%% =============================================================================
%% src/llm/llm_test_adapter.erl
%% Test adapter for mock LLM responses in integration tests.
%% =============================================================================
-module(llm_test_adapter).
-export([complete/3]).

complete(_Messages, System, _Config) ->
  case binary:match(System, <<"execution planner">>) of
    {_, _} ->
      {ok, <<"{\"mode\":\"single\",\"steps\":[{\"step_id\":\"step_1\",\"tool\":\"mock_tool\",\"params\":{}}]}">>};
    nomatch ->
      case binary:match(System, <<"format">>) of
        {_, _} -> {ok, <<"Mock formatted response">>};
        nomatch -> {ok, <<"{\"intent\":\"mock_action\",\"entities\":{},\"confidence\":0.95}">>}
      end
  end.
