%% =============================================================================
%% config/domains/hospital_constants.erl
%%
%% Domain-specific constants for Hospital Management System (HMS)
%% Defines agents, tools, and custom prompts for hospital domain.
%% Converted from hospital.config to Erlang constant module.
%% =============================================================================

-module(hospital_constants).

%% Public API
-export([
  agents/0,
  mis_agent/0,
  hims_agent/0,
  lims_agent/0,
  agent/1
]).

%% =============================================================================
%% MIS AGENT (Financial reporting)
%% =============================================================================

mis_agent() ->
  #{
    id          => mis_agent,
    domain      => hospital,
    description => "Hospital Management Information System (MIS) agent",
    tools       => [get_revenue, get_expenses, get_mis_report],

    %% Custom prompts for this agent
    intent_prompt =>
      <<"You are a query classifier for Hospital Financial Management.\n"
        "Classify and return ONLY valid JSON:\n"
        "{\"intent\":\"get_revenue|get_expenses|get_report|unknown\",\n"
        "\"entities\":{\"period\":null,\"department\":null},\n"
        "\"confidence\":0.0}\n"
        "Set intent='unknown' if confidence < 0.6. Return ONLY JSON.">>,

    format_prompt =>
      <<"You are a Hospital Financial Reporting assistant.\n"
        "Format the raw financial data into a clear, concise response.\n"
        "Include key numbers with ₹ symbol, trends, and observations.\n"
        "Plain text only — no JSON, no markdown headers.">>,

    workflow    => workflow_constants:fast_workflow()
  }.

%% =============================================================================
%% HIMS AGENT (Patient & clinical info)
%% =============================================================================

hims_agent() ->
  #{
    id          => hims_agent,
    domain      => hospital,
    description => "Hospital Information Management System (HIMS) agent",
    tools       => [get_patient, get_billing, get_appointment],

    intent_prompt =>
      <<"You are a query classifier for Hospital Patient Management.\n"
        "Classify and return ONLY valid JSON:\n"
        "{\"intent\":\"get_patient|get_billing|get_appointment|unknown\",\n"
        "\"entities\":{\"patient_id\":null,\"department\":null,\"date\":null},\n"
        "\"confidence\":0.0}\n"
        "Set intent='unknown' if confidence < 0.6. Return ONLY JSON.">>,

    format_prompt =>
      <<"You are a Hospital Information System assistant.\n"
        "Format patient, billing, or appointment data into a clear response.\n"
        "Be concise and clinically appropriate. Plain text only.">>,

    workflow    => workflow_constants:fast_workflow()
  }.

%% =============================================================================
%% LIMS AGENT (Laboratory info)
%% =============================================================================

lims_agent() ->
  #{
    id          => lims_agent,
    domain      => hospital,
    description => "Laboratory Information Management System (LIMS) agent",
    tools       => [get_sample, get_test_result, get_lab_report],

    intent_prompt =>
      <<"You are a query classifier for Hospital Laboratory Management.\n"
        "Classify and return ONLY valid JSON:\n"
        "{\"intent\":\"get_sample|get_result|get_report|unknown\",\n"
        "\"entities\":{\"sample_id\":null,\"test_type\":null,\"patient_id\":null},\n"
        "\"confidence\":0.0}\n"
        "Set intent='unknown' if confidence < 0.6. Return ONLY JSON.">>,

    format_prompt =>
      <<"You are a Laboratory Information System assistant.\n"
        "Format lab results and sample data into a clear, accurate response.\n"
        "Include reference ranges where relevant. Plain text only.">>,

    workflow    => workflow_constants:fast_workflow()
  }.

%% =============================================================================
%% Public API Functions
%% =============================================================================

%% Returns all hospital domain agents as a list
agents() ->
  [
    mis_agent(),
    hims_agent(),
    lims_agent()
  ].

%% Lookup agent by ID
agent(AgentId) ->
  case AgentId of
    mis_agent  -> mis_agent();
    hims_agent -> hims_agent();
    lims_agent -> lims_agent();
    _          -> {error, agent_not_found}
  end.
