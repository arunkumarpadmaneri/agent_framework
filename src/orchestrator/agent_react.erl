%% =============================================================================
%% src/orchestrator/agent_react.erl
%%
%% ReAct (Reasoning + Acting) loop.
%%
%% Instead of a fixed intent→plan→execute→format pipeline, the LLM drives
%% the loop itself: it sees the tool list, decides which tool to call, gets
%% the result back, and repeats until it produces a final answer.
%%
%% Loop structure:
%%   1. Send messages + tool schemas to LLM
%%   2. LLM replies with one of:
%%        {"action":"tool_name","params":{...}}  → call tool, append result, loop
%%        {"answer":"...text..."}                 → return answer, done
%%   3. Repeat up to react_max_iterations times
%%
%% Workflow config to enable react mode for an agent:
%%   workflow => #{mode => react, llm_profile => claude_standard}
%%
%% Optional per-agent system prompt override:
%%   react_prompt => <<"You are a hospital assistant...">>
%% =============================================================================

-module(agent_react).
-export([run/4]).

-define(DEFAULT_MAX_ITER, 5).

%% ---------------------------------------------------------------------------
%% run/4 — entry point called from agent_orchestrator
%% ---------------------------------------------------------------------------
run(Query, AgentDef, _Ctx, LLMProfile) ->
  AgentId  = maps:get(id, AgentDef),
  MaxIter  = af_config:get(react_max_iterations),
  Schemas  = tool_registry:schemas_for(AgentId),
  SysPrompt = build_system_prompt(Schemas, AgentDef),
  InitMsgs  = [#{<<"role">> => <<"user">>, <<"content">> => Query}],

  af_logger:info(react_start, #{agent => AgentId, query => Query, max_iter => MaxIter}),
  loop(InitMsgs, AgentDef, LLMProfile, SysPrompt, MaxIter).

%% ---------------------------------------------------------------------------
%% loop/5 — one iteration: call LLM, parse, branch
%% ---------------------------------------------------------------------------
loop(_Messages, AgentDef, _Profile, _Prompt, 0) ->
  AgentId = maps:get(id, AgentDef),
  af_logger:error(react_max_iter_exceeded, #{agent => AgentId}),
  {error, max_iterations_exceeded};

loop(Messages, AgentDef, Profile, SysPrompt, ItersLeft) ->
  AgentId = maps:get(id, AgentDef),

  case llm_router:call(Profile, Messages, SysPrompt) of
    {ok, LLMText} ->
      af_logger:info(react_llm_response, #{
        agent      => AgentId,
        iters_left => ItersLeft,
        response   => LLMText
      }),
      case parse_response(LLMText, AgentId) of

        {tool_call, ToolName, Params} ->
          af_logger:info(react_tool_call, #{agent => AgentId, tool => ToolName, params => Params}),
          ToolResult = tool_registry:execute(AgentId, ToolName, Params),
          ResultMsg  = encode_tool_result(ToolName, ToolResult),
          NewMessages = Messages ++ [
            #{<<"role">> => <<"assistant">>, <<"content">> => LLMText},
            #{<<"role">> => <<"user">>,      <<"content">> => ResultMsg}
          ],
          loop(NewMessages, AgentDef, Profile, SysPrompt, ItersLeft - 1);

        {answer, Text} ->
          af_logger:info(react_done, #{agent => AgentId, iters_used => ?DEFAULT_MAX_ITER - ItersLeft + 1}),
          {ok, Text};

        raw ->
          %% LLM didn't follow the JSON format — treat the raw text as the answer
          af_logger:info(react_raw_answer, #{agent => AgentId}),
          {ok, LLMText}
      end;

    {error, Reason} ->
      af_logger:error(react_llm_failed, #{agent => AgentId, reason => Reason}),
      {error, Reason}
  end.

%% ---------------------------------------------------------------------------
%% parse_response/2 — decode LLM output into a tool call or final answer
%% ---------------------------------------------------------------------------
parse_response(Text, AgentId) ->
  Cleaned = clean_json(Text),
  try
    D = jsx:decode(Cleaned, [return_maps]),
    case {maps:find(<<"action">>, D), maps:find(<<"answer">>, D)} of

      {{ok, ToolBin}, _} when is_binary(ToolBin) ->
        Params = maps:get(<<"params">>, D, #{}),
        Tool = case catch erlang:binary_to_existing_atom(ToolBin, utf8) of
          A when is_atom(A) -> A;
          _                 -> undefined
        end,
        case Tool of
          undefined ->
            af_logger:error(react_unknown_tool, #{agent => AgentId, tool => ToolBin}),
            raw;
          _ ->
            case tool_registry:exists(AgentId, Tool) of
              true  -> {tool_call, Tool, Params};
              false ->
                af_logger:error(react_tool_not_registered, #{agent => AgentId, tool => Tool}),
                raw
            end
        end;

      {_, {ok, Answer}} when is_binary(Answer) ->
        {answer, Answer};

      _ ->
        raw
    end
  catch _:_ ->
    raw
  end.

%% ---------------------------------------------------------------------------
%% build_system_prompt/2
%% ---------------------------------------------------------------------------
build_system_prompt(Schemas, AgentDef) ->
  SchemaJson    = jsx:encode(Schemas),
  CustomPrompt  = maps:get(react_prompt, AgentDef, <<>>),
  <<
    "You are an intelligent agent with access to tools.\n\n"
    "AVAILABLE TOOLS:\n", SchemaJson/binary, "\n\n",
    CustomPrompt/binary,
    "\n\nRESPONSE FORMAT — you must ALWAYS reply with exactly one of these two JSON forms:\n\n"
    "To call a tool:\n"
    "{\"action\":\"tool_name\",\"params\":{\"key\":\"value\"}}\n\n"
    "When you have enough information to give a final answer:\n"
    "{\"answer\":\"your response here\"}\n\n"
    "Rules:\n"
    "- Call tools as many times as needed before answering\n"
    "- Only call tools listed in AVAILABLE TOOLS\n"
    "- Fill params from the user query; omit optional params if not mentioned\n"
    "- Output ONLY the JSON — no extra text outside the JSON object"
  >>.

%% ---------------------------------------------------------------------------
%% encode_tool_result/2 — format a tool result as the next user message
%% ---------------------------------------------------------------------------
encode_tool_result(ToolName, {ok, Data}) ->
  jsx:encode(#{
    tool   => atom_to_binary(ToolName, utf8),
    status => <<"ok">>,
    result => safe_encode_data(Data)
  });
encode_tool_result(ToolName, {error, Reason}) ->
  jsx:encode(#{
    tool   => atom_to_binary(ToolName, utf8),
    status => <<"error">>,
    reason => iolist_to_binary(io_lib:format("~p", [Reason]))
  }).

%% Convert arbitrary Erlang term into something jsx:encode can handle.
%% Maps with atom keys need conversion; nested structures are traversed.
safe_encode_data(M) when is_map(M) ->
  maps:fold(fun(K, V, Acc) ->
    Key = if is_atom(K) -> atom_to_binary(K, utf8); true -> K end,
    maps:put(Key, safe_encode_data(V), Acc)
  end, #{}, M);
safe_encode_data(L) when is_list(L) ->
  [safe_encode_data(E) || E <- L];
safe_encode_data(A) when is_atom(A) ->
  atom_to_binary(A, utf8);
safe_encode_data(V) ->
  V.

%% Strip markdown code fences the LLM sometimes wraps around JSON
clean_json(B) ->
  Stripped = re:replace(B, <<"```(?:json)?\\s*|\\s*```">>, <<>>,
               [global, {return, binary}]),
  string:trim(Stripped).
