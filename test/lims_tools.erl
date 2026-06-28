%% =============================================================================
%% src/tools/lims_tools.erl
%% LIMS (Laboratory Information Management System) Tools
%% =============================================================================
-module(lims_tools).
-export([
  sample/1,
  test_result/1,
  lab_report/1,
  schemas/0
]).

%% Input/Output Schemas
schemas() ->
  [
    {get_sample, #{
      function => sample,
      description => <<"Get lab sample status and collection details">>,
      input => #{sample_id => <<"optional, unique identifier">>, patient_id => <<"optional, unique identifier">>},
      output => #{sample_id => <<"string">>, patient_id => <<"string">>, status => <<"string">>, collection_date => <<"string">>}
    }},
    {get_test_result, #{
      function => test_result,
      description => <<"Get lab test results for a patient or sample">>,
      input => #{
        sample_id => <<"optional, unique identifier">>,
        patient_id => <<"optional, unique identifier">>,
        test_type => <<"optional, e.g. 'CBC', 'LFT', 'RFT', 'urine'">>
      },
      output => #{sample_id => <<"string">>, test_type => <<"string">>, result => <<"string">>, normal_range => <<"string">>}
    }},
    {get_lab_report, #{
      function => lab_report,
      description => <<"Get full laboratory report for a patient">>,
      input => #{patient_id => <<"required, unique identifier">>, date => <<"optional, e.g. 'today'">>},
      output => #{patient_id => <<"string">>, report_id => <<"string">>, tests => <<"array">>, summary => <<"string">>}
    }}
  ].

%% ---------------------------------------------------------------------------
%% Tool: Get Sample
%% Input:  {sample_id => string | undefined, patient_id => string | undefined}
%% Output: {ok, {sample_id => string, patient_id => string, status => string, collection_date => string}} | {error, Reason}
%% ---------------------------------------------------------------------------
sample(Params) ->
  SampleId  = maps:get(<<"sample_id">>, Params, undefined),
  PatientId = maps:get(<<"patient_id">>, Params, undefined),
  lims_mcp:call(get_sample, #{sample_id => SampleId, patient_id => PatientId}).

%% ---------------------------------------------------------------------------
%% Tool: Get Test Result
%% Input:  {sample_id => string | undefined, patient_id => string | undefined, test_type => string}
%% Output: {ok, {sample_id => string, test_type => string, result => string, normal_range => string}} | {error, Reason}
%% ---------------------------------------------------------------------------
test_result(Params) ->
  SampleId  = maps:get(<<"sample_id">>, Params, undefined),
  PatientId = maps:get(<<"patient_id">>, Params, undefined),
  TestType  = maps:get(<<"test_type">>, Params, <<"all">>),
  lims_mcp:call(get_test_result, #{
    sample_id  => SampleId,
    patient_id => PatientId,
    test_type  => TestType
  }).

%% ---------------------------------------------------------------------------
%% Tool: Get Lab Report
%% Input:  {patient_id => string, date => string}
%% Output: {ok, {patient_id => string, report_id => string, tests => list, summary => string}} | {error, Reason}
%% ---------------------------------------------------------------------------
lab_report(Params) ->
  PatientId = maps:get(<<"patient_id">>, Params),
  Date      = maps:get(<<"date">>, Params, <<"today">>),
  lims_mcp:call(get_lab_report, #{patient_id => PatientId, date => Date}).
