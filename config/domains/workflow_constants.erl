%% =============================================================================
%% config/domains/workflow_constants.erl
%%
%% Unified workflow definitions for consistent agent orchestration.
%% Provides standard workflow patterns that agents can reference.
%% =============================================================================

-module(workflow_constants).

%% Public API
-export([
  standard_workflow/0,
  fast_workflow/0,
  planning_workflow/0,
  execution_only_workflow/0,
  get_workflow/1
]).

%% =============================================================================
%% STANDARD WORKFLOW
%% Uses Claude Sonnet for all thinking steps, none for execution
%% Balanced cost/quality for typical agents
%% =============================================================================

standard_workflow() ->
  [
    #{step => intent,   llm_profile => claude_standard},
    #{step => plan,     llm_profile => claude_standard},
    #{step => execute,  llm_profile => none},
    #{step => format,   llm_profile => claude_standard}
  ].

%% =============================================================================
%% FAST WORKFLOW
%% Uses Claude Haiku for fast operations, minimal cost
%% Suitable for simple queries and intent classification
%% =============================================================================

fast_workflow() ->
  [
    #{step => intent,   llm_profile => claude_fast},
    #{step => plan,     llm_profile => claude_fast},
    #{step => execute,  llm_profile => none},
    #{step => format,   llm_profile => claude_standard}
  ].

%% =============================================================================
%% PLANNING WORKFLOW
%% Heavy on planning, uses standard models for complex reasoning
%% Suitable for multi-step agent orchestration
%% =============================================================================

planning_workflow() ->
  [
    #{step => intent,   llm_profile => claude_fast},
    #{step => plan,     llm_profile => claude_standard},
    #{step => execute,  llm_profile => none},
    #{step => format,   llm_profile => claude_standard}
  ].

%% =============================================================================
%% EXECUTION-ONLY WORKFLOW
%% Skips LLM steps, only runs tool execution and basic formatting
%% Suitable for deterministic, template-based responses
%% =============================================================================

execution_only_workflow() ->
  [
    #{step => intent,   llm_profile => none},
    #{step => plan,     llm_profile => none},
    #{step => execute,  llm_profile => none},
    #{step => format,   llm_profile => none}
  ].

%% =============================================================================
%% get_workflow/1 — lookup workflow by name
%% Returns workflow list of step maps
%% =============================================================================

get_workflow(standard) -> standard_workflow();
get_workflow(fast)     -> fast_workflow();
get_workflow(planning) -> planning_workflow();
get_workflow(execution_only) -> execution_only_workflow();
get_workflow(fast)     -> fast_workflow();  %% default
get_workflow(_)        -> fast_workflow().  %% safe default
