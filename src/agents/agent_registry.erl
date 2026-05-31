%% =============================================================================
%% src/agents/agent_registry.erl
%%
%% Agent definition registry.
%%
%% Loads all agent definitions from sys.config at startup.
%% Provides O(1) lookup by agent id atom.
%%
%% Agent definition structure (from sys.config):
%%   #{
%%     id          => mis_agent,
%%     description => "...",
%%     tools       => [mis_tool_revenue, ...],
%%     workflow    => [
%%       #{step => intent,  llm_profile => claude_fast},
%%       #{step => plan,    llm_profile => claude_fast},
%%       #{step => execute, llm_profile => none},
%%       #{step => format,  llm_profile => claude_standard}
%%     ]
%%   }
%% =============================================================================

-module(agent_registry).
-behaviour(gen_server).

-export([start_link/0, lookup/1, list/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% ---------------------------------------------------------------------------
%% lookup/1 — get full agent definition by id
%% Returns {ok, AgentDef} | {error, {unknown_agent, AgentId}}
%% ---------------------------------------------------------------------------
lookup(AgentId) ->
  case ets:lookup(agent_definitions, AgentId) of
    [{_, Def}] -> {ok, Def};
    []         -> {error, {unknown_agent, AgentId}}
  end.

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

handle_call(_Req, _From, State) -> {reply, ok, State}.
handle_cast(_Msg, State)        -> {noreply, State}.
handle_info(_Info, State)       -> {noreply, State}.
terminate(_Reason, _State)      -> ok.

%% ─── INTERNAL ────────────────────────────────────────────────────────────────

load_agents() ->
  AgentDefs = application:get_env(agent_framework, agents, []),
  lists:foreach(fun(Def) ->
    Id = maps:get(id, Def),
    ets:insert(agent_definitions, {Id, Def}),
    af_logger:info(agent_loaded, #{id => Id})
  end, AgentDefs).
