# Agent Framework — Generic Multi-Domain Orchestration Engine

A reusable, domain-agnostic Erlang framework for building multi-step agent workflows with configurable LLM integration, tool execution, and result formatting.

## Architecture Overview

```
User Query
   ↓
[INTENT]     → Classify query intent using LLM
   ↓
[PLAN]       → Build execution plan (single/sequential/parallel)
   ↓
[EXECUTE]    → Run tools based on plan
   ↓
[FORMAT]     → Format results into human-readable response
```

## Key Features

- **Domain-Agnostic**: Framework code has no domain logic. All domain knowledge lives in config files.
- **Multi-Domain Support**: Run different agents for different domains (hospital, e-commerce, banking, etc.) in the same system.
- **Pluggable Tools**: Support Erlang modules, MCP servers, or hybrid approach.
- **Configurable Workflows**: Each agent defines its own LLM profiles and workflow steps.
- **Custom Prompts per Agent**: Intent and format prompts are config-driven, not hardcoded.

## Project Structure

```
agent_framework/
├── config/
│   ├── sys.config                 # Generic framework config (LLM profiles, pipeline settings)
│   └── domains/
│       ├── hospital.config        # Hospital domain agents & prompts
│       └── ecommerce.config       # E-commerce domain agents & prompts
├── src/
│   ├── orchestrator/
│   │   ├── agent_intent.erl       # Intent classification (generic)
│   │   ├── agent_planner.erl      # Execution planning (generic)
│   │   ├── agent_executor.erl     # Tool execution (generic)
│   │   ├── agent_formatter.erl    # Result formatting (generic)
│   │   ├── agent_orchestrator.erl # Pipeline coordinator (generic)
│   │   └── agent_registry.erl     # Agent lookup & registration
│   ├── tools/
│   │   ├── mis_tools.erl          # Hospital financial tools
│   │   ├── hims_tools.erl         # Hospital patient tools
│   │   ├── lims_tools.erl         # Hospital lab tools
│   │   └── tool_registry.erl      # Per-agent tool dispatcher
│   ├── llm/
│   │   └── llm_router.erl         # LLM provider abstraction
│   └── lib/
│       └── af_logger.erl          # Logging utilities
└── rebar.config                   # Build config
```

## Adding a New Domain

### Step 1: Create Domain Config

Create `config/domains/your_domain.config`:

```erlang
[
  {agent_framework, [
    {agents, [
      #{
        id => your_agent_id,
        domain => your_domain,
        description => "Your agent description",
        tools => [tool1, tool2, tool3],
        
        % Custom intent classification prompt
        intent_prompt =>
          <<"You are a classifier for [domain].\n"
            "Return JSON: {\"intent\":\"...\",\"entities\":{},\"confidence\":0.0}">> ,
        
        % Custom result formatting prompt
        format_prompt =>
          <<"Format the result for [domain]. Plain text only.">>,
        
        workflow => [
          #{step => intent,   llm_profile => claude_fast},
          #{step => plan,     llm_profile => claude_fast},
          #{step => execute,  llm_profile => none},
          #{step => format,   llm_profile => claude_standard}
        ]
      }
    ]}
  ]}
].
```

### Step 2: Create Tool Module(s)

Create `src/tools/your_domain_tools.erl`:

```erlang
-module(your_domain_tools).
-export([tool_func/1, schemas/0]).

schemas() ->
  [
    {tool_name, #{
      function => tool_func,
      description => <<"Tool description">>,
      input => #{param1 => <<"type">>, param2 => <<"type">>},
      output => #{result => <<"type">>}
    }}
  ].

tool_func(Params) ->
  % Your tool implementation
  {ok, Result}.
```

### Step 3: Load Domain Config at Runtime

The framework will merge domain configs with the main `sys.config` automatically.

### Step 4: Use the Agent

```erlang
agent_framework:run(your_agent_id, Query, Context)
```

## Configuration Deep Dive

### Global Config (`config/sys.config`)

Defines:
- **LLM Profiles**: Named configurations for different LLM providers/models
- **Pipeline Settings**: Timeout, retry logic, concurrency limits
- **Empty Agents List**: Populated from domain configs at runtime

### Domain Config (`config/domains/*.config`)

Defines:
- **Agents**: Agent ID, description, tools, workflow, custom prompts
- **Intent Prompt**: How to classify user queries
- **Format Prompt**: How to format tool results for humans
- **Workflow Steps**: Which LLM profile to use for each step

## Generic Workflow Explained

### 1. INTENT Step
- **Input**: User query + history
- **Process**: LLM classifies query using agent's custom `intent_prompt`
- **Output**: `{intent, entities, confidence}`
- **Config**: `intent_prompt` in agent definition

### 2. PLAN Step
- **Input**: Classified intent + available tools
- **Process**: LLM builds execution plan
- **Output**: `{mode, [steps]}` where mode is `single|sequential|parallel`
- **Generic**: Uses `agent_planner:plan_prompt()` (same for all agents)

### 3. EXECUTE Step
- **Input**: Execution plan
- **Process**: Tool registry dispatches tools based on plan
- **Output**: `{step_id => result}`
- **Generic**: No LLM involved, pure tool execution

### 4. FORMAT Step
- **Input**: Original query + tool results
- **Process**: LLM formats results using agent's custom `format_prompt`
- **Output**: Human-readable text response
- **Config**: `format_prompt` in agent definition

## How It's Domain-Agnostic

### Before (Hardcoded)
```erlang
% In agent_intent.erl
intent_prompt(mis_agent) ->
  <<"MIS classifier prompt">>;
intent_prompt(hims_agent) ->
  <<"HIMS classifier prompt">>.
```
**Problem**: Framework knows about hospitals, can't be reused.

### After (Config-Driven)
```erlang
% In agent_intent.erl
run(Query, AgentDef, Ctx, LLMProfile) ->
  SystemPrompt = maps:get(intent_prompt, AgentDef, generic_intent_prompt()),
  ...
```
**Benefit**: Framework knows nothing about domains. All prompts in config.

## Tool Registration

Agents declare which tools they can use:

```erlang
tools => [get_revenue, get_expenses, get_patient, ...]
```

Tool registry maps tool names to functions:

```erlang
{tool_name, {module, function, schema}}
```

For different domains:
- Hospital: `mis_tools`, `hims_tools`, `lims_tools`
- E-commerce: Custom `ecommerce_tools`, `payment_tools`
- Any domain: Just add tools to tool registry

## LLM Profile Management

Use different LLMs for different steps:

```erlang
workflow => [
  #{step => intent,   llm_profile => claude_fast},      % Cheap classification
  #{step => plan,     llm_profile => claude_fast},      % Cheap planning
  #{step => execute,  llm_profile => none},             % No LLM needed
  #{step => format,   llm_profile => claude_standard}   % Best quality output
]
```

Change LLM for all agents of a domain by editing the domain config file.

## Extending: MCP Server Support

To support MCP servers alongside Erlang tools:

1. **Tool Registry Enhancement**: Map tool names to either:
   - `{erl_module, function}` → call Erlang function
   - `{mcp_server, tool_name}` → call MCP server

2. **Tool Executor**: Route based on tool type:
   ```erlang
   execute(AgentId, ToolName, Params) ->
     case tool_registry:lookup(ToolName) of
       {erl, Module, Function} -> apply(Module, Function, [Params]);
       {mcp, Server, Tool}     -> mcp_client:call(Server, Tool, Params)
     end.
   ```

3. **Configuration**: Declare tools as:
   ```erlang
   tools => [
     {get_revenue, erl},           % Erlang tool
     {get_weather, {mcp, service}} % MCP tool
   ]
   ```

## Running the Framework

```bash
# Start the framework
erl -config config/sys.config -s agent_framework

# Run an agent
agent_framework:run(mis_agent, "What's this month's revenue?", #{})
```

## Summary: What Makes This Generic

| Aspect | Before | After |
|--------|--------|-------|
| **Domain Logic** | Hardcoded in `.erl` files | Config files (`*.config`) |
| **Agent Prompts** | Function clauses per agent | Config maps with `intent_prompt` + `format_prompt` |
| **Workflow** | Fixed for all agents | Per-agent in config |
| **Tool Registration** | Per-domain modules | Unified registry, any domain |
| **LLM Assignment** | Hardcoded | Per-step in workflow config |
| **Reusability** | Only for hospitals | Any domain by config alone |

Now you can use this framework for:
- **Hospitals** (HMS, HIMS, LIMS)
- **E-commerce** (Orders, Products, Payments)
- **Banking** (Accounts, Transactions, Support)
- **HR Systems** (Payroll, Recruitment, Benefits)
- **Any multi-step workflow domain**

Just create a new domain config file—no code changes needed!
