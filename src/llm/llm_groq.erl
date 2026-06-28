%% =============================================================================
%% src/llm/llm_groq.erl
%%
%% Groq adapter
%% =============================================================================

-module(llm_groq).
-export([complete/3]).

complete(Messages, System, Config) ->
  AllMsgs = [#{<<"role">> => <<"system">>, <<"content">> => System} | Messages],
  Body = jsx:encode(#{
    model       => maps:get(model,       Config, <<"mixtral-8x7b-32768">>),
    max_tokens  => maps:get(max_tokens,  Config, 2048),
    temperature => maps:get(temperature, Config, 0.0),
    messages    => AllMsgs
  }),
  Headers = [
    {"authorization", "Bearer " ++ binary_to_list(maps:get(api_key, Config))},
    {"content-type",  "application/json"}
  ],
  llm_http:post("https://api.groq.com/openai/v1/chat/completions", Headers, Body,
    maps:get(timeout_ms, Config, 30000),
    fun(R) ->
      #{<<"choices">> := [#{<<"message">> := #{<<"content">> := T}}|_]} =
        jsx:decode(R, [return_maps]),
      {ok, T}
    end).
