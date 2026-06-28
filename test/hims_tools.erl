%% =============================================================================
%% src/tools/hims_tools.erl
%% HIMS (Hospital Information Management System) Tools
%% =============================================================================
-module(hims_tools).
-export([
  patient/1,
  billing/1,
  appointment/1,
  schemas/0
]).

%% Input/Output Schemas
schemas() ->
  [
    {get_patient, #{
      function => patient,
      description => <<"Get patient information and admission details">>,
      input => #{patient_id => <<"optional, unique identifier">>, department => <<"optional, default 'all'">>},
      output => #{patient_id => <<"string">>, name => <<"string">>, department => <<"string">>, admission_date => <<"string">>}
    }},
    {get_billing, #{
      function => billing,
      description => <<"Get billing and invoice details for a patient or department">>,
      input => #{patient_id => <<"optional, unique identifier">>, department => <<"optional, default 'all'">>},
      output => #{patient_id => <<"string">>, invoice_id => <<"string">>, amount => <<"number">>, status => <<"string">>}
    }},
    {get_appointment, #{
      function => appointment,
      description => <<"Get appointment schedule and OPD details">>,
      input => #{date => <<"optional, e.g. 'today'">>, department => <<"optional, default 'all'">>},
      output => #{appointment_id => <<"string">>, date => <<"string">>, time => <<"string">>, department => <<"string">>}
    }}
  ].

%% ---------------------------------------------------------------------------
%% Tool: Get Patient
%% Input:  {patient_id => string | undefined, department => string}
%% Output: {ok, {patient_id => string, name => string, department => string, ...}} | {error, Reason}
%% ---------------------------------------------------------------------------
patient(Params) ->
  PatientId = maps:get(<<"patient_id">>, Params, undefined),
  Dept      = maps:get(<<"department">>, Params, <<"all">>),
  hims_mcp:call(get_patient, #{patient_id => PatientId, department => Dept}).

%% ---------------------------------------------------------------------------
%% Tool: Get Billing
%% Input:  {patient_id => string | undefined, department => string}
%% Output: {ok, {patient_id => string, invoice_id => string, amount => number, status => string}} | {error, Reason}
%% ---------------------------------------------------------------------------
billing(Params) ->
  PatientId = maps:get(<<"patient_id">>, Params, undefined),
  Dept      = maps:get(<<"department">>, Params, <<"all">>),
  hims_mcp:call(get_billing, #{patient_id => PatientId, department => Dept}).

%% ---------------------------------------------------------------------------
%% Tool: Get Appointment
%% Input:  {date => string, department => string}
%% Output: {ok, {appointment_id => string, date => string, time => string, department => string}} | {error, Reason}
%% ---------------------------------------------------------------------------
appointment(Params) ->
  Date = maps:get(<<"date">>, Params, <<"today">>),
  Dept = maps:get(<<"department">>, Params, <<"all">>),
  hims_mcp:call(get_appointment, #{date => Date, department => Dept}).
