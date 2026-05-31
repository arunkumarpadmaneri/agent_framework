%% =============================================================================
%% src/orchestrator/agent_intent.erl
%%
%% Workflow Step: INTENT
%%
%% Classifies the user query into a structured intent map.
%% Uses the LLM profile assigned to this step in the agent's workflow config.
%% Uses the agent's own system prompt from its definition (domain-specific).
%%
%% Returns: {ok, #{intent, entities, confidence}} | {error, Reason}
%% =============================================================================

-module(agent_intent).
-export([run/4]).

run(Query, AgentDef, Ctx, LLMProfile) ->
  AgentId  = maps:get(id, AgentDef),
  History  = maps:get(history, Ctx, []),

  %% Build messages: last 3 history turns + current query
  HistMsgs = history_to_messages(lists:nthtail(
    max(0, length(History) - 6), History)),
  Messages = HistMsgs ++ [
    #{<<"role">> => <<"user">>, <<"content">> => Query}
  ],

  %% System prompt comes from agent definition or use generic fallback
  SystemPrompt = maps:get(intent_prompt, AgentDef, generic_intent_prompt()),

  case llm_router:call(LLMProfile, Messages, SystemPrompt) of
    {ok, Json} ->
      parse_intent(clean(Json), AgentId);
    {error, Reason} ->
      af_logger:error(intent_llm_failed, #{agent => AgentId, reason => Reason}),
      {error, {intent_failed, Reason}}
  end.

%% Generic fallback intent prompt
generic_intent_prompt() ->
  <<"You are a query classifier.\n"
    "Classify the query and return ONLY valid JSON:\n"
    "{\"intent\":\"action\",\"entities\":{},\"confidence\":0.0}\n"
    "Set intent='unknown' if confidence < 0.6. Return ONLY the JSON.">>.

parse_intent(Json, AgentId) ->
  try
    D = jsx:decode(Json, [return_maps]),
    Intent = #{
      intent     => maps:get(<<"intent">>,     D),
      entities   => maps:get(<<"entities">>,   D, #{}),
      confidence => maps:get(<<"confidence">>, D, 0.0)
    },
    case maps:get(intent, Intent) of
      <<"unknown">> -> {error, {unknown_intent, AgentId}};
      _             ->
        af_logger:info(intent_ok, #{
          agent      => AgentId,
          intent     => maps:get(intent, Intent),
          confidence => maps:get(confidence, Intent)
        }),
        {ok, Intent}
    end
  catch _:E ->
    af_logger:error(intent_parse_failed, #{json => Json, err => E}),
    {error, {intent_parse_failed, Json}}
  end.

history_to_messages(H) ->
  lists:map(fun({Role, Content}) ->
    #{<<"role">> => atom_to_binary(Role), <<"content">> => Content}
  end, H).

clean(B) ->
  Stripped = re:replace(B, <<"```(?:json)?\\s*|\\s*```">>, <<>>,
               [global, {return, binary}]),
  string:trim(Stripped).
