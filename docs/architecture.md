# Agent Framework Architecture

## Overview

The framework is built as an OTP application with a clear separation of concerns across agents, orchestrator, and service modules.

```
User query -> agent_framework -> agent_orchestrator -> [intent, plan, execute, format]
```

## Key Components

- `agent_framework`
  - Public interface exposing `run/3`, `agents/0`, and `tools/1`
  - Normalizes request context and dispatches to orchestration

- `agent_orchestrator`
  - Coordinates multi-step pipeline execution for a selected agent
  - Loads agent workflow definitions and executes each step in order

- `agent_registry`
  - Holds agent definitions loaded from domain configs
  - Provides lookup and validation by `AgentId`

- `tool_registry`
  - Maintains tool schemas and tool availability per agent
  - Enables planner validation of tool names for each agent

- `llm_router`
  - Dispatches messages to the configured provider adapter
  - Supports multiple profiles: `claude`, `openai`, `gemini`
  - Provides retry/backoff and timeout handling

- `session_mgr`
  - Tracks per-user request history and enriches context

- `rate_limiter`
  - Applies per-role throttling to protect the platform

- `agent_planner`
  - Converts LLM plan responses into executable step structures
  - Validates tool names and enforces safe plan parsing

## Workflow

1. Query arrives at `agent_framework:run/3`
2. Agent is resolved via `agent_registry`
3. Workflow steps are executed in sequence:
   - `intent` step → classify user intent
   - `plan` step → create execution plan based on agent tools
   - `execute` step → call tools or perform business logic
   - `format` step → format final response for the user
4. `agent_framework` returns a natural language answer or a structured error

## Configuration Model

- Global config: `config/sys.config`
  - Defines LLM profiles, pipeline timeouts, retry settings, and session TTL
- Domain configs: `config/domains/*.config`
  - Define domain-specific agents, prompts, tools, and workflows

## Agent/Tool Schema Example

Agents should specify:

- `id`: agent identifier (atom)
- `domain`: logical domain
- `description`: human-friendly summary
- `tools`: list of supported tool atoms
- `intent_prompt`: prompt template for intent classifier
- `format_prompt`: prompt template for response formatting
- `workflow`: ordered list of stages with `step` and `llm_profile`

Tools are validated by `tool_registry` and should expose schemas for planner and executor use.

## Deployment Considerations

- Use `rebar3 shell` for local development and debugging
- Use env vars for LLM API keys and provider credentials
- Keep domain configs separated for each business area
- Add CI to run `rebar3 compile`, `rebar3 eunit`, and lint checks
