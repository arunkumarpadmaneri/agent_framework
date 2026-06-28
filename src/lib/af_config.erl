%% =============================================================================
%% src/lib/af_config.erl
%%
%% Framework configuration — no sys.config needed.
%%
%% USAGE
%% -----
%% 1. Call af_config:init/1 once when your app starts (or in your supervisor).
%% 2. Call af_config:set/2 any time to change a value at runtime.
%% 3. Everything not set falls back to framework defaults automatically.
%%
%% EXAMPLE
%% -------
%%   af_config:init(#{
%%     domain_module => my_constants,
%%     tool_modules  => [my_hims_tools, my_mis_tools],
%%     react_max_iterations => 10
%%   }).
%%
%%   %% Change at runtime — no restart needed
%%   af_config:set(retry_attempts, 5).
%%   af_config:set_llm_profile(my_fast, [{provider, groq}, ...]).
%% =============================================================================

-module(af_config).
-export([
  init/1,
  set/2,
  get/1, get/2,
  reset/0,
  llm_profiles/0,
  llm_profile/1,
  set_llm_profile/2,
  update_llm_profile/2
]).

%% ---------------------------------------------------------------------------
%% init/1 — call once at app startup with your settings map.
%% Keys not provided fall back to framework defaults.
%%
%%   af_config:init(#{
%%     domain_module => my_constants,
%%     tool_modules  => [my_hims_tools],
%%     llm_profiles  => [{my_fast, [{provider, groq}, ...]}]
%%   }).
%% ---------------------------------------------------------------------------
init(Settings) when is_map(Settings) ->
  maps:foreach(fun(Key, Value) ->
    application:set_env(agent_framework, Key, Value)
  end, Settings).

%% ---------------------------------------------------------------------------
%% set/2 — change any config value at runtime, takes effect immediately.
%%
%%   af_config:set(retry_attempts, 5).
%%   af_config:set(pipeline_timeout_ms, 30000).
%%   af_config:set(domain_module, my_new_constants).
%% ---------------------------------------------------------------------------
set(Key, Value) ->
  application:set_env(agent_framework, Key, Value).

%% ---------------------------------------------------------------------------
%% reset/0 — clear all runtime config, restoring framework defaults.
%% ---------------------------------------------------------------------------
reset() ->
  Keys = [domain_module, tool_modules, agents, llm_profiles, llm_profiles_builtin,
          pipeline_timeout_ms, retry_attempts, retry_base_ms,
          session_ttl_seconds, max_parallel_tools, react_max_iterations],
  lists:foreach(fun(K) -> application:unset_env(agent_framework, K) end, Keys).

%% ---------------------------------------------------------------------------
%% get/1,2 — read a config value, falling back to framework default.
%%
%%   af_config:get(retry_attempts)       %% → 3
%%   af_config:get(my_key, <<"none">>)   %% custom default for unknown keys
%% ---------------------------------------------------------------------------
get(Key) ->
  Default = maps:get(Key, defaults(), undefined),
  application:get_env(agent_framework, Key, Default).

get(Key, Default) ->
  application:get_env(agent_framework, Key, Default).

%% ---------------------------------------------------------------------------
%% set_llm_profile/2 — add or override a single LLM profile at runtime.
%%
%%   af_config:set_llm_profile(my_groq_fast, [
%%     {provider,    groq},
%%     {api_key,     {env, "GROQ_API_KEY"}},
%%     {model,       <<"llama3-70b-8192">>},
%%     {max_tokens,  1024},
%%     {temperature, 0.0},
%%     {timeout_ms,  10000}
%%   ]).
%% ---------------------------------------------------------------------------
set_llm_profile(Name, ProfileConfig) ->
  Existing = application:get_env(agent_framework, llm_profiles, []),
  Updated  = lists:keystore(Name, 1, Existing, {Name, ProfileConfig}),
  application:set_env(agent_framework, llm_profiles, Updated).

%% ---------------------------------------------------------------------------
%% update_llm_profile/2 — patch specific fields of an existing profile.
%% Works on both your profiles and built-in profiles.
%% Only the keys you pass are changed — everything else stays the same.
%%
%%   %% Change just the model
%%   af_config:update_llm_profile(claude_standard, #{model => <<"claude-opus-4-8">>}).
%%
%%   %% Rotate the API key env var
%%   af_config:update_llm_profile(claude_standard, #{api_key => {env, "NEW_KEY_VAR"}}).
%%
%%   %% Change model and token limit together
%%   af_config:update_llm_profile(groq_standard, #{
%%     model      => <<"llama3-70b-8192">>,
%%     max_tokens => 2048
%%   }).
%% ---------------------------------------------------------------------------
update_llm_profile(Name, Changes) when is_map(Changes) ->
  case llm_profile(Name) of
    {ok, CurrentConfig} ->
      Updated = maps:fold(fun(Key, Val, Acc) ->
        lists:keystore(Key, 1, Acc, {Key, Val})
      end, CurrentConfig, Changes),
      set_llm_profile(Name, Updated);
    {error, _} = Err ->
      Err
  end.

%% ---------------------------------------------------------------------------
%% llm_profiles/0 — full merged list: your profiles + built-ins.
%% Your profiles always win over built-ins on name clash.
%% Set {llm_profiles_builtin, false} to disable built-ins entirely.
%% ---------------------------------------------------------------------------
llm_profiles() ->
  AppProfiles = application:get_env(agent_framework, llm_profiles, []),
  UseBuiltin  = application:get_env(agent_framework, llm_profiles_builtin, true),
  case UseBuiltin of
    false ->
      AppProfiles;
    _ ->
      Gaps = [P || {Name, _} = P <- builtin_profiles(),
                   not lists:keymember(Name, 1, AppProfiles)],
      AppProfiles ++ Gaps
  end.

%% ---------------------------------------------------------------------------
%% llm_profile/1 — look up a single profile by name atom.
%% ---------------------------------------------------------------------------
llm_profile(Name) ->
  case lists:keyfind(Name, 1, llm_profiles()) of
    {_, Config} -> {ok, Config};
    false       -> {error, {unknown_llm_profile, Name}}
  end.

%% ---------------------------------------------------------------------------
%% Framework defaults — every key has a sensible value here.
%% ---------------------------------------------------------------------------
defaults() ->
  #{
    pipeline_timeout_ms  => 60000,
    retry_attempts       => 3,
    retry_base_ms        => 1000,
    session_ttl_seconds  => 1800,
    max_parallel_agents  => 10,
    max_parallel_tools   => 5,
    react_max_iterations => 5,
    tool_modules         => [],
    agents               => []
  }.

%% ---------------------------------------------------------------------------
%% Built-in LLM profiles — always available, no config needed.
%% api_key is always read from env vars at runtime.
%% ---------------------------------------------------------------------------
builtin_profiles() ->
  [
    {claude_standard, [
      {provider,    claude},
      {api_key,     {env, "ANTHROPIC_API_KEY"}},
      {model,       <<"claude-sonnet-4-20250514">>},
      {max_tokens,  2048},
      {temperature, 0.0},
      {timeout_ms,  30000}
    ]},
    {claude_fast, [
      {provider,    claude},
      {api_key,     {env, "ANTHROPIC_API_KEY"}},
      {model,       <<"claude-haiku-4-5-20251001">>},
      {max_tokens,  1024},
      {temperature, 0.0},
      {timeout_ms,  15000}
    ]},
    {openai_standard, [
      {provider,    openai},
      {api_key,     {env, "OPENAI_API_KEY"}},
      {model,       <<"gpt-4o">>},
      {max_tokens,  2048},
      {temperature, 0.0},
      {timeout_ms,  30000}
    ]},
    {gemini_standard, [
      {provider,    gemini},
      {api_key,     {env, "GEMINI_API_KEY"}},
      {model,       <<"gemini-1.5-pro">>},
      {max_tokens,  2048},
      {temperature, 0.0},
      {timeout_ms,  30000}
    ]},
    {groq_standard, [
      {provider,    groq},
      {api_key,     {env, "GROQ_API_KEY"}},
      {model,       <<"mixtral-8x7b-32768">>},
      {max_tokens,  2048},
      {temperature, 0.0},
      {timeout_ms,  30000}
    ]}
  ].
