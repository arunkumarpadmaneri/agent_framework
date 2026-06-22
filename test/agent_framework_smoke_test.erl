-module(agent_framework_smoke_test).
-include_lib("eunit/include/eunit.hrl").

%% Smoke tests for the agent_framework runtime.
%% These tests verify that the OTP application starts and the agent/tool
%% registries are populated from domain config files.

application_start_test() ->
    {ok, _Started} = application:ensure_all_started(agent_framework),
    ok.

agent_registry_smoke_test() ->
    ok = ensure_app_started(),
    Agents = agent_framework:agents(),
    ?assert(lists:member(mis_agent, Agents)),
    ?assert(lists:member(hims_agent, Agents)),
    ?assert(lists:member(order_agent, Agents)).

agent_tools_smoke_test() ->
    ok = ensure_app_started(),
    {ok, Tools} = agent_framework:tools(mis_agent),
    ?assert(lists:member(get_revenue, Tools)),
    ?assert(lists:member(get_mis_report, Tools)).

integration_run_smoke_test() ->
    setup_mock_run(),
    {ok, Response} = agent_framework:run(test_agent, <<"Hello mock">>, #{role => guest, user_id => <<"test_user">>}),
    ?assertEqual(<<"Mock formatted response">>, Response),
    cleanup_mock_run().

setup_mock_run() ->
    _ = application:set_env(agent_framework, llm_profiles, [
      {mock_profile, [
        {provider, test},
        {api_key, <<"dummy-key">>},
        {model, <<"test-model">>},
        {max_tokens, 256},
        {temperature, 0.0},
        {timeout_ms, 5000}
      ]}
    ]),
    _ = application:set_env(agent_framework, tool_modules, [test_tools]),
    ok = ensure_app_started(),
    AgentDef = #{
      id => test_agent,
      domain => test,
      description => <<"Test agent for run/3 integration">>,
      tools => [mock_tool],
      intent_prompt => <<"Test intent prompt">>,
      format_prompt => <<"Test format prompt">>,
      workflow => [
        #{step => intent, llm_profile => mock_profile},
        #{step => plan, llm_profile => mock_profile},
        #{step => execute, llm_profile => none},
        #{step => format, llm_profile => mock_profile}
      ]
    },
    ok = agent_registry:register(AgentDef),
    ok.

cleanup_mock_run() ->
    ok = agent_registry:unregister(test_agent),
    ok.

ensure_app_started() ->
    case application:ensure_all_started(agent_framework) of
        {ok, _Started} -> ok;
        {error, {already_started, agent_framework}} -> ok;
        {error, Reason} -> exit({failed_to_start, Reason})
    end.
