%% =============================================================================
%% src/agent_framework.erl
%%
%% PUBLIC API — the ONLY module your existing web application imports.
%%
%% Your Webmachine resource calls:
%%   agent_framework:run(mis_agent, Query, Ctx)
%%   agent_framework:run(hims_agent, Query, Ctx)
%%   agent_framework:run(lims_agent, Query, Ctx)
%%
%% That's the entire interface. Framework handles everything else.
%%
%% Ctx map your app builds:
%%   #{
%%     role    => finance_admin | doctor | lab_tech | guest,
%%     user_id => <<"user_123">>,    %% for session history
%%     req_id  => <<"abc123">>       %% optional, generated if missing
%%   }
%% =============================================================================

-module(agent_framework).
-export([run/3, agents/0, tools/1]).

%% ---------------------------------------------------------------------------
%% run/3 — execute a query through the named agent pipeline
%%
%% AgentId — atom from sys.config agents list: mis_agent | hims_agent | lims_agent
%% Query   — binary string from the user
%% Ctx     — map with role, user_id, optional req_id
%%
%% Returns:
%%   {ok, BinaryResponse}  — formatted natural language answer
%%   {error, Reason}       — structured error atom/tuple
%% ---------------------------------------------------------------------------
run(AgentId, Query, Ctx) when is_atom(AgentId), is_binary(Query), is_map(Ctx) ->
  %% Inject req_id if caller did not provide one
  Ctx1 = ensure_req_id(Ctx),
  agent_orchestrator:run(AgentId, Query, Ctx1);

run(AgentId, Query, Ctx) ->
  af_logger:error(invalid_run_args, #{
    agent => AgentId, query_type => type_of(Query), ctx_type => type_of(Ctx)
  }),
  {error, invalid_arguments}.

%% ---------------------------------------------------------------------------
%% agents/0 — list all registered agent IDs
%% Useful for validation in your web layer before calling run/3
%% ---------------------------------------------------------------------------
agents() ->
  agent_registry:list().

%% ---------------------------------------------------------------------------
%% tools/1 — list tools registered for a specific agent
%% Useful for building UI or for debugging
%% ---------------------------------------------------------------------------
tools(AgentId) ->
  case agent_registry:lookup(AgentId) of
    {ok, Def}       -> {ok, maps:get(tools, Def, [])};
    {error, Reason} -> {error, Reason}
  end.

%% ─── INTERNAL ────────────────────────────────────────────────────────────────

ensure_req_id(#{req_id := _} = Ctx) -> Ctx;
ensure_req_id(Ctx)                  -> maps:put(req_id, af_lib:req_id(), Ctx).

type_of(X) when is_binary(X) -> binary;
type_of(X) when is_map(X)    -> map;
type_of(X) when is_atom(X)   -> atom;
type_of(_)                   -> unknown.
