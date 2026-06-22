%% =============================================================================
%% src/tools/tool_registry.erl
%%
%% Per-agent namespaced tool registry with function-based tools.
%%
%% Key design: tools are scoped per agent and grouped by system module.
%%   MIS agent  → can only call mis_tools:* functions
%%   HIMS agent → can only call hims_tools:* functions
%%   LIMS agent → can only call lims_tools:* functions
%%
%% This prevents cross-contamination (HIMS planner picking a LIMS tool).
%%
%% ETS table: agent_tools
%%   Key: {AgentId, ToolName}           e.g. {mis_agent, get_revenue}
%%   Val: {Module, Function, Schema}    e.g. {mis_tools, revenue, #{...}}
%%
%% WHY public ETS for execute?
%%   execute/3 is called from many parallel spawned processes.
%%   A GenServer call per execution would serialise parallel tool runs.
%%   Public ETS allows direct concurrent reads.
%% =============================================================================

-module(tool_registry).
-behaviour(gen_server).

-export([start_link/0, start/0,
         load_for_run/2, execute/3, schemas_for/1, exists/2, list_for/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
start()      -> gen_server:start({local, ?MODULE}, ?MODULE, [], []).

%% ---------------------------------------------------------------------------
%% load_for_run/2 — load tools for a specific agent before pipeline runs
%%
%% Called by agent_orchestrator before each pipeline execution.
%% Expects each module to have schemas/0 that returns [{ToolName, SchemaMap}, ...].
%% Each SchemaMap must include a 'function' key with the function name to call.
%% Idempotent — safe to call multiple times.
%% ---------------------------------------------------------------------------
load_for_run(AgentId, ToolNames) when is_list(ToolNames) ->
  clear_agent_tools(AgentId),
  ToolModules = application:get_env(agent_framework, tool_modules, []),
  lists:foreach(fun(Module) ->
    case catch Module:schemas() of
      Schemas when is_list(Schemas) ->
        lists:foreach(fun({ToolName, Schema}) ->
          case lists:member(ToolName, ToolNames) of
            true ->
              FunctionName = maps:get(function, Schema),
              ets:insert(agent_tools, {{AgentId, ToolName}, {Module, FunctionName, Schema}}),
              af_logger:info(tool_loaded, #{agent => AgentId, tool => ToolName, function => FunctionName});
            false ->
              ok
          end
        end, Schemas);
      _ ->
        af_logger:error(tool_load_failed, #{agent => AgentId, module => Module, reason => invalid_schemas})
    end
  end, ToolModules),
  ok.

clear_agent_tools(AgentId) ->
  Pattern = {{AgentId, '$1'}, '_'},
  Keys = [ {AgentId, ToolName} || {{Aid, ToolName}, _} <- ets:match_object(agent_tools, Pattern), Aid =:= AgentId ],
  lists:foreach(fun(Key) -> ets:delete(agent_tools, Key) end, Keys),
  ok.

%% ---------------------------------------------------------------------------
%% execute/3 — run a tool scoped to an agent
%% Calls Module:FunctionName(Params) with timing and error handling.
%% ---------------------------------------------------------------------------
execute(AgentId, ToolName, Params) ->
  case ets:lookup(agent_tools, {AgentId, ToolName}) of
    [{{_, _}, {Module, Function, _Schema}}] ->
      T0 = erlang:monotonic_time(millisecond),
      Result = try
        apply(Module, Function, [Params])
      catch C:R:St ->
        af_logger:error(tool_crash, #{agent => AgentId, tool => ToolName,
                                      module => Module, function => Function,
                                      class => C, reason => R, stack => St}),
        {error, {tool_crashed, ToolName}}
      end,
      af_logger:info(tool_done, #{
        agent   => AgentId,
        tool    => ToolName,
        module  => Module,
        function => Function,
        latency => erlang:monotonic_time(millisecond) - T0
      }),
      Result;
    [] ->
      af_logger:error(tool_not_found, #{agent => AgentId, tool => ToolName}),
      {error, {unknown_tool, AgentId, ToolName}}
  end.

%% ---------------------------------------------------------------------------
%% schemas_for/1 — get all tool schemas for an agent (sent to LLM planner)
%% Filters by agent, adds tool name to schema, removes internal 'function' field.
%% ---------------------------------------------------------------------------
schemas_for(AgentId) ->
  ets:foldl(fun({{Aid, Name}, {_Mod, _Func, Schema}}, Acc) when Aid =:= AgentId ->
    SchemaWithName = maps:put(name, Name, Schema),
    SchemaForLLM = maps:remove(function, SchemaWithName),
    [SchemaForLLM | Acc];
  (_, Acc) -> Acc
  end, [], agent_tools).

%% ---------------------------------------------------------------------------
%% exists/2 — check if a tool is registered for an agent
%% Used by planner to validate LLM-chosen tool names
%% ---------------------------------------------------------------------------
exists(AgentId, ToolName) ->
  ets:member(agent_tools, {AgentId, ToolName}).

%% ---------------------------------------------------------------------------
%% list_for/1 — list all tool names for an agent
%% ---------------------------------------------------------------------------
list_for(AgentId) ->
  ets:foldl(fun({{Aid, Name}, {_, _, _}}, Acc) when Aid =:= AgentId -> [Name | Acc];
               (_, Acc) -> Acc end, [], agent_tools).

init([]) ->
  ets:new(agent_tools, [named_table, set, public]),
  {ok, #{}}.

handle_call(_Req, _From, State) -> {reply, ok, State}.
handle_cast(_Msg, State)        -> {noreply, State}.
handle_info(_Info, State)       -> {noreply, State}.
terminate(_Reason, _State)      -> ok.
