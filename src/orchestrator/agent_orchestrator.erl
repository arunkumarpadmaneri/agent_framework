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
%% PER-STEP LLM SELECTION:
%%   workflow = [
%%     #{step => intent,  llm_profile => claude_fast},   ← uses Claude Haiku
%%     #{step => plan,    llm_profile => claude_fast},   ← uses Claude Haiku
%%     #{step => execute, llm_profile => none},          ← no LLM
%%     #{step => format,  llm_profile => claude_standard} ← uses Claude Sonnet
%%   ]
%%   llm_router:call(Profile, Messages, Prompt) resolves profile → adapter
%%
%% WHY GenServer + spawn_link per request?
%%   GenServer stays responsive — never blocks waiting for LLM.
%%   Each request is isolated — one crash cannot affect another.
%% =============================================================================

-module(agent_orchestrator).
-behaviour(gen_server).

-export([start_link/0, run/3]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% ---------------------------------------------------------------------------
%% run/3 — entry point called by agent_framework:run/3
%% ---------------------------------------------------------------------------
run(AgentId, Query, Ctx) ->
  Timeout = application:get_env(agent_framework, pipeline_timeout_ms, 60000),
  gen_server:call(?MODULE, {run, AgentId, Query, Ctx}, Timeout).

init([]) -> {ok, #{}}.

handle_call({run, AgentId, Query, Ctx}, From, State) ->
  %% Spawn a linked process per request — GenServer never blocks
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

  %% Step 0 — validate agent exists
  case agent_registry:lookup(AgentId) of
    {error, Reason} ->
      {error, Reason};

    {ok, AgentDef} ->
      %% Step 0b — rate limit check
      case rate_limiter:check(maps:get(role, Ctx, guest)) of
        {error, rate_limited} ->
          {error, rate_limited};

        ok ->
          %% Step 0c — enrich context with session history
          Ctx1     = session_mgr:enrich(Ctx),
          Workflow = maps:get(workflow, AgentDef),
          Tools    = maps:get(tools,    AgentDef),

          %% Step 0d — load this agent's tools into registry
          ok = tool_registry:load_for_run(AgentId, Tools),

          %% Dispatch: react loop or fixed step pipeline
          Result = case Workflow of
            #{mode := react, llm_profile := ReactProfile} ->
              agent_react:run(Query, AgentDef, Ctx1, ReactProfile);
            Steps when is_list(Steps) ->
              run_steps(Steps, Query, AgentDef, Ctx1, #{})
          end,

          %% Save exchange to session
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
%%
%% Steps is the ordered workflow list from the agent definition.
%% StepAcc accumulates outputs from each step for use by later steps.
%%
%% The pipeline carries forward:
%%   StepAcc = #{
%%     intent  => IntentMap,       %% set after intent step
%%     plan    => PlanMap,         %% set after plan step
%%     results => ToolResultMap    %% set after execute step
%%   }
%% ---------------------------------------------------------------------------
run_steps([], _Query, _AgentDef, _Ctx, StepAcc) ->
  %% All steps done — final output is the format step result
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

  %% Run the step — each step module gets (Query, AgentDef, Ctx, StepAcc, LLMProfile)
  StepResult = run_step(StepName, LLMProfile, Query, AgentDef, Ctx, StepAcc),

  case StepResult of
    {ok, StepOutput} ->
      %% Accumulate this step's output and continue
      NewAcc = maps:put(StepName, StepOutput, StepAcc),
      run_steps(Rest, Query, AgentDef, Ctx, NewAcc);

    {error, _} = Err ->
      %% Step failed — abort pipeline, return error
      af_logger:error(step_failed, #{step => StepName, err => Err}),
      Err
  end.

%% ---------------------------------------------------------------------------
%% run_step/6 — dispatch to the correct step module
%% ---------------------------------------------------------------------------

%% INTENT STEP — classify query using agent's intent LLM profile
run_step(intent, LLMProfile, Query, AgentDef, Ctx, _StepAcc) ->
  agent_intent:run(Query, AgentDef, Ctx, LLMProfile);

%% PLAN STEP — build execution plan from intent
run_step(plan, LLMProfile, _Query, AgentDef, Ctx, StepAcc) ->
  Intent = maps:get(intent, StepAcc),
  agent_planner:run(Intent, AgentDef, Ctx, LLMProfile);

%% EXECUTE STEP — run tools, no LLM involved
run_step(execute, _LLMProfile, _Query, AgentDef, _Ctx, StepAcc) ->
  Plan = maps:get(plan, StepAcc),
  agent_executor:run(Plan, AgentDef);

%% FORMAT STEP — format results using agent's format LLM profile
run_step(format, LLMProfile, Query, AgentDef, Ctx, StepAcc) ->
  Plan    = maps:get(plan,    StepAcc),
  Results = maps:get(execute, StepAcc),
  agent_formatter:run(Query, Plan, Results, AgentDef, Ctx, LLMProfile);

%% Unknown step — config error
run_step(Unknown, _, _, _, _, _) ->
  af_logger:error(unknown_step, #{step => Unknown}),
  {error, {unknown_workflow_step, Unknown}}.

status_of({ok, _})    -> ok;
status_of({error, _}) -> error.
