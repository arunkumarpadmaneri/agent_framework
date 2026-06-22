# Agent and Tool Schema Reference

This document defines the agent and tool schema conventions used by the Agent Framework.

## Agent Schema

Agent definitions are loaded from domain config files under `config/domains/*.config`.
Each agent is represented as a map with the following fields:

- `id` — atom, unique agent identifier (for example `mis_agent`, `hims_agent`, `order_agent`)
- `domain` — atom, logical domain name (for example `hospital`, `ecommerce`)
- `description` — binary, human-readable description of the agent
- `tools` — list of tool names (atoms) available to this agent
- `intent_prompt` — binary prompt template used by the intent classification step
- `format_prompt` — binary prompt template used by the formatting step
- `workflow` — ordered list of workflow step maps

### Workflow step schema

Each workflow step is a map with:

- `step` — atom, one of `intent`, `plan`, `execute`, `format`
- `llm_profile` — atom naming an LLM profile, or `none` for no LLM

Example:

```erlang
#{
  step => intent,
  llm_profile => claude_fast
}
```

### Example agent definition

```erlang
#{
  id => mis_agent,
  domain => hospital,
  description => "Hospital Management Information System (MIS) agent",
  tools => [get_revenue, get_expenses, get_mis_report],
  intent_prompt => <<"...">>,
  format_prompt => <<"...">>,
  workflow => [
    #{step => intent, llm_profile => claude_fast},
    #{step => plan, llm_profile => claude_fast},
    #{step => execute, llm_profile => none},
    #{step => format, llm_profile => claude_standard}
  ]
}
```

## Tool Schema

Tool modules declare the tools they expose by implementing a `schemas/0` function.
Each tool schema is a tuple `{ToolName, SchemaMap}`.

`ToolName` is an atom representing the tool, and `SchemaMap` must include:

- `name` — tool name atom (added by the registry for LLM consumption)
- `function` — atom name of the function to invoke in the tool module
- `description` — binary description of what the tool does
- `params` — schema map describing input parameters expected for the tool
- additional metadata as needed by the planner or UI

### Example tool schema

```erlang
[{get_revenue, #{
    function => revenue,
    description => "Return revenue figures",
    params => #{department => string, period => string}
  }}]
```

### HTTP and API tool schema examples

Tool modules can also describe external service calls. For example, `http_api_tools` exposes `http_get/1` and `http_post/1` with optional auth and JSON body support.

```erlang
{http_get, #{function => http_get,
             description => "Send an HTTP GET request",
             params => #{url => string,
                         headers => list,
                         auth => map}}}

{http_post, #{function => http_post,
              description => "Send an HTTP POST request with JSON body",
              params => #{url => string,
                          headers => list,
                          auth => map,
                          body => string}}}
```

Similarly, database tools can expose connection-backed tool actions, for example:

```erlang
{db_query, #{function => db_query,
             description => "Execute a SQL query against the database",
             params => #{query => string,
                         connection => map}}}
```

## Tool module requirements

Tool modules must expose a `schemas/0` function and implement matching functions for each tool.
Example:

```erlang
-module(mis_tools).
-export([schemas/0, revenue/1, expenses/1, mis_report/1]).

schemas() ->
  [
    {get_revenue, #{function => revenue,
                   description => "Fetch revenue metrics",
                   params => #{period => string, department => string}}},
    {get_expenses, #{function => expenses,
                    description => "Fetch expense totals",
                    params => #{period => string, department => string}}},
    {get_mis_report, #{function => mis_report,
                      description => "Create a financial summary report",
                      params => #{period => string}}}
  ].
```

## Registry behavior

### `agent_registry`

- Loads agents from `application:get_env(agent_framework, agents, [])`
- Stores definitions in an ETS table called `agent_definitions`
- Exposes `lookup/1` and `list/0`

### `tool_registry`

- Maintains an ETS table `agent_tools`
- Loaded per run by `tool_registry:load_for_run(AgentId, ToolModules)`
- Exposes `schemas_for(AgentId)` for planner LLM prompts
- Exposes `execute(AgentId, ToolName, Params)` for execution
- Validates tool existence with `exists/2`

## Planner contract

The planner expects tool schemas without internal `function` fields in JSON sent to the LLM.
The tool registry strips `function` before sending tool metadata to the planner.

## Recommended schema patterns

- Keep tool names stable and descriptive
- Define `params` clearly, using simple types (`string`, `integer`, `boolean`, `map`, `list`)
- Provide full natural-language descriptions for tools
- Ensure every agent `tools` list matches available tool schemas
- Avoid sharing tool names across domains if you want strong isolation
