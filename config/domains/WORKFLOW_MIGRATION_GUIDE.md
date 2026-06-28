%% =============================================================================
%% config/domains/WORKFLOW_MIGRATION_GUIDE.md
%%
%% Guide to the new unified workflow system for Agent Framework
%% =============================================================================

# Workflow Migration Guide

## Overview

The Agent Framework now uses a unified workflow definition system through Erlang constant modules. This provides:

- **Consistency** — Standard workflow patterns across all agents
- **Reusability** — Define once, use everywhere
- **Maintainability** — Change workflows in one place
- **Flexibility** — Easy to extend with new workflow types

## Key Changes

### Before (Inline Workflows)

Workflows were defined inline in each agent definition:

```erlang
#{
  id => mis_agent,
  workflow => [
    #{step => intent,   llm_profile => claude_fast},
    #{step => plan,     llm_profile => claude_fast},
    #{step => execute,  llm_profile => none},
    #{step => format,   llm_profile => claude_standard}
  ]
}
```

**Problem**: Duplicate definitions, hard to change globally.

### After (Unified Workflows)

Workflows are now defined in `workflow_constants.erl` and referenced in agents:

```erlang
#{
  id => mis_agent,
  workflow => workflow_constants:fast_workflow()
}
```

**Benefits**: DRY principle, single source of truth, easier refactoring.

## Workflow Types

### 1. Fast Workflow (Default)

**Profile**: `workflow_constants:fast_workflow()`

Optimized for **speed and cost** — uses Claude Haiku for thinking steps.

```erlang
[
  #{step => intent,   llm_profile => claude_fast},
  #{step => plan,     llm_profile => claude_fast},
  #{step => execute,  llm_profile => none},
  #{step => format,   llm_profile => claude_standard}
]
```

**Use for**:
- Simple intent classification
- Fast responses required
- Cost-sensitive applications
- **All current hospital/ecommerce/API agents**

---

### 2. Standard Workflow

**Profile**: `workflow_constants:standard_workflow()`

Balanced **quality and cost** — uses Claude Sonnet for thinking steps.

```erlang
[
  #{step => intent,   llm_profile => claude_standard},
  #{step => plan,     llm_profile => claude_standard},
  #{step => execute,  llm_profile => none},
  #{step => format,   llm_profile => claude_standard}
]
```

**Use for**:
- Complex queries requiring better reasoning
- Standard production agents
- Balanced cost/quality needs

**Example**:
```erlang
demo_agent() ->
  #{
    id => demo_agent,
    workflow => workflow_constants:standard_workflow()
  }.
```

---

### 3. Planning Workflow

**Profile**: `workflow_constants:planning_workflow()`

Optimized for **multi-step reasoning** — fast intent, standard planning.

```erlang
[
  #{step => intent,   llm_profile => claude_fast},
  #{step => plan,     llm_profile => claude_standard},
  #{step => execute,  llm_profile => none},
  #{step => format,   llm_profile => claude_standard}
]
```

**Use for**:
- Agents requiring complex planning
- Multi-tool orchestration
- Decision-heavy workflows

---

### 4. Execution-Only Workflow

**Profile**: `workflow_constants:execution_only_workflow()`

**No LLM** — purely deterministic execution and formatting.

```erlang
[
  #{step => intent,   llm_profile => none},
  #{step => plan,     llm_profile => none},
  #{step => execute,  llm_profile => none},
  #{step => format,   llm_profile => none}
]
```

**Use for**:
- Template-based responses
- Deterministic tool execution
- Cost optimization (zero LLM calls)

---

## How Agent Registry Loads Workflows

The updated `agent_registry.erl` loads agents in this order:

1. **Base agents** from `sys.config` (if defined)
2. **Constant module agents** from:
   - `hospital_constants:agents()`
   - `ecommerce_constants:agents()`
   - `api_example_constants:agents()`
3. **Config file agents** from `config/domains/*.config`

This ensures:
- Old config files still work (backward compatibility)
- New constant modules are preferred
- No conflicts between sources

```erlang
%% In agent_registry.erl
load_agents() ->
  BaseAgents      = application:get_env(agent_framework, agents, []),
  ConstantAgents  = load_from_constants(),
  ConfigAgents    = load_domain_configs(),
  Agents          = BaseAgents ++ ConstantAgents ++ ConfigAgents,
  %% Register all agents...
```

## Creating New Agents with Workflows

### Step 1: Create a Constant Module

```erlang
-module(my_domain_constants).
-export([agents/0, my_agent/0]).

my_agent() ->
  #{
    id       => my_agent,
    domain   => my_domain,
    tools    => [tool1, tool2],
    workflow => workflow_constants:fast_workflow()  %% Choose workflow type
  }.

agents() -> [my_agent()].
```

### Step 2: Register the Module

Add the module to `load_from_constants()` in `agent_registry.erl`:

```erlang
load_from_constants() ->
  ConstantModules = [
    hospital_constants,
    ecommerce_constants,
    api_example_constants,
    my_domain_constants  %% Add here
  ],
  %% ... rest of function
```

### Step 3: Test

```bash
rebar3 compile
rebar3 shell
```

```erlang
agent_framework:agents().
%% [mis_agent, hims_agent, ..., my_agent]

agent_framework:run(my_agent, <<"query">>, #{user_id => <<"user_1">>}).
```

## Customizing Workflows

### Option 1: Use Existing Workflow Types

Simply reference the workflow constant:

```erlang
my_agent() ->
  #{
    id       => my_agent,
    workflow => workflow_constants:planning_workflow()
  }.
```

### Option 2: Extend with New Workflow Types

Add a new function to `workflow_constants.erl`:

```erlang
%% New workflow type
research_workflow() ->
  [
    #{step => intent,   llm_profile => claude_standard},
    #{step => plan,     llm_profile => openai_standard},     %% Mix providers
    #{step => execute,  llm_profile => none},
    #{step => format,   llm_profile => claude_standard}
  ].

get_workflow(research) -> research_workflow();
get_workflow(Type)     -> get_workflow(fast).  %% Default fallback
```

Then use in agents:

```erlang
research_agent() ->
  #{
    id       => research_agent,
    workflow => workflow_constants:research_workflow()
  }.
```

### Option 3: Inline Custom Workflow

For one-off agents, define inline:

```erlang
unique_agent() ->
  #{
    id => unique_agent,
    workflow => [
      #{step => intent,   llm_profile => groq_standard},
      #{step => plan,     llm_profile => gemini_standard},
      #{step => execute,  llm_profile => none},
      #{step => format,   llm_profile => claude_fast}
    ]
  }.
```

## Migration Checklist

- [x] Created `workflow_constants.erl` with standard patterns
- [x] Updated `hospital_constants.erl` to use workflows
- [x] Updated `ecommerce_constants.erl` to use workflows
- [x] Updated `api_example_constants.erl` to use workflows
- [x] Updated `agent_registry.erl` to load from constant modules
- [ ] Test all agents load correctly: `agent_framework:agents()`
- [ ] Run existing tests: `rebar3 eunit && rebar3 ct`
- [ ] Verify backward compatibility with `.config` files

## Troubleshooting

### "Undefined function workflow_constants:fast_workflow"

**Cause**: Module not loaded or compiled.

**Fix**:
```bash
rebar3 clean
rebar3 compile
rebar3 shell
```

### Agent Not Loading

**Check**:
1. Is the module listed in `load_from_constants()`?
2. Does the module export `agents/0`?
3. Are all agent definitions valid maps?

```erlang
%% In shell
rebar3 shell
> agent_registry:list().  %% Should show your agent
```

### Workflow Step Fails

**Check**: Is the `llm_profile` defined in `sys.config`?

```erlang
%% In sys.config
{llm_profiles, [
  {claude_fast, [...]},
  {my_custom_profile, [...]}  %% Add if missing
]}
```

## Performance Notes

- Workflows are loaded once at startup
- Constant module functions are inlined by Erlang compiler
- No runtime performance penalty vs inline definitions
- Smaller code footprint across multiple agents

## See Also

- [TOOL_DEFINITIONS_GUIDE.md](../../TOOL_DEFINITIONS_GUIDE.md)
- [architecture.md](../../docs/architecture.md)
- [README.md](../../README.md)
