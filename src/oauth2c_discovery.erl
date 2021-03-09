%% Copyright (c) 2021 Bryan Frimin <bryan@frimin.fr>.
%%
%% Permission to use, copy, modify, and/or distribute this software for any
%% purpose with or without fee is hereby granted, provided that the above
%% copyright notice and this permission notice appear in all copies.
%%
%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
%% SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR
%% IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

-module(oauth2c_discovery).

-export([authorization_server_metadata_definition/0,
         discover/1, discover/2]).

-export_type([authorization_server_metadata/0,
              discover_error_reason/0]).

-type authorization_server_metadata() ::
        #{issuer :=
            oauth2c:issuer(),
          authorization_endpoint =>
            binary(),
          token_endpoint =>
            binary(),
          jwks_uri =>
            binary(),
          registration_endpoint =>
            binary(),
          scopes_supported =>
            [binary()],
          response_types_supported :=
            [binary()],
          response_modes_supported =>
            [binary()],
          grant_types_supported =>
            [binary()],
          token_endpoint_auth_methods_supported =>
            [binary()],
          token_endpoint_auth_signing_alg_values_supported =>
            [binary()],
          service_documentation =>
            binary(),
          ui_locales_supported =>
            [binary()],
          op_policy_uri =>
            binary(),
          op_tos_uri =>
            binary(),
          revocation_endpoint =>
            binary(),
          revocation_endpoint_auth_methods_supported =>
            [binary()],
          revocation_endpoint_auth_signing_alg_values_supported =>
            [binary()],
          introspection_endpoint =>
            binary(),
          introspection_endpoint_auth_methods_supported =>
            [binary()],
          introspection_endpoint_auth_signing_alg_values_supported =>
            [binary()],
          code_challenge_methods_supported =>
            [binary()]}.

-type discover_error_reason() ::
        {bas_resp_code, integer()}
      | {httpc, term()}
      | {invalid_syntax, term()}
      | {invalid_metadata, term()}
      | {bad_issuer, oauth2c:issuer(), binary()}.

-spec authorization_server_metadata_definition() ->
        jsv:definition().
authorization_server_metadata_definition() ->
  {object,
   #{members =>
       #{issuer => uri,
         authorization_endpoint => uri,
         token_endpoint => uri,
         jwks_uri => uri,
         registration_endpoint => uri,
         scopes_supported => {array, #{element => string}},
         response_types_supported => {array, #{element => string}},
         response_modes_supported => {array, #{element => string}},
         grant_types_supported => {array, #{element => string}},
         token_endpoint_auth_methods_supported =>
           {array, #{element => string}},
         token_endpoint_auth_signing_alg_values_supported =>
           {array, #{element => string}},
         service_documentation => uri,
         ui_locales_supported => {array, #{element => string}},
         op_policy_uri => uri,
         op_tos_uri => uri,
         revocation_endpoint => uri,
         revocation_endpoint_auth_methods_supported =>
           {array, #{element => string}},
         revocation_endpoint_auth_signing_alg_values_supported =>
           {array, #{element => string}},
         introspection_endpoint => uri,
         introspection_endpoint_auth_methods_supported =>
           {array, #{element => string}},
         introspection_endpoint_auth_signing_alg_values_supported =>
           {array, #{element => string}},
         code_challenge_methods_supported => {array, #{element => string}}},
     required =>
       [issuer, response_types_supported]}}.

-spec discover(oauth2c:issuer()) ->
        {ok, authorization_server_metadata()} |
        {error, discover_error_reason()}.
discover(Issuer) ->
  discover(Issuer, <<".well-known/oauth-authorization-server">>).

-spec discover(oauth2c:issuer(), Suffix :: binary()) ->
        {ok, authorization_server_metadata()} |
        {error, discover_error_reason()}.
discover(Issuer, Suffix) ->
  Endpoint = discovery_uri(Issuer, Suffix),
  case httpc:request(get, {Endpoint, []}, [], [{body_format, binary}]) of
    {ok, {{_, 200, "OK"}, _, Response}} ->
      case parse_metadata(Response) of
        {ok, #{issuer := Issuer} = MD} ->
          {ok, MD};
        {ok, #{issuer := Value}} ->
          {error, {bad_issuer, Issuer, Value}};
        {error, Reason} ->
          {error, Reason}
      end;
    {ok, {{_, Code, _}, _, _}} ->
      {error, {bad_resp_code, Code}};
    {error, Reason} ->
      {error, {httpc, Reason}}
  end.

-spec parse_metadata(binary()) ->
        {ok, authorization_server_metadata()} |
        {error, term()}.
parse_metadata(Bin) ->
  case json:parse(Bin) of
    {ok, Data} ->
      Definition = authorization_server_metadata_definition(),
      Options = #{unknown_member_handling => keep,
                  disable_verification => true,
                  null_member_handling => remove},
      case jsv:validate(Data, Definition, Options) of
        {ok, Metadata} ->
          {ok, Metadata};
        {error, Reason} ->
          {error, {invalid_metadata, Reason}}
      end;
    {error, Reason} ->
      {error, {invalid_syntax, Reason}}
  end.

-spec discovery_uri(oauth2c:issuer(), Suffix :: binary()) ->
        binary().
discovery_uri(Issuer0, Suffix) ->
  Clean = fun (<<$/, Rest/binary>>) -> Rest;
              (Bin) -> Bin
          end,
  Issuer = uri_string:parse(Issuer0),
  Path = filename:join(Suffix, Clean(maps:get(path, Issuer, <<>>))),
  DiscoveryURI = Issuer#{path => Path},
  uri_string:normalize(DiscoveryURI).
