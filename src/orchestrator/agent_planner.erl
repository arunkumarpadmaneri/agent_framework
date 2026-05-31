%% =============================================================================
%% src/orchestrator/agent_planner.erl
%%
%% Workflow Step: PLAN
%%
%% Receives the classified intent + agent's tool schemas.
%% Sends to LLM → gets back an execution plan.
%%
%% Plan structure:
%%   #{
%%     mode  => single | sequential | parallel,
%%     steps => [#{step_id, tool, params, depends_on}]
%%   }
%% =============================================================================

-module(agent_planner).
-export([run/4]).

run(Intent, AgentDef, _Ctx, LLMProfile) ->
  AgentId = maps:get(id, AgentDef),

  %% Get tool schemas for THIS agent only (scoped to agent's tool list)
  Schemas  = tool_registry:schemas_for(AgentId),
  Msg      = jsx:encode(#{intent => Intent, tools => Schemas}),
  Messages = [#{<<"role">> => <<"user">>, <<"content">> => Msg}],

  case llm_router:call(LLMProfile, Messages, plan_prompt()) of
    {ok, Json} ->
      parse_plan(clean(Json), AgentId);
    {error, Reason} ->
      af_logger:error(plan_llm_failed, #{agent => AgentId, reason => Reason}),
      {error, {plan_failed, Reason}}
  end.

plan_prompt() ->
  <<
    "You are an execution planner. Given intent + tool list, build an execution plan.\n"
    "Return ONLY valid JSON:\n"
    "{\n"
    "  \"mode\": \"single|sequential|parallel\",\n"
    "  \"steps\": [\n"
    "    {\"step_id\":\"step_1\",\"tool\":\"tool_name\","
    "\"params\":{},\"depends_on\":[]}\n"
    "  ]\n"
    "}\n"
    "Rules:\n"
    "  single=one tool, sequential=each step needs previous output,"
    "  parallel=all independent\n"
    "Fill all params from intent entities. Default period='this month'.\n"
    "Return ONLY the JSON."
  >>.

parse_plan(Json, AgentId) ->
  try
    D     = jsx:decode(Json, [return_maps]),
    ModeBin = get_with_default(D, <<"mode">>, <<"single">>),
    Mode    = parse_mode(ModeBin),
    Steps   = parse_steps(get_with_default(D, <<"steps">>, []), AgentId),
    case Steps of
      [] -> {error, no_tools_selected};
      _  ->
        af_logger:info(plan_ok, #{agent => AgentId, mode => Mode, steps => length(Steps)}),
        {ok, #{mode => Mode, steps => Steps}}
    end
  catch _:E ->
    af_logger:error(plan_parse_failed, #{err => E}),
    {error, plan_parse_failed}
  end.

parse_steps(RawSteps, AgentId) ->
  lists:filtermap(fun(S) ->
    try
      ToolBin = get_with_default(S, <<"tool">>, <<>>),
      Tool = parse_tool(ToolBin),
      case Tool of
        undefined ->
          af_logger:error(plan_unknown_tool, #{agent => AgentId, tool => ToolBin}),
          false;
        _ ->
          case tool_registry:exists(AgentId, Tool) of
            true ->
              {true, #{
                step_id    => get_with_default(S, <<"step_id">>, af_lib:req_id()),
                tool       => Tool,
                params     => get_with_default(S, <<"params">>, #{}),
                depends_on => get_with_default(S, <<"depends_on">>, [])
              }};
            false ->
              af_logger:error(plan_unknown_tool, #{agent => AgentId, tool => Tool}),
              false
          end
      end
    catch _:_ -> false
    end
  end, RawSteps).

clean(B) ->
  Stripped = re:replace(B, <<"```(?:json)?\\s*|\\s*```">>, <<>>,
               [global, {return, binary}]),
  binary:trim(Stripped).

get_with_default(Map, Key, Default) ->
  case maps:find(Key, Map) of
    {ok, V} -> V;
    error -> Default
  end.

parse_mode(<<"single">>)     -> single;
parse_mode(<<"sequential">>) -> sequential;
parse_mode(<<"parallel">>)   -> parallel;
parse_mode(_)                 -> single.

parse_tool(<<>>) -> undefined;
parse_tool(Bin) when is_binary(Bin) ->
  case catch erlang:binary_to_existing_atom(Bin, utf8) of
    Atom when is_atom(Atom) -> Atom;
    _ -> undefined
  end.
