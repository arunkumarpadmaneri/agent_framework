# Agent Framework Requirements & Use Cases

## Purpose

The Agent Framework is a multi-agent orchestration platform designed to coordinate natural-language-driven workflows across multiple specialized agents. It combines intent classification, planning, tool execution, and result formatting in a single configurable Erlang application.

## Core Goals

- Provide a reusable orchestration layer for agent pipelines
- Support multiple domain-specific agents with distinct tools and prompts
- Enable flexible workflows with intent, planning, execution, and formatting stages
- Allow safe integration with multiple LLM providers via adapter modules
- Maintain a lightweight, OTP-native architecture for reliability and scalability

## Primary Use Cases

### 1. Hospital Operations

- MIS agent: interpret financial queries, build reports, and summarize key metrics
- HIMS agent: answer patient, billing, and appointment questions
- LIMS agent: retrieve lab sample, test, and report information

### 2. E-Commerce Assistance

- Order agent: list orders, track status, and update orders
- Product agent: search products, provide details, and recommend items
- Payment agent: process payments, verify transactions, and refund orders

## Functional Requirements

- `agent_framework:run(AgentId, Query, Ctx)` should execute a full pipeline and return either `{ok, Response}` or `{error, Reason}`
- Configurable agents must declare:
  - `id`
  - `domain`
  - `description`
  - `tools`
  - `intent_prompt`
  - `format_prompt`
  - `workflow` steps with LLM profile assignments
- Tool registry must expose schemas for each tool and allow lookup by agent
- Agents must be able to use any supported LLM provider profile from sys.config
- The platform should support `single`, `sequential`, and `parallel` execution modes in plans

### Example: API-backed billing agent

A sample API agent is defined in `config/domains/api_example.config`.
It uses `http_api_tools` and exposes one tool, `get_bill_list`, which calls `http_api_tools:http_post/1`.

Example request parameters:

```erlang
Params = #{
  <<"url">> => <<"http://localhost:8000/api/get/billlist/itooth">>,
  <<"headers">> => [{<<"content-type">>, <<"application/x-www-form-urlencoded">>}],
  <<"body">> => #{
    <<"entitykey">> => <<"YOUR_ENTITY_KEY">>,
    <<"date">> => <<"20240622">>
  },
  <<"content_type">> => <<"application/x-www-form-urlencoded">>
}.
```

Run the OTP application:

1. Compile the app:
   - `rebar3 compile`
2. Start the OTP shell:
   - `rebar3 shell`
   - or `erl -config config/sys.config -s agent_framework`
3. Inspect loaded agents:
   - `agent_framework:agents().`
4. Run the billing agent:

```erlang
agent_framework:run(billing_agent,
  <<"Fetch the bill list for entitykey 123 on 20240622">>,
  #{role => guest, user_id => <<"web_user">>}).
```

If the planner selects the `get_bill_list` tool, `http_api_tools` will send the POST request as `application/x-www-form-urlencoded`.

## Non-functional Requirements

- Reliable startup using OTP supervision
- Clear logging of pipeline events and errors
- Config-based domain loading with separate domain config files
- Safe handling of text-to-atom conversion to avoid atom table exhaustion
- Simple testing path with `rebar3 eunit` and `rebar3 ct`

## Success Criteria

- The app boots via `rebar3 shell`
- Core services are registered and running: `tool_registry`, `llm_router`, `session_mgr`, `rate_limiter`, `agent_registry`, `agent_orchestrator`
- Sample domain configs load and expose agents
- The public API returns available agents and their tools
- The framework supports multiple LLM profiles with environment-managed keys
