%% =============================================================================
%% src/lib/rate_limiter.erl — Per-role token bucket
%% =============================================================================
-module(rate_limiter).
-behaviour(gen_server).
-export([start_link/0, check/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(LIMITS, #{finance_admin => 60, doctor => 40, lab_tech => 40, guest => 10}).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

check(Role) ->
  Limit  = maps:get(Role, ?LIMITS, 10),
  Minute = erlang:system_time(second) div 60,
  case ets:lookup(af_rate_limits, Role) of
    [{_, C, W}] when W =:= Minute, C >= Limit ->
      af_logger:warning(rate_limited, #{role => Role}),
      {error, rate_limited};
    [{_, C, W}] when W =:= Minute ->
      ets:insert(af_rate_limits, {Role, C+1, Minute}), ok;
    _ ->
      ets:insert(af_rate_limits, {Role, 1, Minute}), ok
  end.

init([]) ->
  ets:new(af_rate_limits, [named_table, set, public]),
  {ok, #{}}.

handle_call(_,_,S) -> {reply, ok, S}.
handle_cast(_,S)   -> {noreply, S}.
handle_info(_,S)   -> {noreply, S}.
terminate(_,_)     -> ok.
