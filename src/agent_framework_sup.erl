%% =============================================================================
%% src/agent_framework_sup.erl
%%
%% Top-level supervisor.
%%
%% Children in start order (dependencies first):
%%   1. tool_registry  — ETS tool store (agents + orchestrator depend on it)
%%   2. llm_router     — LLM dispatcher (orchestrator depends on it)
%%   3. session_mgr    — per-user history (orchestrator depends on it)
%%   4. rate_limiter   — per-role throttle (orchestrator depends on it)
%%   5. agent_registry — agent definitions lookup (orchestrator depends on it)
%%   6. agent_orchestrator — pipeline runner (depends on all above)
%%
%% strategy: one_for_one
%%   A crash in one child restarts only that child.
%%   Other children and in-flight requests are unaffected.
%% =============================================================================

-module(agent_framework_sup).
-behaviour(supervisor).
-export([start_link/0, init/1]).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  SupFlags = #{strategy => one_for_one, intensity => 5, period => 10},

  Children = [
    worker(tool_registry),
    worker(llm_router),
    worker(session_mgr),
    worker(rate_limiter),
    worker(agent_registry),
    worker(agent_orchestrator)
  ],

  {ok, {SupFlags, Children}}.

worker(Mod) ->
  #{id => Mod, start => {Mod, start_link, []},
    restart => permanent, shutdown => 5000, type => worker}.
