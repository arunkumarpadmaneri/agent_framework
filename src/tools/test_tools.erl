%% =============================================================================
%% src/tools/test_tools.erl
%% Test-only tool module for agent_framework integration tests.
%% =============================================================================
-module(test_tools).
-export([mock_tool/1, schemas/0]).

schemas() ->
  [
    {mock_tool, #{
      function => mock_tool,
      description => <<"Mock tool returning fixed data">>,
      input => #{value => <<"optional string">>},
      output => #{result => <<"string">>}
    }}
  ].

mock_tool(_Params) ->
  {ok, #{result => <<"mock result">>}}.
