# Tool Definition Locations — Module & Function Names

## Overview

Tool definitions are stored in **tool module files** using the `schemas/0` function. This function returns a list of tool definitions that map:

```
Tool Name (ID) → Function Name + Schema
```

Example:
```
get_revenue → revenue (function)
get_expenses → expenses (function)
get_patient → patient (function)
```

---

## Hospital Domain Tool Definitions

### 1. MIS Tools — [src/tools/mis_tools.erl](src/tools/mis_tools.erl)

**Module Name:** `mis_tools`

**Exported Functions:**
```erlang
-export([revenue/1, expenses/1, report/1, schemas/0]).
```

**Tool Definitions (schemas/0):**

```erlang
schemas() ->
  [
    {get_revenue, #{                  ← Tool Name (ID)
      function => revenue,            ← Function Name in mis_tools module
      description => <<"Get hospital revenue/income...">>,
      input => #{
        period => <<"required, e.g. 'this month'">>,
        department => <<"optional, default 'all'">>
      },
      output => #{
        revenue => <<"number">>,
        period => <<"string">>,
        department => <<"string">>
      }
    }},
    
    {get_expenses, #{                 ← Tool Name (ID)
      function => expenses,           ← Function Name in mis_tools module
      description => <<"Get hospital expenses/costs...">>,
      input => #{
        period => <<"required, e.g. 'this month'">>,
        category => <<"optional, default 'all'">>
      },
      output => #{
        expenses => <<"number">>,
        period => <<"string">>,
        category => <<"string">>
      }
    }},
    
    {get_mis_report, #{               ← Tool Name (ID)
      function => report,             ← Function Name in mis_tools module
      description => <<"Get full MIS summary report...">>,
      input => #{
        period => <<"required, e.g. 'this month'">>
      },
      output => #{
        revenue => <<"number">>,
        expenses => <<"number">>,
        profit => <<"number">>,
        outstanding => <<"number">>
      }
    }}
  ].
```

**Function Implementations:**

```erlang
%% Line 44 in mis_tools.erl
revenue(Params) ->
  Period = maps:get(<<"period">>, Params, <<"this month">>),
  Dept   = maps:get(<<"department">>, Params, <<"all">>),
  hims_mcp:call(get_revenue, #{period => Period, department => Dept}).

%% Line 50 in mis_tools.erl
expenses(Params) ->
  Period   = maps:get(<<"period">>, Params, <<"this month">>),
  Category = maps:get(<<"category">>, Params, <<"all">>),
  hims_mcp:call(get_expenses, #{period => Period, category => Category}).

%% Line 57 in mis_tools.erl
report(Params) ->
  Period = maps:get(<<"period">>, Params, <<"this month">>),
  hims_mcp:call(get_mis_report, #{period => Period}).
```

---

### 2. HIMS Tools — [src/tools/hims_tools.erl](src/tools/hims_tools.erl)

**Module Name:** `hims_tools`

**Exported Functions:**
```erlang
-export([patient/1, billing/1, appointment/1, schemas/0]).
```

**Tool Definitions (schemas/0):**

```erlang
schemas() ->
  [
    {get_patient, #{                  ← Tool Name (ID)
      function => patient,            ← Function Name in hims_tools module
      description => <<"Get patient information and admission details">>,
      input => #{
        patient_id => <<"optional, unique identifier">>,
        department => <<"optional, default 'all'">>
      },
      output => #{
        patient_id => <<"string">>,
        name => <<"string">>,
        department => <<"string">>,
        admission_date => <<"string">>
      }
    }},
    
    {get_billing, #{                  ← Tool Name (ID)
      function => billing,            ← Function Name in hims_tools module
      description => <<"Get billing and invoice details...">>,
      input => #{
        patient_id => <<"optional, unique identifier">>,
        department => <<"optional, default 'all'">>
      },
      output => #{
        patient_id => <<"string">>,
        invoice_id => <<"string">>,
        amount => <<"number">>,
        status => <<"string">>
      }
    }},
    
    {get_appointment, #{              ← Tool Name (ID)
      function => appointment,        ← Function Name in hims_tools module
      description => <<"Get appointment schedule and OPD details">>,
      input => #{
        date => <<"optional, e.g. 'today'">>,
        department => <<"optional, default 'all'">>
      },
      output => #{
        appointment_id => <<"string">>,
        date => <<"string">>,
        time => <<"string">>,
        department => <<"string">>
      }
    }}
  ].
```

**Function Implementations:**

```erlang
%% Line 41 in hims_tools.erl
patient(Params) ->
  PatientId = maps:get(<<"patient_id">>, Params, undefined),
  Dept      = maps:get(<<"department">>, Params, <<"all">>),
  hims_mcp:call(get_patient, #{patient_id => PatientId, department => Dept}).

%% Line 50 in hims_tools.erl
billing(Params) ->
  PatientId = maps:get(<<"patient_id">>, Params, undefined),
  Dept      = maps:get(<<"department">>, Params, <<"all">>),
  hims_mcp:call(get_billing, #{patient_id => PatientId, department => Dept}).

%% Line 59 in hims_tools.erl
appointment(Params) ->
  Date = maps:get(<<"date">>, Params, <<"today">>),
  Dept = maps:get(<<"department">>, Params, <<"all">>),
  hims_mcp:call(get_appointment, #{date => Date, department => Dept}).
```

---

### 3. LIMS Tools — [src/tools/lims_tools.erl](src/tools/lims_tools.erl)

**Module Name:** `lims_tools`

**Exported Functions:**
```erlang
-export([sample/1, test_result/1, lab_report/1, schemas/0]).
```

**Tool Definitions (schemas/0):**

```erlang
schemas() ->
  [
    {get_sample, #{                   ← Tool Name (ID)
      function => sample,             ← Function Name in lims_tools module
      description => <<"Get lab sample status and collection details">>,
      input => #{
        sample_id => <<"optional, unique identifier">>,
        patient_id => <<"optional, unique identifier">>
      },
      output => #{
        sample_id => <<"string">>,
        patient_id => <<"string">>,
        status => <<"string">>,
        collection_date => <<"string">>
      }
    }},
    
    {get_test_result, #{              ← Tool Name (ID)
      function => test_result,        ← Function Name in lims_tools module
      description => <<"Get lab test results for a patient or sample">>,
      input => #{
        sample_id => <<"optional, unique identifier">>,
        patient_id => <<"optional, unique identifier">>,
        test_type => <<"optional, e.g. 'CBC', 'LFT'">>
      },
      output => #{
        sample_id => <<"string">>,
        test_type => <<"string">>,
        result => <<"string">>,
        normal_range => <<"string">>
      }
    }},
    
    {get_lab_report, #{               ← Tool Name (ID)
      function => lab_report,         ← Function Name in lims_tools module
      description => <<"Get full laboratory report for a patient">>,
      input => #{
        patient_id => <<"required, unique identifier">>,
        date => <<"optional, e.g. 'today'">>
      },
      output => #{
        patient_id => <<"string">>,
        report_id => <<"string">>,
        tests => <<"array">>,
        summary => <<"string">>
      }
    }}
  ].
```

**Function Implementations:**

```erlang
%% Line 43 in lims_tools.erl
sample(Params) ->
  SampleId  = maps:get(<<"sample_id">>, Params, undefined),
  PatientId = maps:get(<<"patient_id">>, Params, undefined),
  lims_mcp:call(get_sample, #{sample_id => SampleId, patient_id => PatientId}).

%% Line 52 in lims_tools.erl
test_result(Params) ->
  SampleId  = maps:get(<<"sample_id">>, Params, undefined),
  PatientId = maps:get(<<"patient_id">>, Params, undefined),
  TestType  = maps:get(<<"test_type">>, Params, <<"all">>),
  lims_mcp:call(get_test_result, #{
    sample_id  => SampleId,
    patient_id => PatientId,
    test_type  => TestType
  }).

%% Line 65 in lims_tools.erl
lab_report(Params) ->
  % implementation
```

---

## Tool Definition Mapping

### Quick Reference: Tool Name → Function

| Domain | Tool Name | Module | Function | File |
|--------|-----------|--------|----------|------|
| Hospital (MIS) | `get_revenue` | `mis_tools` | `revenue/1` | [mis_tools.erl:44](src/tools/mis_tools.erl#L44) |
| Hospital (MIS) | `get_expenses` | `mis_tools` | `expenses/1` | [mis_tools.erl:50](src/tools/mis_tools.erl#L50) |
| Hospital (MIS) | `get_mis_report` | `mis_tools` | `report/1` | [mis_tools.erl:57](src/tools/mis_tools.erl#L57) |
| Hospital (HIMS) | `get_patient` | `hims_tools` | `patient/1` | [hims_tools.erl:41](src/tools/hims_tools.erl#L41) |
| Hospital (HIMS) | `get_billing` | `hims_tools` | `billing/1` | [hims_tools.erl:50](src/tools/hims_tools.erl#L50) |
| Hospital (HIMS) | `get_appointment` | `hims_tools` | `appointment/1` | [hims_tools.erl:59](src/tools/hims_tools.erl#L59) |
| Hospital (LIMS) | `get_sample` | `lims_tools` | `sample/1` | [lims_tools.erl:43](src/tools/lims_tools.erl#L43) |
| Hospital (LIMS) | `get_test_result` | `lims_tools` | `test_result/1` | [lims_tools.erl:52](src/tools/lims_tools.erl#L52) |
| Hospital (LIMS) | `get_lab_report` | `lims_tools` | `lab_report/1` | [lims_tools.erl:65](src/tools/lims_tools.erl#L65) |

---

## How Tool Definitions Are Used

### 1. At Startup — Agent Registry Loads Agents

**File:** [agent_registry.erl:60](src/agents/agent_registry.erl#L60)

```erlang
load_agents() ->
  AgentDefs = application:get_env(agent_framework, agents, []),
  lists:foreach(fun(Def) ->
    Id = maps:get(id, Def),
    Tools = maps:get(tools, Def),  % ← Get tool names list
    % Tools = [get_revenue, get_expenses, get_mis_report]
    ets:insert(agent_definitions, {Id, Def})
  end, AgentDefs).
```

Agent definition includes tool names:
```erlang
#{
  id => mis_agent,
  tools => [get_revenue, get_expenses, get_mis_report],  ← Tool names from config
  ...
}
```

---

### 2. Per-Request — Tool Registry Loads Tool Functions

**File:** [tool_registry.erl:41](src/tools/tool_registry.erl#L41)

```erlang
load_for_run(AgentId, ToolModules) ->
  % ToolModules = [mis_tools]
  % ToolNames from config = [get_revenue, get_expenses, get_mis_report]
  
  lists:foreach(fun(Module) ->
    % Module = mis_tools
    
    Schemas = Module:schemas(),
    % Schemas = [
    %   {get_revenue, #{function => revenue, ...}},
    %   {get_expenses, #{function => expenses, ...}},
    %   {get_mis_report, #{function => report, ...}}
    % ]
    
    lists:foreach(fun({ToolName, Schema}) ->
      % ToolName = get_revenue
      % Schema = #{function => revenue, ...}
      
      FunctionName = maps:get(function, Schema),
      % FunctionName = revenue
      
      ets:insert(agent_tools, {
        {AgentId, ToolName},
        {Module, FunctionName, Schema}
      }),
      % Stored as:
      % {{mis_agent, get_revenue}, {mis_tools, revenue, #{...}}}
      
    end, Schemas)
  end, ToolModules).
```

---

### 3. Execution — Tool Registry Calls Tool Function

**File:** [tool_registry.erl:65](src/tools/tool_registry.erl#L65)

```erlang
execute(AgentId, ToolName, Params) ->
  % AgentId = mis_agent
  % ToolName = get_revenue
  % Params = #{<<"period">> => <<"this month">>}
  
  case ets:lookup(agent_tools, {AgentId, ToolName}) of
    [{{_, _}, {Module, Function, _Schema}}] ->
      % Found: {mis_tools, revenue, schema}
      % Module = mis_tools
      % Function = revenue
      
      Result = try
        apply(Module, Function, [Params])
        % Calls: mis_tools:revenue(#{<<"period">> => <<"this month">>})
      catch C:R:St ->
        {error, {tool_crashed, ToolName}}
      end,
      Result;
    [] ->
      {error, {unknown_tool, AgentId, ToolName}}
  end.
```

---

## Schema Structure

Each tool definition in `schemas()` must follow this format:

```erlang
{
  ToolName,                    % Atom used in config and LLM plan
  #{
    function => FunctionName,  % Atom of function to call in this module
    description => Description, % For LLM to understand what tool does
    input => #{                 % Parameters the tool accepts
      param1 => <<"type/description">>,
      param2 => <<"type/description">>
    },
    output => #{                % What the tool returns
      result1 => <<"type/description">>,
      result2 => <<"type/description">>
    }
  }
}
```

**Example from mis_tools.erl:**

```erlang
{get_revenue, #{              % ← Tool name (used in config and plan)
  function => revenue,        % ← Function to call: mis_tools:revenue/1
  description => <<"Get hospital revenue/income for a period and department">>,
  input => #{
    period => <<"required, e.g. 'this month'">>,
    department => <<"optional, default 'all'">>
  },
  output => #{
    revenue => <<"number">>,
    period => <<"string">>,
    department => <<"string">>
  }
}}
```

---

## Complete Flow: From Config to Execution

```
1. CONFIG: config/domains/hospital.config
   {agents, [
     #{
       id => mis_agent,
       tools => [get_revenue, get_expenses, get_mis_report]  ← Tool names
     }
   ]}

2. AGENT REGISTRY: agent_registry.erl:60
   load_agents() reads config
   Stores: {mis_agent, #{tools => [get_revenue, ...], ...}}

3. PIPELINE START: agent_orchestrator.erl:75
   execute_pipeline(mis_agent, Query, Ctx)
   Gets: Tools = [get_revenue, get_expenses, get_mis_report]
   Looks up: mis_tools module

4. TOOL REGISTRY: tool_registry.erl:41
   load_for_run(mis_agent, [mis_tools])
   Calls: mis_tools:schemas()
   Gets: [
     {get_revenue, #{function => revenue, ...}},
     {get_expenses, #{function => expenses, ...}},
     {get_mis_report, #{function => report, ...}}
   ]
   Stores in ETS:
     {{mis_agent, get_revenue}, {mis_tools, revenue, #{...}}}
     {{mis_agent, get_expenses}, {mis_tools, expenses, #{...}}}
     {{mis_agent, get_mis_report}, {mis_tools, report, #{...}}}

5. EXECUTION: tool_registry.erl:65
   execute(mis_agent, get_revenue, #{period => "this month"})
   Lookup: {{mis_agent, get_revenue}, {mis_tools, revenue, schema}}
   Call: apply(mis_tools, revenue, [#{period => "this month"}])
   Result: {ok, #{revenue => 5000000, ...}}
```

---

## Files to Read

| File | Line | Content |
|------|------|---------|
| [mis_tools.erl](src/tools/mis_tools.erl#L15) | 15-36 | Tool definitions & function names |
| [hims_tools.erl](src/tools/hims_tools.erl#L15) | 15-37 | Tool definitions & function names |
| [lims_tools.erl](src/tools/lims_tools.erl#L15) | 15-45 | Tool definitions & function names |
| [config/domains/hospital.config](config/domains/hospital.config#L30) | 30 | Tool names in agent config |
| [tool_registry.erl](src/tools/tool_registry.erl#L41) | 41-59 | Tool loading mechanism |
| [tool_registry.erl](src/tools/tool_registry.erl#L65) | 65-82 | Tool execution mechanism |

---

## Summary

**Tool definitions exist in TWO places:**

### 1. **In Tool Module** (`schemas/0` function)
   - **Location:** `src/tools/{domain}_tools.erl`
   - **Content:** Maps Tool Name → Function Name + Schema
   - **Example:** `{get_revenue, #{function => revenue, ...}}`

### 2. **In Config** (referenced by agent)
   - **Location:** `config/domains/{domain}.config`
   - **Content:** Lists which tools an agent can use
   - **Example:** `tools => [get_revenue, get_expenses, ...]`

### Execution Flow

```
Config (tool names)
    ↓
Agent Registry (loads agent defs)
    ↓
Pipeline starts (extracts tool names)
    ↓
Tool Registry (looks up schemas from module)
    ↓
ETS table populated (tool name → {module, function, schema})
    ↓
Pipeline executes (calls function via apply)
```

All tool definitions are **configuration-driven** — just edit config files and modules, no framework code changes needed!
