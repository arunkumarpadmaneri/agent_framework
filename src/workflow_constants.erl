%% =============================================================================
%% src/workflow_constants.erl
%%
%% Standard workflow patterns for pipeline agents.
%% Reference these from domain_constants.erl agent definitions.
%%
%% FUTURE DB MIGRATION
%% -------------------
%% workflow_type column in agents table stores one of:
%%   "fast" | "standard" | "planning" | "react"
%% At load time: workflow_constants:get_workflow(binary_to_atom(WorkflowType))
%% =============================================================================

-module(workflow_constants).
-export([fast_workflow/0, standard_workflow/0, planning_workflow/0,
         react_workflow/1, get_workflow/1]).

%% Fast — Haiku for intent+plan, Sonnet for format. Low cost, most queries.
fast_workflow() ->
  [
    #{step => intent,  llm_profile => claude_fast},
    #{step => plan,    llm_profile => claude_fast},
    #{step => execute, llm_profile => none},
    #{step => format,  llm_profile => claude_standard}
  ].

%% Standard — Sonnet throughout. Better quality, higher cost.
standard_workflow() ->
  [
    #{step => intent,  llm_profile => claude_standard},
    #{step => plan,    llm_profile => claude_standard},
    #{step => execute, llm_profile => none},
    #{step => format,  llm_profile => claude_standard}
  ].

%% Planning — Haiku for intent, Sonnet for complex planning and format.
planning_workflow() ->
  [
    #{step => intent,  llm_profile => claude_fast},
    #{step => plan,    llm_profile => claude_standard},
    #{step => execute, llm_profile => none},
    #{step => format,  llm_profile => claude_standard}
  ].

%% ReAct loop — single LLM drives tool calls until it produces a final answer.
react_workflow(LLMProfile) ->
  #{mode => react, llm_profile => LLMProfile}.

%% Lookup by atom name — useful when workflow type comes from DB/config.
get_workflow(fast)     -> fast_workflow();
get_workflow(standard) -> standard_workflow();
get_workflow(planning) -> planning_workflow();
get_workflow(_)        -> fast_workflow().
