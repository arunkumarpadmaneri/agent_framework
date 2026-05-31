%% =============================================================================
%% src/lib/session_mgr.erl — Per-user conversation history
%% =============================================================================
-module(session_mgr).
-behaviour(gen_server).
-export([start_link/0, enrich/1, record/3]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(MAX_HISTORY, 10).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Add session history to context before pipeline runs
enrich(Ctx) ->
  SessionId = session_id(Ctx),
  History = case ets:lookup(af_sessions, SessionId) of
    [{_, #{history := H}}] -> H;
    []                     -> []
  end,
  maps:put(history, History, Ctx).

%% Record completed exchange into session history
record(Ctx, Query, {ok, Response}) ->
  Id  = session_id(Ctx),
  Now = erlang:system_time(second),
  Old = case ets:lookup(af_sessions, Id) of
    [{_, E}] -> maps:get(history, E, []);
    []       -> []
  end,
  New = lists:sublist(Old ++ [{user, Query}, {assistant, Response}], ?MAX_HISTORY),
  ets:insert(af_sessions, {Id, #{history => New, last_seen => Now}});
record(_Ctx, _Query, {error, _}) -> ok.

init([]) ->
  ets:new(af_sessions, [named_table, set, public]),
  {ok, _} = timer:send_interval(60000, self(), cleanup),
  {ok, #{}}.

handle_call(_,_,S) -> {reply, ok, S}.
handle_cast(_,S)   -> {noreply, S}.

handle_info(cleanup, State) ->
  TTL    = application:get_env(agent_framework, session_ttl_seconds, 1800),
  Cutoff = erlang:system_time(second) - TTL,
  ets:select_delete(af_sessions, [
    {{'_', #{last_seen => '$1'}}, [{'<', '$1', Cutoff}], [true]}
  ]),
  {noreply, State};
handle_info(_, S) -> {noreply, S}.
terminate(_, _) -> ok.

session_id(#{user_id := Uid}) -> Uid;
session_id(#{req_id  := Id})  -> Id;
session_id(_)                 -> <<"default">>.
