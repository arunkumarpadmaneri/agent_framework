%% =============================================================================
%% src/llm/llm_http.erl
%%
%% Shared HTTP helper for LLM adapters
%% =============================================================================

-module(llm_http).
-export([post/5]).

%% http_post(URL, Headers, Body, Timeout, ParseFun)
post(URL, Headers, Body, Timeout, ParseFun) ->
  case httpc:request(post, {URL, Headers, "application/json", Body},
                     [{timeout, Timeout}, {connect_timeout, 5000}], []) of
    {ok, {{_, 200, _}, _, Resp}} ->
      try ParseFun(list_to_binary(Resp))
      catch _:E -> {error, {parse_failed, E}}
      end;
    {ok, {{_, 429, _}, _, _}}  -> {error, rate_limited};
    {ok, {{_, 401, _}, _, _}}  -> {error, auth_failed};
    {ok, {{_, C,   _}, _, B}}  -> {error, {http, C, B}};
    {error, timeout}           -> {error, timeout};
    {error, R}                 -> {error, R}
  end.
