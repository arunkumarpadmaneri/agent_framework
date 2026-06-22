%% =============================================================================
%% src/agent_framework_app.erl
%%
%% OTP Application — starts the framework as a standalone OTP app.
%% Add agent_framework to your existing app's deps and included_applications.
%% =============================================================================

-module(agent_framework_app).
-behaviour(application).
-export([start/2, stop/1]).

start(_Type, _Args) ->
  %% Start dependencies needed for LLM API calls.
  %% Crypto must be started before SSL.
  ok = ensure_started(crypto),
  ok = ensure_started(ssl),
  ok = ensure_started(inets),

  %% Supervisor will start all services including tool_registry
  agent_framework_sup:start_link().

stop(_State) -> ok.

ensure_started(App) ->
  case application:ensure_started(App) of
    ok                              -> ok;
    {error, {already_started, App}} -> ok;
    {error, R}                      -> error({dep_failed, App, R})
  end.
