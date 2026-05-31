%% =============================================================================
%% src/lib/af_error.erl — Client-facing error formatting
%% =============================================================================
-module(af_error).
-export([fmt/1]).

fmt(rate_limited)               -> <<"Rate limit exceeded — please retry later">>;
fmt({unknown_agent, Id})        -> iolist_to_binary(io_lib:format("Unknown agent: ~p", [Id]));
fmt({intent_failed, _})         -> <<"Could not understand query — please rephrase">>;
fmt({unknown_intent, _})        -> <<"Query intent unclear — be more specific">>;
fmt(no_tools_selected)          -> <<"No matching tools for this query">>;
fmt({tool_failed, T, R})        -> iolist_to_binary(io_lib:format("Tool ~p failed: ~p", [T, R]));
fmt(invalid_arguments)          -> <<"Invalid request arguments">>;
fmt(Msg) when is_binary(Msg)    -> Msg;
fmt(Other)                      -> iolist_to_binary(io_lib:format("Error: ~p", [Other])).
