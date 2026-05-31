%% =============================================================================
%% src/llm/llm_claude.erl
%%
%% Anthropic Claude adapter
%% =============================================================================

-module(llm_claude).
-export([complete/3]).

complete(Messages, System, Config) ->
  Body = jsx:encode(#{
    model       => maps:get(model,       Config, <<"claude-sonnet-4-20250514">>),
    max_tokens  => maps:get(max_tokens,  Config, 2048),
    temperature => maps:get(temperature, Config, 0.0),
    system      => System,
    messages    => Messages
  }),
  Headers = [
    {"x-api-key",         binary_to_list(maps:get(api_key, Config))},
    {"anthropic-version", "2023-06-01"},
    {"content-type",      "application/json"}
  ],
  llm_http:post("https://api.anthropic.com/v1/messages", Headers, Body,
    maps:get(timeout_ms, Config, 30000),
    fun(R) ->
      #{<<"content">> := [#{<<"text">> := T}|_]} = jsx:decode(R, [return_maps]),
      {ok, T}
    end).
