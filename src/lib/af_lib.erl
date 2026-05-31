%% =============================================================================
%% src/lib/af_lib.erl — Shared utilities
%% =============================================================================
-module(af_lib).
-export([req_id/0]).

req_id() ->
  integer_to_binary(erlang:unique_integer([positive, monotonic])).
