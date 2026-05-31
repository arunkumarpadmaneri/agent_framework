%% =============================================================================
%% src/llm/llm_router.erl
%%
%% Per-step LLM router.
%%
%% Each workflow step carries an llm_profile atom (e.g. claude_fast).
%% This module resolves profile → config → adapter and makes the call.
%%
%% Profile 'none' is a valid value (execute step has no LLM).
%% Callers should never call llm_router with profile=none —
%% the orchestrator skips LLM routing for execute steps.
%%
%% Usage:
%%   llm_router:call(claude_fast, Messages, SystemPrompt)
%%   → {ok, Binary} | {error, Reason}
%% =============================================================================

-module(llm_router).
-behaviour(gen_server).

-export([start_link/0, call/3]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% ---------------------------------------------------------------------------
%% call/3 — resolve profile → config → adapter → LLM API call
%%
%% LLMProfile — atom from workflow config (e.g. claude_fast, openai_standard)
%% Messages   — [#{<<"role">> => ..., <<"content">> => ...}]
%% System     — binary system prompt
%% ---------------------------------------------------------------------------
call(none, _Messages, _System) ->
  %% execute step passes none — should not reach here
  {error, no_llm_profile};

call(LLMProfile, Messages, System) ->
  Timeout = profile_timeout(LLMProfile) + 5000,
  gen_server:call(?MODULE, {call, LLMProfile, Messages, System}, Timeout).

init([]) -> {ok, #{}}.

handle_call({call, Profile, Messages, System}, From, State) ->
  %% Spawn per call — router never blocks
  spawn_link(fun() ->
    Result = do_call(Profile, Messages, System),
    gen_server:reply(From, Result)
  end),
  {noreply, State}.

handle_cast(_Msg, State) -> {noreply, State}.
handle_info(_Info, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.

%% ─── INTERNAL ────────────────────────────────────────────────────────────────

do_call(Profile, Messages, System) ->
  Config  = resolve_profile(Profile),
  Adapter = provider_to_adapter(maps:get(provider, Config)),
  Retries = application:get_env(agent_framework, retry_attempts, 3),
  BaseMs  = application:get_env(agent_framework, retry_base_ms,  1000),

  af_logger:info(llm_call, #{profile => Profile, provider => maps:get(provider, Config)}),

  retry(fun() -> Adapter:complete(Messages, System, Config) end, Retries, BaseMs).

%% Resolve profile atom → config map from sys.config llm_profiles
resolve_profile(Profile) ->
  Profiles = application:get_env(agent_framework, llm_profiles, []),
  case proplists:get_value(Profile, Profiles) of
    undefined ->
      af_logger:error(unknown_llm_profile, #{profile => Profile}),
      error({unknown_llm_profile, Profile});
    Raw ->
      Cfg = maps:from_list(Raw),
      Key = case maps:get(api_key, Cfg) of
        {env, Var} ->
          case os:getenv(Var) of
            false -> error({missing_env_var, Var});
            V     -> list_to_binary(V)
          end;
        K -> K
      end,
      maps:put(api_key, Key, Cfg)
  end.

provider_to_adapter(claude) -> llm_claude;
provider_to_adapter(openai) -> llm_openai;
provider_to_adapter(gemini) -> llm_gemini;
provider_to_adapter(X)      -> error({unknown_provider, X}).

profile_timeout(Profile) ->
  Profiles = application:get_env(agent_framework, llm_profiles, []),
  case proplists:get_value(Profile, Profiles) of
    undefined -> 30000;
    Raw       -> proplists:get_value(timeout_ms, Raw, 30000)
  end.

%% Exponential backoff retry — only for transient errors
retry(Fun, 0, _Base) -> Fun();
retry(Fun, N, Base) ->
  case Fun() of
    {ok, R}                -> {ok, R};
    {error, rate_limited}  -> timer:sleep(Base), retry(Fun, N-1, Base*2);
    {error, timeout}       -> timer:sleep(Base), retry(Fun, N-1, Base*2);
    {error, {http, C, _}} when C >= 500 -> timer:sleep(Base), retry(Fun, N-1, Base*2);
    {error, R}             -> {error, R}
  end.
