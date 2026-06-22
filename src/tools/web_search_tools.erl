%% =============================================================================
%% src/tools/web_search_tools.erl
%% Simple web search tool using the DuckDuckGo Instant Answer API.
%% =============================================================================
-module(web_search_tools).
-export([search_web/1, schemas/0]).

schemas() ->
  [
    {web_search, #{
      function => search_web,
      description => <<"Search the web and return the top instant-answer JSON">>,
      input => #{query => <<"required search query">>, region => <<"optional locale, e.g. 'us-en'">>},
      output => #{query => <<"string">>, region => <<"string">>, body => <<"json">>}
    }}
  ].

search_web(Params) when is_map(Params) ->
  Query  = maps:get(<<"query">>, Params, <<"">>),
  Region = maps:get(<<"region">>, Params, <<"us-en">>),
  EncodedQuery = url_encode(Query),
  Url    = <<"https://api.duckduckgo.com/?q=", EncodedQuery/binary,
             "&format=json&no_html=1&skip_disambig=1&kl=", Region/binary>>,
  case httpc:request(get, {Url, []}, [], [{body_format, binary}, {timeout, 15000}]) of
    {ok, {{_, 200, _}, _Headers, Body}} ->
      {ok, #{query => Query, region => Region, body => Body}};
    {ok, {{_, Status, _}, _, Body}} ->
      {error, {http_error, Status, Body}};
    {error, Reason} ->
      {error, Reason}
  end.

url_encode(Bin) when is_binary(Bin) ->
  uri_string:percent_encode(Bin, uri_string:encode_query()).
