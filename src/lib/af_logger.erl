%% =============================================================================
%% src/lib/af_logger.erl — Structured event logger
%% =============================================================================
-module(af_logger).
-export([info/2, warning/2, error/2]).

info(Event, Meta)    -> logger:info(build(Event, Meta)).
warning(Event, Meta) -> logger:warning(build(Event, Meta)).
error(Event, Meta)   -> logger:error(build(Event, Meta)).

build(Event, Meta) ->
  maps:merge(#{event => Event, ts => erlang:system_time(millisecond)}, Meta).
