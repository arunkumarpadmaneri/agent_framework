%% =============================================================================
%% src/agents/agent_registry.erl
%%
%% Agent definition registry.
%%
%% On startup loads agents from:
%%   1. af_config:get(agents)   — inline list (optional)
%%   2. {domain_module, Mod}    — your project's constants module
%%
%% Runtime updates via update/2 — change workflow, tools, prompts without
%% re-registering the agent.
%% =============================================================================

-module(agent_registry).
-behaviour(gen_server).

-export([start_link/0, lookup/1, list/0, register/1, unregister/1, update/2,
         add_tool/2, remove_tool/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% ---------------------------------------------------------------------------
%% lookup/1 — get full agent definition by id
%% ---------------------------------------------------------------------------
lookup(AgentId) ->
  case ets:lookup(agent_definitions, AgentId) of
    [{_, Def}] -> {ok, Def};
    []         -> {error, {unknown_agent, AgentId}}
  end.

%% ---------------------------------------------------------------------------
%% update/2 — patch specific fields of a live agent, takes effect immediately.
%%
%%   %% Switch to ReAct loop
%%   agent_registry:update(hims_agent, #{
%%     workflow => workflow_constants:react_workflow(claude_standard)
%%   }).
%%
%%   %% Switch back to fast pipeline
%%   agent_registry:update(hims_agent, #{
%%     workflow => workflow_constants:fast_workflow()
%%   }).
%%
%%   %% Change LLM profile used in workflow
%%   agent_registry:update(hims_agent, #{
%%     workflow => workflow_constants:standard_workflow()
%%   }).
%%
%%   %% Update tools and prompts together
%%   agent_registry:update(hims_agent, #{
%%     tools         => [my_hims_tools, my_new_tools],
%%     intent_prompt => <<"Updated intent prompt.">>
%%   }).
%%
%% Returns ok | {error, {unknown_agent, AgentId}}
%% ---------------------------------------------------------------------------
update(AgentId, Changes) when is_map(Changes) ->
  gen_server:call(?MODULE, {update, AgentId, Changes}).

%% ---------------------------------------------------------------------------
%% add_tool/2 — add a tool module to a live agent.
%% No-op if the module is already in the agent's tool list.
%%
%%   agent_registry:add_tool(hims_agent, my_new_search_tool).
%% ---------------------------------------------------------------------------
add_tool(AgentId, ToolModule) ->
  gen_server:call(?MODULE, {add_tool, AgentId, ToolModule}).

%% ---------------------------------------------------------------------------
%% remove_tool/2 — remove a tool module from a live agent.
%% No-op if the module is not in the agent's tool list.
%%
%%   agent_registry:remove_tool(hims_agent, my_old_tool).
%% ---------------------------------------------------------------------------
remove_tool(AgentId, ToolModule) ->
  gen_server:call(?MODULE, {remove_tool, AgentId, ToolModule}).

register(AgentDef) when is_map(AgentDef) ->
  gen_server:call(?MODULE, {register, AgentDef}).

unregister(AgentId) when is_atom(AgentId) ->
  gen_server:call(?MODULE, {unregister, AgentId}).

%% ---------------------------------------------------------------------------
%% list/0 — return all registered agent id atoms
%% ---------------------------------------------------------------------------
list() ->
  ets:foldl(fun({Id, _}, Acc) -> [Id | Acc] end, [], agent_definitions).

%% ─── GEN_SERVER ──────────────────────────────────────────────────────────────

init([]) ->
  ets:new(agent_definitions, [named_table, set, protected]),
  load_agents(),
  {ok, #{}}.

handle_call({register, AgentDef}, _From, State) ->
  Id = maps:get(id, AgentDef),
  ets:insert(agent_definitions, {Id, AgentDef}),
  af_logger:info(agent_registered, #{id => Id}),
  {reply, ok, State};

handle_call({unregister, AgentId}, _From, State) ->
  ets:delete(agent_definitions, AgentId),
  {reply, ok, State};

handle_call({update, AgentId, Changes}, _From, State) ->
  case ets:lookup(agent_definitions, AgentId) of
    [{_, Current}] ->
      Updated = maps:merge(Current, Changes),
      ets:insert(agent_definitions, {AgentId, Updated}),
      af_logger:info(agent_updated, #{id => AgentId, changed_keys => maps:keys(Changes)}),
      {reply, ok, State};
    [] ->
      {reply, {error, {unknown_agent, AgentId}}, State}
  end;

handle_call({add_tool, AgentId, ToolModule}, _From, State) ->
  case ets:lookup(agent_definitions, AgentId) of
    [{_, Def}] ->
      Tools   = maps:get(tools, Def, []),
      case lists:member(ToolModule, Tools) of
        true  ->
          {reply, ok, State};
        false ->
          Updated = maps:put(tools, Tools ++ [ToolModule], Def),
          ets:insert(agent_definitions, {AgentId, Updated}),
          af_logger:info(tool_added, #{agent => AgentId, tool => ToolModule}),
          {reply, ok, State}
      end;
    [] ->
      {reply, {error, {unknown_agent, AgentId}}, State}
  end;

handle_call({remove_tool, AgentId, ToolModule}, _From, State) ->
  case ets:lookup(agent_definitions, AgentId) of
    [{_, Def}] ->
      Tools   = maps:get(tools, Def, []),
      Updated = maps:put(tools, lists:delete(ToolModule, Tools), Def),
      ets:insert(agent_definitions, {AgentId, Updated}),
      af_logger:info(tool_removed, #{agent => AgentId, tool => ToolModule}),
      {reply, ok, State};
    [] ->
      {reply, {error, {unknown_agent, AgentId}}, State}
  end;

handle_call(_Req, _From, State) -> {reply, ok, State}.
handle_cast(_Msg, State)        -> {noreply, State}.
handle_info(_Info, State)       -> {noreply, State}.
terminate(_Reason, _State)      -> ok.

%% ─── INTERNAL ────────────────────────────────────────────────────────────────

load_agents() ->
  InlineAgents = af_config:get(agents),
  ModuleAgents = load_from_domain_module(),
  lists:foreach(fun(Def) ->
    case maps:find(id, Def) of
      {ok, Id} ->
        ets:insert(agent_definitions, {Id, Def}),
        af_logger:info(agent_loaded, #{id => Id, ts => erlang:system_time(millisecond)});
      error ->
        af_logger:error(agent_load_failed, #{reason => missing_id, def => Def})
    end
  end, InlineAgents ++ ModuleAgents).

load_from_domain_module() ->
  case af_config:get(domain_module, undefined) of
    undefined ->
      [];
    Mod ->
      try Mod:agents() of
        Agents when is_list(Agents) -> Agents;
        _                           -> []
      catch
        _:_ ->
          af_logger:error(domain_module_failed, #{module => Mod}),
          []
      end
  end.
