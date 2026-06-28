%% =============================================================================
%% src/orchestrator/agent_orchestrator.erl
%%
%% Core pipeline runner.
%%
%% Receives: AgentId + Query + Ctx
%% 1. Looks up the agent definition (workflow + tools)
%% 2. Registers the agent's tools into the tool registry for this run
%% 3. Executes each workflow step in order
%% 4. Each step gets its own LLM profile from the workflow config
%%
%% PARALLEL EXECUTION
%%   run_all/1 — runs many agents concurrently, up to max_parallel_agents.
%%   Each agent runs in its own process; results are collected with a timeout.
%%
%% PER-STEP LLM SELECTION:
%%   workflow = [
%%     #{step => intent,  llm_profile => claude_fast},    ← Claude Haiku
%%     #{step => plan,    llm_profile => claude_fast},    ← Claude Haiku
%%     #{step => execute, llm_profile => none},           ← no LLM
%%     #{step => format,  llm_profile => claude_standard} ← Claude Sonnet
%%   ]
%% =============================================================================

-module(agent_orchestrator).
-behaviour(gen_server).

-export([start_link/0, run/3, run_all/1, run_all/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% ---------------------------------------------------------------------------
%% run/3 — run a single agent, returns {ok, Result} | {error, Reason}
%% ---------------------------------------------------------------------------
run(AgentId, Query, Ctx) ->
  Timeout = af_config:get(pipeline_timeout_ms),
  gen_server:call(?MODULE, {run, AgentId, Query, Ctx}, Timeout).

%% ---------------------------------------------------------------------------
%% run_all/1,2 — run multiple agents in parallel, returns a result per agent.
%%
%%   Results = agent_orchestrator:run_all([
%%     {hims_agent, <<"Get patient count">>},
%%     {mis_agent,  <<"Get department summary">>},
%%     {lims_agent, <<"Get pending lab tests">>}
%%   ]).
%%   %% Returns:
%%   %% #{
%%   %%   hims_agent => {ok, <<"...">>},
%%   %%   mis_agent  => {ok, <<"...">>},
%%   %%   lims_agent => {error, rate_limited}
%%   %% }
%%
%% Each agent runs in its own process. Max concurrent agents is capped by
%% max_parallel_agents config (default 10). If the list is larger it is
%% chunked and each chunk runs concurrently.
%%
%% run_all/2 accepts a shared context map applied to all agents:
%%   agent_orchestrator:run_all(Agents, #{user_id => <<"u1">>}).
%% ---------------------------------------------------------------------------
run_all(Agents) ->
  run_all(Agents, #{}).

run_all(Agents, Ctx) when is_list(Agents) ->
  Timeout    = af_config:get(pipeline_timeout_ms),
  MaxParallel = af_config:get(max_parallel_agents),
  Chunks     = chunk(Agents, MaxParallel),
  lists:foldl(fun(Chunk, Acc) ->
    ChunkResults = run_chunk(Chunk, Ctx, Timeout),
    maps:merge(Acc, ChunkResults)
  end, #{}, Chunks).

%% ---------------------------------------------------------------------------

init([]) -> {ok, #{}}.

handle_call({run, AgentId, Query, Ctx}, From, State) ->
  spawn_link(fun() ->
    Result = execute_pipeline(AgentId, Query, Ctx),
    gen_server:reply(From, Result)
  end),
  {noreply, State}.

handle_cast(_Msg, State) -> {noreply, State}.
handle_info(_Info, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.

%% =============================================================================
%% PIPELINE EXECUTION
%% =============================================================================

execute_pipeline(AgentId, Query, Ctx) ->
  ReqId = maps:get(req_id, Ctx, af_lib:req_id()),
  af_logger:info(pipeline_start, #{agent => AgentId, req_id => ReqId, query => Query}),

  case agent_registry:lookup(AgentId) of
    {error, Reason} ->
      {error, Reason};

    {ok, AgentDef} ->
      case rate_limiter:check(maps:get(role, Ctx, guest)) of
        {error, rate_limited} ->
          {error, rate_limited};

        ok ->
          Ctx1     = session_mgr:enrich(Ctx),
          Workflow = maps:get(workflow, AgentDef),
          Tools    = maps:get(tools,    AgentDef),

          ok = tool_registry:load_for_run(AgentId, Tools),

          Result = case Workflow of
            #{mode := react, llm_profile := ReactProfile} ->
              agent_react:run(Query, AgentDef, Ctx1, ReactProfile);
            Steps when is_list(Steps) ->
              run_steps(Steps, Query, AgentDef, Ctx1, #{})
          end,

          session_mgr:record(Ctx1, Query, Result),

          af_logger:info(pipeline_done, #{
            agent  => AgentId,
            req_id => ReqId,
            status => status_of(Result)
          }),
          Result
      end
  end.

%% ---------------------------------------------------------------------------
%% run_steps/5 — execute each workflow step in sequence
%% ---------------------------------------------------------------------------
run_steps([], _Query, _AgentDef, _Ctx, StepAcc) ->
  case maps:get(format, StepAcc, undefined) of
    undefined -> {error, no_format_output};
    Output    -> {ok, Output}
  end;

run_steps([#{step := StepName, llm_profile := LLMProfile} | Rest],
          Query, AgentDef, Ctx, StepAcc) ->

  af_logger:info(step_start, #{
    agent   => maps:get(id, AgentDef),
    step    => StepName,
    profile => LLMProfile
  }),

  StepResult = run_step(StepName, LLMProfile, Query, AgentDef, Ctx, StepAcc),

  case StepResult of
    {ok, StepOutput} ->
      NewAcc = maps:put(StepName, StepOutput, StepAcc),
      run_steps(Rest, Query, AgentDef, Ctx, NewAcc);
    {error, _} = Err ->
      af_logger:error(step_failed, #{step => StepName, err => Err}),
      Err
  end.

run_step(intent,  LLMProfile, Query,  AgentDef, Ctx, _StepAcc) ->
  agent_intent:run(Query, AgentDef, Ctx, LLMProfile);
run_step(plan,    LLMProfile, _Query, AgentDef, Ctx,  StepAcc) ->
  agent_planner:run(maps:get(intent, StepAcc), AgentDef, Ctx, LLMProfile);
run_step(execute, _,          _Query, AgentDef, _Ctx, StepAcc) ->
  agent_executor:run(maps:get(plan, StepAcc), AgentDef);
run_step(format,  LLMProfile, Query,  AgentDef, Ctx,  StepAcc) ->
  agent_formatter:run(Query, maps:get(plan, StepAcc),
                      maps:get(execute, StepAcc), AgentDef, Ctx, LLMProfile);
run_step(Unknown, _, _, _, _, _) ->
  af_logger:error(unknown_step, #{step => Unknown}),
  {error, {unknown_workflow_step, Unknown}}.

%% =============================================================================
%% PARALLEL HELPERS
%% =============================================================================

%% Run one chunk of agents concurrently, collect all results.
run_chunk(Chunk, Ctx, Timeout) ->
  Parent = self(),
  Pids   = lists:map(fun({AgentId, Query}) ->
    Pid = spawn_link(fun() ->
      Result = execute_pipeline(AgentId, Query, Ctx),
      Parent ! {agent_result, AgentId, Result}
    end),
    {AgentId, Pid}
  end, Chunk),
  collect_results(Pids, Timeout, #{}).

collect_results([], _Timeout, Acc) ->
  Acc;
collect_results(Pids, Timeout, Acc) ->
  receive
    {agent_result, AgentId, Result} ->
      Remaining = lists:keydelete(AgentId, 1, Pids),
      collect_results(Remaining, Timeout, maps:put(AgentId, Result, Acc))
  after Timeout ->
    %% Mark timed-out agents and return what we have
    lists:foldl(fun({AgentId, _Pid}, A) ->
      maps:put(AgentId, {error, timeout}, A)
    end, Acc, Pids)
  end.

%% Split a list into chunks of size N.
chunk([], _N) -> [];
chunk(List, N) ->
  {Head, Tail} = lists:split(min(N, length(List)), List),
  [Head | chunk(Tail, N)].

status_of({ok, _})    -> ok;
status_of({error, _}) -> error.
