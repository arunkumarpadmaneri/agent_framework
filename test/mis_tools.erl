%% =============================================================================
%% src/tools/mis_tools.erl
%% MIS (Management Information System) Tools
%% =============================================================================
-module(mis_tools).
-export([
  revenue/1,
  expenses/1,
  report/1,
  schemas/0
]).

%% Input/Output Schemas
schemas() ->
  [
    {get_revenue, #{
      function => revenue,
      description => <<"Get hospital revenue/income for a period and department">>,
      input => #{period => <<"required, e.g. 'this month'">>, department => <<"optional, default 'all'">>},
      output => #{revenue => <<"number">>, period => <<"string">>, department => <<"string">>}
    }},
    {get_expenses, #{
      function => expenses,
      description => <<"Get hospital expenses/costs for a period and category">>,
      input => #{period => <<"required, e.g. 'this month'">>, category => <<"optional, default 'all'">>},
      output => #{expenses => <<"number">>, period => <<"string">>, category => <<"string">>}
    }},
    {get_mis_report, #{
      function => report,
      description => <<"Get full MIS summary report: revenue, expenses, profit, outstanding">>,
      input => #{period => <<"required, e.g. 'this month'">>},
      output => #{revenue => <<"number">>, expenses => <<"number">>, profit => <<"number">>, outstanding => <<"number">>}
    }}
  ].

%% ---------------------------------------------------------------------------
%% Tool: Get Revenue
%% Input:  {period => string, department => string}
%% Output: {ok, {revenue => number, period => string, department => string}} | {error, Reason}
%% ---------------------------------------------------------------------------
revenue(Params) ->
  Period = maps:get(<<"period">>, Params, <<"this month">>),
  Dept   = maps:get(<<"department">>, Params, <<"all">>),
  hims_mcp:call(get_revenue, #{period => Period, department => Dept}).

%% ---------------------------------------------------------------------------
%% Tool: Get Expenses
%% Input:  {period => string, category => string}
%% Output: {ok, {expenses => number, period => string, category => string}} | {error, Reason}
%% ---------------------------------------------------------------------------
expenses(Params) ->
  Period   = maps:get(<<"period">>, Params, <<"this month">>),
  Category = maps:get(<<"category">>, Params, <<"all">>),
  hims_mcp:call(get_expenses, #{period => Period, category => Category}).

%% ---------------------------------------------------------------------------
%% Tool: Get MIS Report
%% Input:  {period => string}
%% Output: {ok, {revenue => number, expenses => number, profit => number, outstanding => number}} | {error, Reason}
%% ---------------------------------------------------------------------------
report(Params) ->
  Period = maps:get(<<"period">>, Params, <<"this month">>),
  hims_mcp:call(get_mis_report, #{period => Period}).
