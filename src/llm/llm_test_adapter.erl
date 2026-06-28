%% =============================================================================
%% src/llm/llm_test_adapter.erl
%%
%% Mock LLM adapter for the framework's own test suite.
%% Dispatches on the system prompt to return canned responses for each
%% workflow step, without making any real HTTP calls.
%%
%% Fixed pipeline responses:
%%   intent step  → JSON intent map
%%   plan step    → JSON execution plan using mock_tool
%%   format step  → plain text response
%%
%% ReAct loop responses (detected by "AVAILABLE TOOLS" in system prompt):
%%   first call  (no tool result in history) → tool call action
%%   second call (tool result present)       → final answer
%% =============================================================================
-module(llm_test_adapter).
-export([complete/3]).

complete(Messages, System, _Config) ->
  %% Check react FIRST — its system prompt may also contain "format" in schema JSON.
  case binary:match(System, <<"AVAILABLE TOOLS">>) of
    {_, _} ->
      %% ReAct loop — check if a tool result is already in history
      react_response(Messages);
    nomatch ->
      case binary:match(System, <<"execution planner">>) of
        {_, _} ->
          %% Fixed pipeline — plan step
          {ok, <<"{\"mode\":\"single\",\"steps\":[{\"step_id\":\"step_1\",\"tool\":\"mock_tool\",\"params\":{}}]}">>};
        nomatch ->
          case binary:match(System, <<"format">>) of
            {_, _} ->
              %% Fixed pipeline — format step
              {ok, <<"Mock formatted response">>};
            nomatch ->
              %% Fixed pipeline — intent step
              {ok, <<"{\"intent\":\"mock_action\",\"entities\":{},\"confidence\":0.95}">>}
          end
      end
  end.

%% If the conversation already contains a tool result (identified by
%% "\"status\"" in any message), produce a final answer; otherwise call a tool.
react_response(Messages) ->
  HasToolResult = lists:any(fun(M) ->
    Content = maps:get(<<"content">>, M, <<>>),
    binary:match(Content, <<"\"status\"">>) =/= nomatch
  end, Messages),
  case HasToolResult of
    true  -> {ok, <<"{\"answer\":\"Mock react final answer\"}">>};
    false -> {ok, <<"{\"action\":\"mock_tool\",\"params\":{}}">>}
  end.
