# Tool Loading at Startup — Complete Flow

## Where Tools Are Loaded

Tools are loaded in **two phases**:

1. **At Framework Startup** (one-time)
   - Location: [agent_registry.erl](src/agents/agent_registry.erl#L56)
   - Loads: Agent definitions from config (`agents` list in `sys.config` or domain configs)
   - What's stored: Agent ID → Agent definition map (tools list + prompts + workflow)

2. **Per-Request at Pipeline Start** (for each query)
   - Location: [agent_orchestrator.erl](src/orchestrator/agent_orchestrator.erl#L82)
   - Loads: Specific agent's tools into ETS table
   - What's stored: `{AgentId, ToolName} → {Module, Function, Schema}`

---

## Phase 1: Framework Startup

### Entry Point: [agent_framework_app.erl](src/agent_framework_app.erl)

```erlang
start(_Type, _Args) ->
  %% Step 1: Start required dependencies
  ok = ensure_started(inets),
  ok = ensure_started(ssl),
  ok = ensure_started(crypto),

  %% Step 2: Start tool registry (creates ETS table)
  ok = tool_registry:start(),

  %% Step 3: Start supervision tree
  agent_framework_sup:start_link().
```

**What happens:**
- Creates empty ETS table: `agent_tools`
- Starts supervisor

---

### Supervision Tree: [agent_framework_sup.erl](src/agent_framework_sup.erl)

```erlang
init([]) ->
  SupFlags = #{strategy => one_for_one, intensity => 5, period => 10},

  Children = [
    worker(tool_registry),           % 1. ETS store for tools
    worker(llm_router),              % 2. LLM provider routing
    worker(session_mgr),             % 3. Session history
    worker(rate_limiter),            % 4. Rate limiting
    worker(agent_registry),          % 5. Agent definitions
    worker(agent_orchestrator)       % 6. Pipeline runner
  ],

  {ok, {SupFlags, Children}}.
```

**Startup order:**
1. `tool_registry` starts → creates ETS table
2. `agent_registry` starts → loads agents from config

---

### Agent Registry Initialization: [agent_registry.erl](src/agents/agent_registry.erl#L56)

```erlang
init([]) ->
  %% Create ETS table for agent definitions
  ets:new(agent_definitions, [named_table, set, protected]),
  
  %% Load all agents from sys.config
  load_agents(),
  
  {ok, #{}}.

%% Where agents are loaded:
load_agents() ->
  %% Read from application config: sys.config or domain configs
  AgentDefs = application:get_env(agent_framework, agents, []),
  
  %% For each agent definition, store in ETS
  lists:foreach(fun(Def) ->
    Id = maps:get(id, Def),
    ets:insert(agent_definitions, {Id, Def}),
    af_logger:info(agent_loaded, #{id => Id})
  end, AgentDefs).
```

**What gets loaded:**
```erlang
% From config/domains/hospital.config
#{
  id => mis_agent,
  domain => hospital,
  description => "Hospital MIS agent",
  tools => [get_revenue, get_expenses, get_mis_report],  % ← Tool names only
  intent_prompt => <<"...">>,
  format_prompt => <<"...">>,
  workflow => [...]
}
```

**Stored in ETS as:**
```erlang
agent_definitions table:
{mis_agent, #{id => mis_agent, tools => [...], ...}}
{hims_agent, #{id => hims_agent, tools => [...], ...}}
{lims_agent, #{id => lims_agent, tools => [...], ...}}
```

**Note:** At startup, only **agent definitions** are loaded. Actual tools are not loaded yet.

---

## Phase 2: Per-Request Tool Loading

### When Query Arrives: [agent_orchestrator.erl](src/orchestrator/agent_orchestrator.erl#L75)

```erlang
run(AgentId, Query, Ctx) ->
  %% Called by: agent_framework:run(AgentId, Query, Ctx)
  %% Spawns linked process to execute pipeline
  spawn_link(fun() ->
    Result = execute_pipeline(AgentId, Query, Ctx),
    gen_server:reply(From, Result)
  end).

execute_pipeline(AgentId, Query, Ctx) ->
  %% Step 0: Validate agent exists
  case agent_registry:lookup(AgentId) of
    {error, Reason} -> {error, Reason};
    
    {ok, AgentDef} ->
      %% Step 0c: Extract tools list from agent definition
      Tools = maps:get(tools, AgentDef),
      %% Tools = [get_revenue, get_expenses, get_mis_report]
      
      %% Step 0d: ← LOAD TOOLS FOR THIS AGENT ←
      ok = tool_registry:load_for_run(AgentId, Tools),
      
      %% Step 1-4: Run workflow steps
      Result = run_steps(Workflow, Query, AgentDef, Ctx1, #{}),
      Result
  end.
```

**What happens:**

Line 82 of agent_orchestrator.erl:
```erlang
ok = tool_registry:load_for_run(AgentId, Tools)
```

This calls:
```erlang
tool_registry:load_for_run(mis_agent, [get_revenue, get_expenses, get_mis_report])
```

---

### Tool Loading: [tool_registry.erl](src/tools/tool_registry.erl#L41)

```erlang
load_for_run(AgentId, ToolModules) ->
  lists:foreach(fun(Module) ->
    try
      %% Step 1: Call Module:schemas() to get tool definitions
      Schemas = Module:schemas(),
      %% Returns: [
      %%   {get_revenue, #{function => revenue, ...}},
      %%   {get_expenses, #{function => expenses, ...}},
      %%   {get_mis_report, #{function => report, ...}}
      %% ]
      
      lists:foreach(fun({ToolName, Schema}) ->
        %% Step 2: Extract function name from schema
        FunctionName = maps:get(function, Schema),
        
        %% Step 3: Insert into ETS table
        ets:insert(agent_tools, {
          {AgentId, ToolName},
          {Module, FunctionName, Schema}
        }),
        
        %% {mis_agent, get_revenue} → {mis_tools, revenue, #{...}}
        
        af_logger:info(tool_loaded, #{
          agent => AgentId,
          tool => ToolName,
          function => FunctionName
        })
      end, Schemas)
    catch C:R ->
      af_logger:error(tool_load_failed, #{
        agent => AgentId,
        module => Module,
        class => C,
        reason => R
      })
    end
  end, ToolModules),
  ok.
```

---

## Complete Startup Sequence (Timeline)

```
1. System Start
   ├─ erl -config config/sys.config

2. agent_framework_app:start/2
   ├─ ensure_started(inets, ssl, crypto)
   ├─ tool_registry:start()
   │  └─ ets:new(agent_tools, [...])  ← Empty ETS table
   └─ agent_framework_sup:start_link()
      ├─ tool_registry:init()           ← Supervisor restarts it
      ├─ llm_router:init()
      ├─ session_mgr:init()
      ├─ rate_limiter:init()
      ├─ agent_registry:init()          ← Loads agents from config
      │  └─ load_agents()
      │     └─ Read agents from sys.config
      │        └─ ets:insert(agent_definitions, ...)
      │           └─ {mis_agent, #{...tools => [...]...}}
      │           └─ {hims_agent, #{...tools => [...]...}}
      │           └─ {lims_agent, #{...tools => [...]...}}
      │
      └─ agent_orchestrator:init()
         └─ Ready to receive queries

3. Framework Ready
   └─ Ready for: agent_framework:run(mis_agent, Query, Ctx)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

4. User Query Arrives
   └─ agent_framework:run(mis_agent, "What's revenue?", Ctx)
      └─ agent_orchestrator:run(mis_agent, Query, Ctx)
         └─ spawn_link execute_pipeline(mis_agent, Query, Ctx)
            ├─ agent_registry:lookup(mis_agent)
            │  └─ Returns: #{id => mis_agent, tools => [...], ...}
            │
            ├─ Extract Tools = [get_revenue, get_expenses, ...]
            │
            └─ tool_registry:load_for_run(mis_agent, Tools)
               ├─ For each Tool module in Tools:
               │  ├─ Tool:schemas()
               │  ├─ For each schema entry:
               │  └─ ets:insert(agent_tools, {
               │       {mis_agent, get_revenue},
               │       {mis_tools, revenue, #{...}}
               │     })
               │
               └─ Tools ready for execution

5. Pipeline Execution
   ├─ INTENT  step calls llm_router
   ├─ PLAN    step calls llm_router
   ├─ EXECUTE step calls tool_registry:execute()
   │  └─ ets:lookup(agent_tools, {mis_agent, get_revenue})
   │     └─ Found: {mis_tools, revenue, schema}
   │        └─ apply(mis_tools, revenue, [Params])
   ├─ FORMAT  step calls llm_router
   └─ Response returned

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[Process ends, per-request ETS entries cleaned up? Optional.]
```

---

## Key Files and Line Numbers

| File | Line | What Happens |
|------|------|--------------|
| [agent_framework_app.erl](src/agent_framework_app.erl#L13) | 13-20 | Framework startup entry point |
| [agent_framework_sup.erl](src/agent_framework_sup.erl#L49) | 49-62 | Supervision tree definition |
| [tool_registry.erl](src/tools/tool_registry.erl#L110) | 110-115 | init/1 - creates ETS table |
| [agent_registry.erl](src/agents/agent_registry.erl#L56) | 56-66 | init/1 - loads agents from config |
| [agent_registry.erl](src/agents/agent_registry.erl#L60) | 60-68 | load_agents/0 - reads from app config |
| [agent_orchestrator.erl](src/orchestrator/agent_orchestrator.erl#L75) | 75-100 | execute_pipeline/3 - entry point per query |
| [agent_orchestrator.erl](src/orchestrator/agent_orchestrator.erl#L82) | 82 | **tool_registry:load_for_run/2** ← Tools loaded here! |
| [tool_registry.erl](src/tools/tool_registry.erl#L41) | 41-59 | load_for_run/2 - loads tools into ETS |

---

## What Gets Loaded Where

### At Startup (One-time)
**File:** `config/sys.config` or `config/domains/*.config`

```erlang
{agents, [
  #{
    id => mis_agent,
    tools => [get_revenue, get_expenses, get_mis_report],
    ...
  },
  ...
]}
```

**Loaded into:** `agent_definitions` ETS table

```erlang
{mis_agent, #{id => mis_agent, tools => [...], ...}}
```

---

### Per-Request (For each query)
**Triggered by:** `tool_registry:load_for_run(AgentId, ToolModules)` in line 82 of agent_orchestrator.erl

**Source:** Tool module definitions (e.g., `mis_tools:schemas()`)

```erlang
schemas() -> [
  {get_revenue, #{
    function => revenue,
    description => <<"...">>,
    input => #{...},
    output => #{...}
  }},
  ...
]
```

**Loaded into:** `agent_tools` ETS table

```erlang
{{mis_agent, get_revenue}, {mis_tools, revenue, #{...}}}
```

---

## Configuration Loading Order

### 1. Read sys.config

```bash
erl -config config/sys.config -s agent_framework
```

### 2. Merge Domain Configs (if needed)

Currently, domain configs must be manually added to application config. To automate:

```erlang
% In agent_registry.erl:load_agents()

load_agents() ->
  %% Load base agents from sys.config
  BaseAgents = application:get_env(agent_framework, agents, []),
  
  %% Load domain configs
  DomainAgents = load_domain_configs(),
  
  %% Merge
  AllAgents = BaseAgents ++ DomainAgents,
  
  %% Store in ETS
  lists:foreach(fun(Def) ->
    Id = maps:get(id, Def),
    ets:insert(agent_definitions, {Id, Def})
  end, AllAgents).

load_domain_configs() ->
  ConfigDir = "config/domains",
  case file:list_dir(ConfigDir) of
    {ok, Files} ->
      Configs = [F || F <- Files, filename:extension(F) == ".config"],
      lists:flatten([load_config_file(F) || F <- Configs]);
    {error, _} -> []
  end.

load_config_file(Filename) ->
  Path = filename:join("config/domains", Filename),
  case file:consult(Path) of
    {ok, [ConfigList]} ->
      proplists:get_value(agent_framework, ConfigList, []),
      agents -> [];
    {error, _} -> []
  end.
```

---

## Summary: Tool Loading Points

### **Startup Time** (agent_registry.erl:60)
```erlang
load_agents() ->
  AgentDefs = application:get_env(agent_framework, agents, []),
  lists:foreach(fun(Def) ->
    ets:insert(agent_definitions, {maps:get(id, Def), Def})
  end, AgentDefs).
```
✅ Loads **agent definitions** (including tool names)

### **Per-Request** (agent_orchestrator.erl:82)
```erlang
ok = tool_registry:load_for_run(AgentId, Tools)
```
✅ Loads **actual tool functions** into ETS

### **Tool Execution** (tool_registry.erl:65)
```erlang
execute(AgentId, ToolName, Params) ->
  case ets:lookup(agent_tools, {AgentId, ToolName}) of
    [{{_, _}, {Module, Function, _Schema}}] ->
      apply(Module, Function, [Params])
  end.
```
✅ **Calls** the actual Erlang function

---

## Flow Diagram with File References

```
config/sys.config
      ↓
agent_framework_app:start/2
      ↓
agent_framework_sup:start_link/0
      ├─ tool_registry:init/1           [tool_registry.erl:110]
      ├─ agent_registry:init/1          [agent_registry.erl:56]
      │  └─ load_agents/0               [agent_registry.erl:60]
      │     └─ Read sys.config
      │        └─ ets:insert(agent_definitions, ...)
      │
      └─ agent_orchestrator:init/1      [agent_orchestrator.erl]
         └─ Ready

User calls: agent_framework:run(mis_agent, Query, Ctx)
      ↓
agent_orchestrator:execute_pipeline/3  [agent_orchestrator.erl:75]
      ├─ agent_registry:lookup/1
      │  └─ ets:lookup(agent_definitions, mis_agent)
      │     └─ Returns: #{tools => [get_revenue, ...]}
      │
      └─ tool_registry:load_for_run/2   [tool_registry.erl:41] ← TOOLS LOADED HERE
         ├─ mis_tools:schemas/0
         ├─ ets:insert(agent_tools, {
         │    {mis_agent, get_revenue},
         │    {mis_tools, revenue, schema}
         │  })
         │
         └─ Tools ready for execution

Execute pipeline → tool_registry:execute/3 [tool_registry.erl:65]
                  └─ apply(mis_tools, revenue, [Params])
```

---

## Files to Read

To understand tool loading completely:

1. **Startup:** [agent_framework_app.erl](src/agent_framework_app.erl) + [agent_framework_sup.erl](src/agent_framework_sup.erl)
2. **Agent Loading:** [agent_registry.erl](src/agents/agent_registry.erl#L56-L68)
3. **Per-Request Tool Loading:** [agent_orchestrator.erl](src/orchestrator/agent_orchestrator.erl#L75-L100)
4. **Tool Loading Logic:** [tool_registry.erl](src/tools/tool_registry.erl#L41-L59)
5. **Tool Execution:** [tool_registry.erl](src/tools/tool_registry.erl#L64-L82)

All tool loading is **configuration-driven** and **zero-modification** — just edit config files!
