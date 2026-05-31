%% =============================================================================
%% src/orchestrator/agent_formatter.erl
%%
%% Workflow Step: FORMAT
%%
%% Receives raw tool results and formats them into a readable response.
%% Uses the LLM profile assigned to this step in the workflow config.
%% Uses a domain-specific system prompt per agent.
%%
%% Returns: {ok, BinaryText} | {error, Reason}
%% =============================================================================

-module(agent_formatter).
-export([run/6]).

run(Query, Plan, ToolResults, AgentDef, _Ctx, LLMProfile) ->
  AgentId   = maps:get(id, AgentDef),
  #{mode := Mode, steps := Steps} = Plan,
  ToolNames = [atom_to_binary(maps:get(tool, S)) || S <- Steps],

  Msg = jsx:encode(#{
    query      => Query,
    mode       => Mode,
    tools_used => ToolNames,
    data       => ToolResults
  }),
  Messages = [#{<<"role">> => <<"user">>, <<"content">> => Msg}],

  %% Format prompt comes from agent definition or use generic fallback
  FormatPrompt = maps:get(format_prompt, AgentDef, generic_format_prompt()),

  case llm_router:call(LLMProfile, Messages, FormatPrompt) of
    {ok, Text} ->
      af_logger:info(format_ok, #{agent => AgentId, len => byte_size(Text)}),
      {ok, Text};
    {error, Reason} ->
      af_logger:error(format_failed, #{agent => AgentId, reason => Reason}),
      %% Fallback: return raw JSON rather than nothing
      {ok, jsx:encode(#{note => <<"Formatting failed">>, data => ToolResults})}
  end.

%% Generic fallback format prompt
generic_format_prompt() ->
  <<"Format the data into a clear, human-readable response.\n"
    "Be concise and accurate. Plain text only.">>.
