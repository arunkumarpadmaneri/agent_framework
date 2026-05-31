# Tool Calling Mechanism — Complete Flow

## High-Level Tool Call Flow

```
LLM (Planner)
    ↓
Generates Execution Plan:
  {plan, {mode, [steps]}}
    ↓
Agent Executor
  (agent_executor.erl)
    ↓
Tool Registry
  (tool_registry.erl)
    ↓
Tool Module
  (mis_tools.erl, hims_tools.erl, etc.)
    ↓
MCP Server / Database / External API
    ↓
Result → Back through chain
```

---

## Step-by-Step Tool Call Sequence

### 1️⃣ LLM Generates Execution Plan

The planner LLM receives available tools and returns a plan:

```erlang
Plan = #{
  mode => single|sequential|parallel,
  steps => [
    #{
      step_id => "step_1",
      tool => get_revenue,           % Tool name
      params => #{
        <<"period">> => <<"this month">>,
        <<"department">> => <<"cardiology">>
      },
      depends_on => []
    }
  ]
}
```

### 2️⃣ Executor Receives Plan

```erlang
% In agent_executor.erl

run(Plan, AgentDef) ->
  #{mode := Mode, steps := Steps} = Plan,
  AgentId = maps:get(id, AgentDef),
  
  case Mode of
    single     -> run_single(hd(Steps), AgentId);
    sequential -> run_sequential(Steps, AgentId, #{});
    parallel   -> run_parallel(Steps, AgentId)
  end.
```

### 3️⃣ Executor Calls Tool Registry

For **single** execution:

```erlang
run_single(#{step_id := Id, tool := Tool, params := Params}, AgentId) ->
  case tool_registry:execute(AgentId, Tool, Params) of
    {ok, Data}      -> {ok, #{Id => Data}};
    {error, Reason} -> {error, {tool_failed, Tool, Reason}}
  end.
```

**Example call:**
```erlang
tool_registry:execute(mis_agent, get_revenue, #{<<"period">> => <<"this month">>})
```

### 4️⃣ Tool Registry Looks Up Tool

```erlang
% In tool_registry.erl

execute(AgentId, ToolName, Params) ->
  % Query ETS table for: {mis_agent, get_revenue}
  case ets:lookup(agent_tools, {AgentId, ToolName}) of
    
    % Returns: {{mis_agent, get_revenue}, {mis_tools, revenue, #{...schema...}}}
    [{{_, _}, {Module, Function, _Schema}}] ->
      T0 = erlang:monotonic_time(millisecond),
      Result = try
        apply(Module, Function, [Params])  % ← Call the actual tool
      catch C:R:St -> {error, {tool_crashed, ToolName}}
      end,
      Result;
    
    [] -> {error, {unknown_tool, AgentId, ToolName}}
  end.
```

### 5️⃣ Tool Function Executes

```erlang
% In mis_tools.erl

revenue(Params) ->
  Period = maps:get(<<"period">>, Params, <<"this month">>),
  Dept   = maps:get(<<"department">>, Params, <<"all">>),
  
  % Call external MCP server or database
  hims_mcp:call(get_revenue, #{period => Period, department => Dept}).
```

**Tool receives:** `#{<<"period">> => <<"this month">>, <<"department">> => <<"cardiology">>}`

**Tool returns:** `{ok, #{revenue => 5000000, period => <<"this month">>, department => <<"cardiology">>}}`

---

## Tool Definition Structure

Every tool module must implement:

```erlang
-module(domain_tools).
-export([tool_func/1, schemas/0]).

%% REQUIRED: schemas/0 
%% Returns list of tool definitions for registration
schemas() ->
  [
    {tool_name, #{                           % ← Tool ID (used in config)
      function => tool_func,                 % ← Erlang function to call
      description => <<"What it does">>,     % ← For LLM planner
      input => #{
        param1 => <<"type/description">>,
        param2 => <<"type/description">>
      },
      output => #{
        result => <<"type/description">>
      }
    }}
  ].

%% REQUIRED: Each exported function must match schemas
tool_func(Params) ->
  % Params is a map with binary keys (from LLM)
  Value1 = maps:get(<<"param1">>, Params, default),
  Value2 = maps:get(<<"param2">>, Params, default),
  
  % Call external service
  Result = call_external_service(Value1, Value2),
  
  % Return {ok, Data} or {error, Reason}
  {ok, Result}.
```

---

## Execution Modes

### Mode: SINGLE
```erlang
%% Only one tool in the plan
run_single(#{step_id := Id, tool := Tool, params := Params}, AgentId) ->
  case tool_registry:execute(AgentId, Tool, Params) of
    {ok, Data}      -> {ok, #{Id => Data}};
    {error, Reason} -> {error, {tool_failed, Tool, Reason}}
  end.
```

**Example:**
```
Query: "What's this month's revenue?"
  ↓ (Intent + Plan)
Execute: get_revenue(#{period => "this month"})
  ↓
Return: {ok, #{revenue => 5000000}}
```

---

### Mode: SEQUENTIAL
```erlang
%% Tools run one after another
%% Each tool can use results from previous tools
run_sequential([#{step_id := Id, tool := Tool, params := Params} | Rest], AgentId, Acc) ->
  EnrichedParams = maps:put(<<"prev">>, Acc, Params),  % ← Add previous results
  case tool_registry:execute(AgentId, Tool, EnrichedParams) of
    {ok, Data}      -> run_sequential(Rest, AgentId, maps:put(Id, Data, Acc));
    {error, Reason} -> {error, {tool_failed, Tool, Reason}}
  end.
```

**Example:**
```
Query: "Compare this month's revenue vs expenses"
  ↓ (Intent + Plan)
Step 1: get_revenue(#{period => "this month"})
  ↓ Returns: step1 => #{revenue => 5000000}
Step 2: get_expenses(#{period => "this month", prev => step1_result})
  ↓ Returns: step2 => #{expenses => 3000000}
Combine: {step1 => {...}, step2 => {...}}
```

---

### Mode: PARALLEL
```erlang
%% Tools run concurrently
%% Each spawned in its own process
run_parallel(Steps, AgentId) ->
  Parent = self(),
  Timeout = application:get_env(agent_framework, pipeline_timeout_ms, 30000),

  StepIds = lists:map(fun(#{step_id := Id, tool := Tool, params := Params}) ->
    spawn_link(fun() ->
      Result = tool_registry:execute(AgentId, Tool, Params),
      Parent ! {step_done, Id, Result}  % ← Send result back
    end),
    Id
  end, Steps),

  collect(StepIds, #{}, Timeout).  % ← Collect all results
```

**Example:**
```
Query: "Get patient info, billing, and appointments"
  ↓ (Intent + Plan)
Parallel:
  Process 1: get_patient(#{patient_id => "123"})
  Process 2: get_billing(#{patient_id => "123"})
  Process 3: get_appointment(#{patient_id => "123"})
  ↓ All run concurrently
Result timeout after 30 seconds (default)
Combine all results: {step1 => {...}, step2 => {...}, step3 => {...}}
```

---

## Tool Registration Flow

### At Startup

```erlang
% In agent_framework_app.erl or similar

tool_registry:start_link(),

% Load tools for each agent
tool_registry:load_for_run(mis_agent, [mis_tools]),
tool_registry:load_for_run(hims_agent, [hims_tools]),
tool_registry:load_for_run(lims_agent, [lims_tools]).
```

### Registration Process

```erlang
load_for_run(mis_agent, [mis_tools]) ->
  % 1. Call mis_tools:schemas()
  Schemas = [
    {get_revenue, #{function => revenue, ...}},
    {get_expenses, #{function => expenses, ...}},
    {get_mis_report, #{function => report, ...}}
  ],
  
  % 2. For each schema, insert into ETS
  ets:insert(agent_tools, 
    {{mis_agent, get_revenue}, {mis_tools, revenue, #{...}}}),
  ets:insert(agent_tools, 
    {{mis_agent, get_expenses}, {mis_tools, expenses, #{...}}}),
  ets:insert(agent_tools, 
    {{mis_agent, get_mis_report}, {mis_tools, report, #{...}}}),
  
  % 3. All registered and ready to execute
  ok.
```

### ETS Table Structure

```erlang
agent_tools ETS table:

Key                              | Value
─────────────────────────────────────────────────────────────
{mis_agent, get_revenue}         | {mis_tools, revenue, #{...}}
{mis_agent, get_expenses}        | {mis_tools, expenses, #{...}}
{mis_agent, get_mis_report}      | {mis_tools, report, #{...}}
{hims_agent, get_patient}        | {hims_tools, patient, #{...}}
{hims_agent, get_billing}        | {hims_tools, billing, #{...}}
{hims_agent, get_appointment}    | {hims_tools, appointment, #{...}}
{lims_agent, get_sample}         | {lims_tools, sample, #{...}}
{lims_agent, get_test_result}    | {lims_tools, test_result, #{...}}
{lims_agent, get_lab_report}     | {lims_tools, lab_report, #{...}}
```

---

## Complete Example: From Query to Result

### Scenario
```
Agent: mis_agent (Hospital MIS)
Query: "What's this month's revenue by department?"
```

### Execution Trace

```erlang
1. INTENT STEP
   Input:  "What's this month's revenue by department?"
   Output: #{intent => get_revenue, entities => #{period => "this month"}}

2. PLAN STEP
   LLM sees available tools: [get_revenue, get_expenses, get_mis_report]
   LLM decides: Use get_revenue
   Output: #{
     mode => single,
     steps => [#{
       step_id => "step_1",
       tool => get_revenue,
       params => #{<<"period">> => <<"this month">>},
       depends_on => []
     }]
   }

3. EXECUTE STEP
   agent_executor:run_single(
     #{step_id => "step_1", tool => get_revenue, params => #{<<"period">> => <<"this month">>}},
     mis_agent
   )
   
   ↓ Call tool_registry:execute/3
   
   tool_registry:execute(
     mis_agent,
     get_revenue,
     #{<<"period">> => <<"this month">>}
   )
   
   ↓ Lookup ETS: {mis_agent, get_revenue}
     Returns: {mis_tools, revenue, #{...}}
   
   ↓ Call actual function
   
   apply(mis_tools, revenue, [#{<<"period">> => <<"this month">>}])
   
   ↓ Function executes
   
   revenue(#{<<"period">> => <<"this month">>}) ->
     Period = <<"this month">>,
     Dept = <<"all">>,
     hims_mcp:call(get_revenue, #{period => Period, department => Dept})
   
   ↓ MCP server returns
   
   {ok, #{
     revenue => 5000000,
     period => <<"this month">>,
     department => <<"all">>
   }}
   
   ↓ Back to executor
   
   {ok, #{step_1 => #{revenue => 5000000, ...}}}

4. FORMAT STEP
   Input: Query + tool results
   LLM formats: "Your hospital revenue for this month across all departments is ₹50 lakhs (₹5,000,000)."
   Output: Formatted text response
```

---

## Tool Parameter Flow

### Parameters Come From LLM

```
LLM Plan:
{
  "step_id": "step_1",
  "tool": "get_revenue",
  "params": {
    "period": "this month",
    "department": "cardiology"
  }
}
```

### Converted to Erlang Map

```erlang
#{
  step_id => "step_1",
  tool => get_revenue,
  params => #{
    <<"period">> => <<"this month">>,
    <<"department">> => <<"cardiology">>
  }
}
```

### Passed to Tool

```erlang
revenue(#{
  <<"period">> => <<"this month">>,
  <<"department">> => <<"cardiology">>
})
```

### Tool Extracts Parameters

```erlang
revenue(Params) ->
  Period = maps:get(<<"period">>, Params, <<"this month">>),
  Dept   = maps:get(<<"department">>, Params, <<"all">>),
  
  % Period = <<"this month">>
  % Dept = <<"cardiology">>
  
  hims_mcp:call(get_revenue, #{period => Period, department => Dept}).
```

---

## Error Handling

### Tool Not Found

```erlang
tool_registry:execute(mis_agent, unknown_tool, #{})
  ↓
ETS lookup fails: []
  ↓
{error, {unknown_tool, mis_agent, unknown_tool}}
```

### Tool Crashes

```erlang
tool_registry:execute(mis_agent, get_revenue, #{})
  ↓
apply(mis_tools, revenue, [#{...}]) throws exception
  ↓
catch C:R:St
  ↓
{error, {tool_crashed, get_revenue}}
```

### Tool Returns Error

```erlang
tool_registry:execute(mis_agent, get_revenue, #{})
  ↓
revenue(#{...}) returns {error, {database_error, "Connection failed"}}
  ↓
Result passed back as-is
  ↓
Agent executor logs and handles gracefully
```

---

## Summary: How Tools Are Called

| Stage | What Happens |
|-------|--------------|
| **Config** | Domain config specifies `tools => [tool1, tool2, ...]` |
| **Startup** | Tool modules registered in ETS: `{agent_id, tool_name} => {module, function, schema}` |
| **Planning** | LLM chooses which tools to use based on schemas |
| **Execution** | `tool_registry:execute(agent_id, tool_name, params)` looks up in ETS |
| **Call** | `apply(Module, Function, [Params])` calls the actual Erlang function |
| **Result** | Function returns `{ok, Data}` or `{error, Reason}` |
| **Formatting** | Results formatted by LLM into human-readable response |

---

## Next: Adding Your Own Tools

See **GENERIC_FRAMEWORK_README.md** section "Adding a New Domain" for step-by-step instructions on:
1. Creating a new tool module
2. Defining tool schemas
3. Implementing tool functions
4. Registering tools in configuration
