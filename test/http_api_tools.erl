%% =============================================================================
%% src/tools/http_api_tools.erl
%% HTTP API call tool with support for bearer/basic auth, JSON, and form-encoded requests.
%% =============================================================================
-module(http_api_tools).
-export([http_get/1, http_post/1, schemas/0]).

schemas() ->
  [
    {http_get, #{
      function => http_get,
      description => <<"Send an HTTP GET request with optional authentication and query params">>,
      input => #{url => <<"required URL">>, headers => <<"optional headers list">>, auth => <<"optional auth map">>, query_params => <<"optional query params map">>},
      output => #{status_code => <<"integer">>, headers => <<"list">>, body => <<"binary">>}
    }},
    {http_post, #{
      function => http_post,
      description => <<"Send an HTTP POST request with JSON or form-encoded body and optional authentication">>,
      input => #{url => <<"required URL">>, headers => <<"optional headers list">>, auth => <<"optional auth map">>, body => <<"optional body map or binary">>, content_type => <<"optional content type">>},
      output => #{status_code => <<"integer">>, headers => <<"list">>, body => <<"binary">>}
    }}
  ].

http_get(Params) when is_map(Params) ->
  request(get, Params).

http_post(Params) when is_map(Params) ->
  request(post, Params).

request(Method, Params) ->
  Url = maps:get(<<"url">>, Params, <<"">>),
  QueryParams = maps:get(<<"query_params">>, Params, undefined),
  FullUrl = append_query_params(Url, QueryParams),
  Headers = build_headers(maps:get(<<"headers">>, Params, []), maps:get(<<"auth">>, Params, undefined)),
  Timeout = maps:get(<<"timeout">>, Params, 15000),
  Request = case Method of
    get -> {FullUrl, Headers};
    post ->
      ContentType = maps:get(<<"content_type">>, Params, <<"application/json">>),
      Body = build_body(maps:get(<<"body">>, Params, <<"">>), ContentType),
      {FullUrl, Headers, ContentType, Body}
  end,
  case httpc:request(Method, Request, [], [{body_format, binary}, {timeout, Timeout}]) of
    {ok, {{_, Code, _}, RespHeaders, ResponseBody}} ->
      {ok, #{status_code => Code, headers => RespHeaders, body => ResponseBody}};
    {error, Reason} ->
      {error, Reason}
  end.

append_query_params(Url, undefined) -> Url;
append_query_params(Url, QueryParams) when is_map(QueryParams) ->
  QueryString = encode_query_params(maps:to_list(QueryParams)),
  case binary:match(Url, <<"?">>) of
    nomatch -> <<Url/binary, "?", QueryString/binary>>;
    {_, _} -> <<Url/binary, "&", QueryString/binary>>
  end;
append_query_params(Url, _) -> Url.

encode_query_params([]) -> <<>>;
encode_query_params([{Key, Value} | Rest]) ->
  EncodedKey = url_encode_term(Key),
  EncodedValue = url_encode_term(Value),
  Encoded = <<EncodedKey/binary, "=", EncodedValue/binary>>,
  case Rest of
    [] -> Encoded;
    _ ->
      Tail = encode_query_params(Rest),
      <<Encoded/binary, "&", Tail/binary>>
  end.

url_encode_term(Value) when is_binary(Value) -> url_encode_binary(Value);
url_encode_term(Value) when is_list(Value) -> url_encode_binary(list_to_binary(Value));
url_encode_term(Value) when is_integer(Value) -> url_encode_binary(integer_to_binary(Value));
url_encode_term(Value) -> url_encode_binary(list_to_binary(io_lib:format("~p", [Value]))).

url_encode_binary(Binary) ->
  %% Minimal URL-encoding for form bodies and query strings.
  re:replace(Binary,
             <<"[ !#\$%&'()*+,/:;=?@\[\]\\^`{|}~]">>,
             fun(S) -> percent_encode(S) end,
             [global, {return, binary}]).

percent_encode(Bin) when is_binary(Bin) ->
  [Byte] = binary_to_list(Bin),
  list_to_binary(io_lib:format("~2.16.0B", [Byte])).

build_body(Body, <<"application/x-www-form-urlencoded">>) when is_map(Body) ->
  encode_query_params(maps:to_list(Body));
build_body(Body, <<"application/x-www-form-urlencoded">>) when is_list(Body) ->
  encode_query_params(Body);
build_body(Body, <<"application/json">>) when is_map(Body) ->
  jsx:encode(Body);
build_body(Body, <<"application/json">>) when is_list(Body) ->
  jsx:encode(Body);
build_body(Body, _) when is_binary(Body) -> Body;
build_body(Body, _) when is_list(Body) -> list_to_binary(Body);
build_body(_, _) -> <<>>.

build_headers(Headers, undefined) -> headers_to_list(Headers);
build_headers(Headers, #{"type" := <<"bearer">>, "token" := Token}) ->
  [{<<"authorization">>, <<"Bearer ", Token/binary>>} | headers_to_list(Headers)];
build_headers(Headers, #{"type" := <<"basic">>, "username" := User, "password" := Pass}) ->
  Token = base64:encode_to_string(<<User/binary, ":", Pass/binary>>),
  [{<<"authorization">>, <<"Basic ", Token/binary>>} | headers_to_list(Headers)];
build_headers(Headers, _) -> headers_to_list(Headers).

headers_to_list(Headers) when is_map(Headers) ->
  [ {list_to_binary(Key), list_to_binary(Value)} || {Key, Value} <- maps:to_list(Headers)];
headers_to_list(Headers) when is_list(Headers) -> Headers;
headers_to_list(_) -> [].
