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

-export([start_link/0, lookup/1, list/0, register/1, unregister/1]).
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
handle_call(_Req, _From, State) -> {reply, ok, State}.
handle_cast(_Msg, State)        -> {noreply, State}.
handle_info(_Info, State)       -> {noreply, State}.
terminate(_Reason, _State)      -> ok.

%% ─── INTERNAL ────────────────────────────────────────────────────────────────

load_agents() ->
  BaseAgents      = application:get_env(agent_framework, agents, []),
  ConstantAgents  = load_from_constants(),
  ConfigAgents    = load_domain_configs(),
  Agents          = BaseAgents ++ ConstantAgents ++ ConfigAgents,
  lists:foreach(fun(Def) ->
    case maps:find(id, Def) of
      {ok, Id} ->
        ets:insert(agent_definitions, {Id, Def}),
        af_logger:info(agent_loaded, #{id => Id});
      error ->
        af_logger:error(agent_load_failed, #{reason => invalid_definition, def => Def})
    end
  end, Agents).

%% Load agents from Erlang constant modules (preferred approach)
load_from_constants() ->
  ConstantModules = [
    hospital_constants,
    ecommerce_constants,
    api_example_constants
  ],
  lists:flatmap(fun(Module) ->
    case code:ensure_loaded(Module) of
      {module, Module} ->
        try Module:agents() of
          Agents when is_list(Agents) -> Agents;
          _ -> []
        catch
          _:_ -> []
        end;
      {error, _} ->
        []
    end
  end, ConstantModules).

load_domain_configs() ->
  ConfigDir = "config/domains",
  case file:list_dir(ConfigDir) of
    {ok, Files} ->
      ConfigFiles = lists:filter(fun(F) -> filename:extension(F) == ".config" end, Files),
      lists:flatmap(fun(F) -> load_domain_file(filename:join(ConfigDir, F)) end, ConfigFiles);
    {error, _} ->
      []
  end.

load_domain_file(Path) ->
  case file:consult(Path) of
    {ok, [Config]} ->
      case proplists:get_value(agent_framework, Config, []) of
        AgentFrameworkEnv when is_list(AgentFrameworkEnv) ->
          case proplists:get_value(agents, AgentFrameworkEnv, []) of
            Agents when is_list(Agents) -> Agents;
            _ -> []
          end;
        _ ->
          []
      end;
    _ ->
      []
  end.
