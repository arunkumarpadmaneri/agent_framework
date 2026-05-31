%% =============================================================================
%% src/llm/llm_gemini.erl
%%
%% Google Gemini adapter
%% =============================================================================

-module(llm_gemini).
-export([complete/3]).

complete(Messages, System, Config) ->
  ApiKey = maps:get(api_key, Config),
  Model  = maps:get(model, Config, <<"gemini-1.5-pro">>),
  URL    = binary_to_list(iolist_to_binary([
    "https://generativelanguage.googleapis.com/v1beta/models/",
    Model, ":generateContent?key=", ApiKey
  ])),
  LastMsg    = maps:get(<<"content">>, lists:last(Messages), <<>>),
  FullText   = <<System/binary, "\n\n", LastMsg/binary>>,
  Body = jsx:encode(#{contents => [#{parts => [#{text => FullText}]}]}),
  Headers = [{"content-type", "application/json"}],
  llm_http:post(URL, Headers, Body,
    maps:get(timeout_ms, Config, 30000),
    fun(R) ->
      #{<<"candidates">> := [#{<<"content">> :=
          #{<<"parts">> := [#{<<"text">> := T}|_]}}|_]} =
        jsx:decode(R, [return_maps]),
      {ok, T}
    end).
