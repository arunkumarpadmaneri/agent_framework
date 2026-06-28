%% =============================================================================
%% src/agent_framework.erl
%%
%% PUBLIC API — the only module your application imports.
%%
%% RUNNING AGENTS
%%   agent_framework:run(hims_agent, Query, Ctx)
%%   agent_framework:run_all([{hims_agent, Q1}, {mis_agent, Q2}], Ctx)
%%
%% MANAGING AGENTS AT RUNTIME
%%   agent_framework:add_agent(Def)
%%   agent_framework:remove_agent(hims_agent)
%%   agent_framework:update_agent(hims_agent, #{workflow => ...})
%%
%% MANAGING TOOLS AT RUNTIME
%%   agent_framework:add_agent_tool(hims_agent, my_new_tool)
%%   agent_framework:remove_agent_tool(hims_agent, my_old_tool)
%%
%% INTROSPECTION
%%   agent_framework:agents()
%%   agent_framework:tools(hims_agent)
%% =============================================================================

-module(agent_framework).
-export([
  %% Execute
  run/3,
  run_all/1, run_all/2,

  %% Agent lifecycle
  add_agent/1,
  remove_agent/1,
  update_agent/2,

  %% Tool management
  add_agent_tool/2,
  remove_agent_tool/2,

  %% Introspection
  agents/0,
  tools/1
]).

%% =============================================================================
%% EXECUTE
%% =============================================================================

%% ---------------------------------------------------------------------------
%% run/3 — run a single agent, returns {ok, Response} | {error, Reason}
%%
%%   agent_framework:run(hims_agent, <<"Get patient count">>, #{
%%     role    => doctor,
%%     user_id => <<"u1">>
%%   }).
%% ---------------------------------------------------------------------------
run(AgentId, Query, Ctx) when is_atom(AgentId), is_binary(Query), is_map(Ctx) ->
  agent_orchestrator:run(AgentId, Query, ensure_req_id(Ctx));
run(AgentId, Query, Ctx) ->
  af_logger:error(invalid_run_args, #{
    agent => AgentId, query_type => type_of(Query), ctx_type => type_of(Ctx)
  }),
  {error, invalid_arguments}.

%% ---------------------------------------------------------------------------
%% run_all/1,2 — run multiple agents in parallel.
%%
%%   Results = agent_framework:run_all([
%%     {hims_agent, <<"Get patient count">>},
%%     {mis_agent,  <<"Get department summary">>},
%%     {lims_agent, <<"Get pending lab tests">>}
%%   ]).
%%   %% → #{hims_agent => {ok, <<"...">>}, mis_agent => {ok, <<"...">>}, ...}
%%
%%   %% With shared context
%%   agent_framework:run_all(Agents, #{role => admin, user_id => <<"u1">>}).
%% ---------------------------------------------------------------------------
run_all(Agents) when is_list(Agents) ->
  agent_orchestrator:run_all(Agents, #{}).

run_all(Agents, Ctx) when is_list(Agents), is_map(Ctx) ->
  agent_orchestrator:run_all(Agents, ensure_req_id(Ctx)).

%% =============================================================================
%% AGENT LIFECYCLE
%% =============================================================================

%% ---------------------------------------------------------------------------
%% add_agent/1 — register a new agent at runtime.
%% Takes effect immediately — next run/3 call can use it.
%%
%%   agent_framework:add_agent(#{
%%     id          => pharmacy_agent,
%%     domain      => hospital,
%%     description => <<"Pharmacy and drug management">>,
%%     tools       => [my_pharmacy_tools],
%%     workflow    => workflow_constants:fast_workflow(),
%%     intent_prompt => <<"Extract the user's pharmacy intent.">>,
%%     format_prompt => <<"Format the pharmacy response clearly.">>
%%   }).
%% ---------------------------------------------------------------------------
add_agent(#{id := _} = AgentDef) ->
  agent_registry:register(AgentDef);
add_agent(_) ->
  {error, missing_agent_id}.

%% ---------------------------------------------------------------------------
%% remove_agent/1 — unregister an agent at runtime.
%% In-flight requests for this agent complete normally.
%% New requests after this call return {error, {unknown_agent, AgentId}}.
%%
%%   agent_framework:remove_agent(pharmacy_agent).
%% ---------------------------------------------------------------------------
remove_agent(AgentId) when is_atom(AgentId) ->
  agent_registry:unregister(AgentId).

%% ---------------------------------------------------------------------------
%% update_agent/2 — patch specific fields of a live agent.
%% Only the keys you pass are changed — everything else stays the same.
%%
%%   %% Switch to ReAct loop
%%   agent_framework:update_agent(hims_agent, #{
%%     workflow => workflow_constants:react_workflow(claude_standard)
%%   }).
%%
%%   %% Update intent prompt
%%   agent_framework:update_agent(hims_agent, #{
%%     intent_prompt => <<"New intent prompt.">>
%%   }).
%%
%%   %% Change workflow and tools together
%%   agent_framework:update_agent(hims_agent, #{
%%     workflow => workflow_constants:standard_workflow(),
%%     tools    => [my_hims_tools, my_search_tool]
%%   }).
%% ---------------------------------------------------------------------------
update_agent(AgentId, Changes) when is_atom(AgentId), is_map(Changes) ->
  agent_registry:update(AgentId, Changes).

%% =============================================================================
%% TOOL MANAGEMENT
%% =============================================================================

%% ---------------------------------------------------------------------------
%% add_agent_tool/2 — add a tool module to a live agent.
%% No-op if the tool is already registered for this agent.
%%
%%   agent_framework:add_agent_tool(hims_agent, my_new_search_tool).
%% ---------------------------------------------------------------------------
add_agent_tool(AgentId, ToolModule) when is_atom(AgentId), is_atom(ToolModule) ->
  agent_registry:add_tool(AgentId, ToolModule).

%% ---------------------------------------------------------------------------
%% remove_agent_tool/2 — remove a tool module from a live agent.
%% No-op if the tool is not registered for this agent.
%%
%%   agent_framework:remove_agent_tool(hims_agent, my_old_tool).
%% ---------------------------------------------------------------------------
remove_agent_tool(AgentId, ToolModule) when is_atom(AgentId), is_atom(ToolModule) ->
  agent_registry:remove_tool(AgentId, ToolModule).

%% =============================================================================
%% INTROSPECTION
%% =============================================================================

%% ---------------------------------------------------------------------------
%% agents/0 — list all currently registered agent IDs
%% ---------------------------------------------------------------------------
agents() ->
  agent_registry:list().

%% ---------------------------------------------------------------------------
%% tools/1 — list tool modules registered for a specific agent
%% ---------------------------------------------------------------------------
tools(AgentId) ->
  case agent_registry:lookup(AgentId) of
    {ok, Def}       -> {ok, maps:get(tools, Def, [])};
    {error, Reason} -> {error, Reason}
  end.

%% =============================================================================
%% INTERNAL
%% =============================================================================

ensure_req_id(#{req_id := _} = Ctx) -> Ctx;
ensure_req_id(Ctx)                  -> Ctx#{req_id => af_lib:req_id()}.

type_of(X) when is_binary(X) -> binary;
type_of(X) when is_map(X)    -> map;
type_of(X) when is_atom(X)   -> atom;
type_of(_)                   -> unknown.
