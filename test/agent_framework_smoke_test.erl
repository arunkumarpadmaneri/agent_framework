%% =============================================================================
%% test/agent_framework_smoke_test.erl
%%
%% Framework integration tests — no real LLM calls, no external services.
%% All tests use llm_test_adapter (provider=test) and test_tools.
%%
%% Test coverage:
%%   1. application_start         — OTP app boots cleanly
%%   2. agent_registration        — register/lookup/list/unregister
%%   3. tool_execution            — tool_registry loads and calls a tool directly
%%   4. fixed_pipeline            — full intent→plan→execute→format pipeline
%%   5. react_loop                — ReAct loop: tool call → observe → answer
%%   6. unknown_agent_error       — run/3 returns {error,_} for missing agent
%%   7. react_tool_call_twice     — loop calls two different tools before answering
%% =============================================================================
-module(agent_framework_smoke_test).
-include_lib("eunit/include/eunit.hrl").

%% ---------------------------------------------------------------------------
%% 1. App startup
%% ---------------------------------------------------------------------------
application_start_test() ->
  {ok, _} = application:ensure_all_started(agent_framework),
  ok.

%% ---------------------------------------------------------------------------
%% 2. Agent registration
%% ---------------------------------------------------------------------------
agent_registration_test() ->
  ok = ensure_app_started(),
  Def = test_agent_def(reg_agent, fixed),
  ok  = agent_registry:register(Def),
  {ok, Got} = agent_registry:lookup(reg_agent),
  ?assertEqual(reg_agent, maps:get(id, Got)),
  ?assert(lists:member(reg_agent, agent_framework:agents())),
  ok = agent_registry:unregister(reg_agent),
  ?assertEqual({error, {unknown_agent, reg_agent}}, agent_registry:lookup(reg_agent)).

%% ---------------------------------------------------------------------------
%% 3. Tool loading and direct execution
%% ---------------------------------------------------------------------------
tool_execution_test() ->
  setup_mock_env(),
  ok = ensure_app_started(),
  ok = tool_registry:load_for_run(tool_test_agent, [mock_tool, get_info, list_records]),
  {ok, R1} = tool_registry:execute(tool_test_agent, mock_tool, #{}),
  ?assertEqual(<<"mock result">>, maps:get(result, R1)),
  {ok, R2} = tool_registry:execute(tool_test_agent, get_info, #{<<"id">> => <<"42">>}),
  ?assertEqual(<<"42">>,      maps:get(id,     R2)),
  ?assertEqual(<<"active">>,  maps:get(status, R2)),
  {ok, R3} = tool_registry:execute(tool_test_agent, list_records, #{<<"category">> => <<"orders">>}),
  ?assertEqual(<<"orders">>,  maps:get(category, R3)),
  ?assertEqual(2,             maps:get(total,    R3)).

%% ---------------------------------------------------------------------------
%% 4. Full fixed pipeline  intent → plan → execute → format
%% ---------------------------------------------------------------------------
fixed_pipeline_test() ->
  with_test_agent(fixed_agent, fixed, fun() ->
    {ok, Response} = agent_framework:run(fixed_agent, <<"show me data">>,
                       #{role => guest, user_id => <<"u1">>}),
    ?assertEqual(<<"Mock formatted response">>, Response)
  end).

%% ---------------------------------------------------------------------------
%% 5. ReAct loop: mock LLM calls a tool on first turn, answers on second
%% ---------------------------------------------------------------------------
react_loop_test() ->
  with_test_agent(react_agent, react, fun() ->
    {ok, Response} = agent_framework:run(react_agent, <<"what is the info?">>,
                       #{role => guest, user_id => <<"u2">>}),
    ?assertEqual(<<"Mock react final answer">>, Response)
  end).

%% ---------------------------------------------------------------------------
%% 6. Unknown agent returns structured error
%% ---------------------------------------------------------------------------
unknown_agent_error_test() ->
  ok = ensure_app_started(),
  Result = agent_framework:run(no_such_agent, <<"hello">>, #{role => guest, user_id => <<"u3">>}),
  ?assertMatch({error, _}, Result).

%% ---------------------------------------------------------------------------
%% 7. ReAct loop — list_records tool called, then answer
%% ---------------------------------------------------------------------------
react_list_records_test() ->
  with_test_agent(react_list_agent, react, fun() ->
    {ok, Response} = agent_framework:run(react_list_agent, <<"list all records">>,
                       #{role => guest, user_id => <<"u4">>}),
    ?assertEqual(<<"Mock react final answer">>, Response)
  end).

%% ===========================================================================
%% Helpers
%% ===========================================================================

%% Run a test with a fresh agent registered and cleaned up after.
with_test_agent(AgentId, Mode, Fun) ->
  setup_mock_env(),
  ok = ensure_app_started(),
  ok = agent_registry:register(test_agent_def(AgentId, Mode)),
  try Fun() after agent_registry:unregister(AgentId) end.

%% Point the framework at mock LLM profile and test_tools.
setup_mock_env() ->
  _ = application:set_env(agent_framework, llm_profiles, [
    {mock_profile, [
      {provider,    test},
      {api_key,     <<"dummy">>},
      {model,       <<"test-model">>},
      {max_tokens,  256},
      {temperature, 0.0},
      {timeout_ms,  5000}
    ]}
  ]),
  _ = application:set_env(agent_framework, tool_modules, [test_tools]).

%% Build a minimal agent definition for the given mode.
test_agent_def(AgentId, fixed) ->
  #{
    id          => AgentId,
    domain      => test,
    description => <<"Test agent — fixed pipeline">>,
    tools       => [mock_tool, get_info, list_records],
    intent_prompt => <<"Test intent prompt">>,
    format_prompt => <<"Test format prompt">>,
    workflow    => [
      #{step => intent,  llm_profile => mock_profile},
      #{step => plan,    llm_profile => mock_profile},
      #{step => execute, llm_profile => none},
      #{step => format,  llm_profile => mock_profile}
    ]
  };
test_agent_def(AgentId, react) ->
  #{
    id          => AgentId,
    domain      => test,
    description => <<"Test agent — ReAct loop">>,
    tools       => [mock_tool, get_info, list_records],
    react_prompt => <<"Test react system prompt">>,
    workflow    => #{mode => react, llm_profile => mock_profile}
  }.

ensure_app_started() ->
  case application:ensure_all_started(agent_framework) of
    {ok, _}                                     -> ok;
    {error, {already_started, agent_framework}} -> ok;
    {error, Reason}                             -> exit({failed_to_start, Reason})
  end.
