%% =============================================================================
%% src/tools/test_tools.erl
%%
%% Mock tool module used by the framework's own test suite.
%% Shows the exact contract a real app's tool module must satisfy:
%%   - Export schemas/0 returning [{tool_name, SchemaMap}]
%%   - Each SchemaMap has a 'function' key naming the implementing function
%%   - Each function takes a params map, returns {ok, Data} | {error, Reason}
%%
%% Real apps put their own tool modules in their codebase and point the
%% framework at them via {tool_modules, [my_tools, other_tools]} in sys.config.
%% =============================================================================
-module(test_tools).
-export([mock_tool/1, get_info/1, list_records/1, schemas/0]).

schemas() ->
  [
    {mock_tool, #{
      function    => mock_tool,
      description => <<"Returns a fixed mock result. Use for basic pipeline smoke tests.">>,
      input       => #{value => <<"optional string">>},
      output      => #{result => <<"string">>}
    }},
    {get_info, #{
      function    => get_info,
      description => <<"Fetch info for a given id. Simulates a data-lookup tool.">>,
      input       => #{id => <<"required string identifier">>},
      output      => #{id => <<"string">>, name => <<"string">>, status => <<"string">>}
    }},
    {list_records, #{
      function    => list_records,
      description => <<"List records optionally filtered by category.">>,
      input       => #{category => <<"optional, default 'all'">>},
      output      => #{category => <<"string">>, items => <<"list">>, total => <<"integer">>}
    }}
  ].

mock_tool(_Params) ->
  {ok, #{result => <<"mock result">>}}.

get_info(Params) ->
  Id = maps:get(<<"id">>, Params, <<"1">>),
  {ok, #{id => Id, name => <<"Test Item">>, status => <<"active">>}}.

list_records(Params) ->
  Category = maps:get(<<"category">>, Params, <<"all">>),
  {ok, #{category => Category, items => [<<"record_1">>, <<"record_2">>], total => 2}}.
