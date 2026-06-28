%% =============================================================================
%% config/domains/api_example_constants.erl
%%
%% Domain-specific constants for Billing API agent
%% Converted from api_example.config to Erlang constant module.
%% =============================================================================

-module(api_example_constants).

%% Public API
-export([
  agents/0,
  billing_agent/0,
  agent/1
]).

%% =============================================================================
%% BILLING AGENT
%% =============================================================================

billing_agent() ->
  #{
    id          => billing_agent,
    domain      => api,
    description => "Billing API agent for fetching bill lists from a local endpoint",
    tools       => [get_bill_list],

    intent_prompt =>
      <<"You are a billing query classifier. Return only valid JSON with this shape:\n"
        "{\"intent\":\"get_bill_list|unknown\",\n"
        "\"entities\":{\"entitykey\":null,\"date\":null},\n"
        "\"confidence\":0.0}\n"
        "Choose intent 'get_bill_list' for requests asking for bill lists, otherwise 'unknown'.">>,

    format_prompt =>
      <<"You are a billing assistant. Format the bill list response clearly and concisely. Use plain text only.">>,

    workflow    => workflow_constants:fast_workflow()
  }.

%% =============================================================================
%% Public API Functions
%% =============================================================================

%% Returns all API domain agents as a list
agents() ->
  [
    billing_agent()
  ].

%% Lookup agent by ID
agent(AgentId) ->
  case AgentId of
    billing_agent -> billing_agent();
    _             -> {error, agent_not_found}
  end.
