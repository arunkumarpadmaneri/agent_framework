%% =============================================================================
%% src/orchestrator/agent_executor.erl
%%
%% Workflow Step: EXECUTE
%%
%% Runs tools from the plan. No LLM involved.
%% Supports single, sequential, and parallel execution.
%%
%% Returns: {ok, #{step_id => Data}} | {error, Reason}
%% =============================================================================

-module(agent_executor).
-export([run/2]).

run(Plan, AgentDef) ->
  #{mode := Mode, steps := Steps} = Plan,
  AgentId = maps:get(id, AgentDef),
  af_logger:info(execute_start, #{agent => AgentId, mode => Mode, steps => length(Steps)}),
  case Mode of
    single     -> run_single(hd(Steps), AgentId);
    sequential -> run_sequential(Steps, AgentId, #{});
    parallel   -> run_parallel(Steps, AgentId);
    _          when length(Steps) =:= 1 -> run_single(hd(Steps), AgentId);
    _          -> run_parallel(Steps, AgentId)
  end.

%% ── SINGLE ───────────────────────────────────────────────────────────────────

run_single(#{step_id := Id, tool := Tool, params := Params}, AgentId) ->
  case tool_registry:execute(AgentId, Tool, Params) of
    {ok, Data}      -> {ok, #{Id => Data}};
    {error, Reason} -> {error, {tool_failed, Tool, Reason}}
  end.

%% ── SEQUENTIAL ───────────────────────────────────────────────────────────────

run_sequential([], _AgentId, Acc) ->
  {ok, Acc};

run_sequential([#{step_id := Id, tool := Tool, params := Params} | Rest], AgentId, Acc) ->
  %% Inject all previous results under 'prev' so later tools can reference them
  EnrichedParams = maps:put(<<"prev">>, Acc, Params),
  case tool_registry:execute(AgentId, Tool, EnrichedParams) of
    {ok, Data}      -> run_sequential(Rest, AgentId, maps:put(Id, Data, Acc));
    {error, Reason} ->
      af_logger:error(sequential_failed, #{tool => Tool, reason => Reason}),
      {error, {tool_failed, Tool, Reason}}
  end.

%% ── PARALLEL ─────────────────────────────────────────────────────────────────

run_parallel(Steps, AgentId) ->
  Parent  = self(),
  Timeout = af_config:get(pipeline_timeout_ms),

  StepIds = lists:map(fun(#{step_id := Id, tool := Tool, params := Params}) ->
    spawn_link(fun() ->
      Result = tool_registry:execute(AgentId, Tool, Params),
      Parent ! {step_done, Id, Result}
    end),
    Id
  end, Steps),

  collect(StepIds, #{}, Timeout).

collect([], Acc, _) -> {ok, Acc};
collect(Pending, Acc, Timeout) ->
  receive
    {step_done, Id, {ok, Data}} ->
      collect(lists:delete(Id, Pending), maps:put(Id, Data, Acc), Timeout);
    {step_done, Id, {error, R}} ->
      af_logger:error(parallel_step_failed, #{step => Id, reason => R}),
      collect(lists:delete(Id, Pending), maps:put(Id, {error, R}, Acc), Timeout)
  after Timeout ->
    af_logger:error(parallel_timeout, #{pending => Pending}),
    {ok, Acc}  %% partial results — never hang
  end.
