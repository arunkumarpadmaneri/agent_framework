# Agent Framework — Developer Guide

This guide covers everything you need to use `agent_framework` as a dependency in your Erlang/OTP project.

---

## Table of Contents

1. [Installation](#1-installation)
2. [Project Setup](#2-project-setup)
3. [Define Your Tools](#3-define-your-tools)
4. [Define Your Agents](#4-define-your-agents)
5. [Initialize the Framework](#5-initialize-the-framework)
6. [Run Agents](#6-run-agents)
7. [Dynamic Management](#7-dynamic-management)
8. [Configuration Reference](#8-configuration-reference)
9. [LLM Profiles](#9-llm-profiles)
10. [Workflow Types](#10-workflow-types)
11. [Error Handling](#11-error-handling)

---

## 1. Installation

### rebar3

Add to your `rebar.config`:

```erlang
{deps, [
  {agent_framework, {git, "https://github.com/your-org/agent_framework.git", {branch, "main"}}}
]}.
```

### rebar2

Add to your `rebar.config`:

```erlang
{deps, [
  {agent_framework, ".*",
    {git, "https://github.com/your-org/agent_framework.git", {branch, "main"}}}
]}.
```

Add to your `.app.src` dependencies:

```erlang
{applications, [kernel, stdlib, agent_framework]}
```

---

## 2. Project Setup

### Start the framework

Ensure `agent_framework` starts before your application. In your `.app.src`:

```erlang
{applications, [kernel, stdlib, ssl, inets, agent_framework]}
```

### Set API keys in your environment

```bash
export ANTHROPIC_API_KEY="sk-ant-..."   # for Claude
export OPENAI_API_KEY="sk-..."          # for OpenAI
export GEMINI_API_KEY="AI..."           # for Gemini
export GROQ_API_KEY="gsk_..."           # for Groq
```

API keys are always read from environment variables. Never hardcode them.

---

## 3. Define Your Tools

A tool module exposes `schemas/0` plus one function per tool.

```erlang
%% src/my_hims_tools.erl
-module(my_hims_tools).
-export([schemas/0, get_patient_count/1, get_admission_list/1]).

schemas() ->
  [
    {get_patient_count, #{
      function    => get_patient_count,
      description => <<"Returns total admitted patient count.">>,
      input       => #{ward => <<"optional ward name, default all">>},
      output      => #{count => <<"integer">>}
    }},
    {get_admission_list, #{
      function    => get_admission_list,
      description => <<"Returns list of patients admitted today.">>,
      input       => #{date => <<"optional, default today (YYYY-MM-DD)">>},
      output      => #{patients => <<"list">>, total => <<"integer">>}
    }}
  ].

get_patient_count(Params) ->
  Ward = maps:get(<<"ward">>, Params, <<"all">>),
  Count = my_db:count_patients(Ward),
  {ok, #{count => Count}}.

get_admission_list(Params) ->
  Date     = maps:get(<<"date">>, Params, today()),
  Patients = my_db:admissions(Date),
  {ok, #{patients => Patients, total => length(Patients)}}.

today() ->
  {{Y, M, D}, _} = calendar:local_time(),
  list_to_binary(io_lib:format("~4..0B-~2..0B-~2..0B", [Y, M, D])).
```

**Rules for tool functions:**
- Take one argument: a `params` map with binary keys (`<<"key">>`)
- Return `{ok, ResultMap}` on success
- Return `{error, Reason}` on failure
- Keep functions focused — one thing per tool

---

## 4. Define Your Agents

Create a constants module in your project. This is the single file that maps to your DB in the future.

```erlang
%% src/my_constants.erl
-module(my_constants).
-export([agents/0]).

agents() ->
  [
    #{
      id            => hims_agent,
      domain        => hospital,
      description   => <<"Hospital information and patient management">>,
      tools         => [my_hims_tools],
      workflow      => workflow_constants:fast_workflow(),
      intent_prompt => <<"You are a hospital information assistant.
        Extract the user's intent from their query about patient data.
        Return JSON: {\"intent\": \"action_name\", \"params\": {...}}">>,
      format_prompt => <<"Format the hospital data into a clear,
        professional response for medical staff.">>
    },

    #{
      id            => mis_agent,
      domain        => hospital,
      description   => <<"Management information and reporting">>,
      tools         => [my_mis_tools],
      workflow      => workflow_constants:standard_workflow(),
      intent_prompt => <<"Extract the reporting intent from the query.
        Return JSON: {\"intent\": \"report_name\", \"params\": {...}}">>,
      format_prompt => <<"Format the report data into a concise summary.">>
    },

    #{
      id            => lims_agent,
      domain        => hospital,
      description   => <<"Lab information and test results">>,
      tools         => [my_lims_tools],
      workflow      => workflow_constants:react_workflow(claude_standard),
      react_prompt  => <<"You are a lab assistant. Use tools to look up
        test results. When you have enough information, provide a final answer.">>,
      intent_prompt => <<"Extract the lab query intent.">>,
      format_prompt => <<"Format lab results clearly.">>
    }
  ].
```

**Agent map fields:**

| Field | Required | Description |
|---|---|---|
| `id` | Yes | Unique atom identifier |
| `domain` | No | Grouping atom (hospital, ecommerce, etc.) |
| `description` | Yes | What this agent does |
| `tools` | Yes | List of tool module atoms |
| `workflow` | Yes | From `workflow_constants` — see [Workflow Types](#10-workflow-types) |
| `intent_prompt` | Yes | System prompt for the intent step |
| `format_prompt` | Yes | System prompt for the format step |
| `react_prompt` | Only for ReAct | System prompt when using ReAct workflow |

---

## 5. Initialize the Framework

Call `af_config:init/1` once when your application starts. The best place is your top-level supervisor's `init/1` or your application's `start/2`.

```erlang
%% src/my_app.erl
-module(my_app).
-behaviour(application).
-export([start/2, stop/1]).

start(_Type, _Args) ->
  af_config:init(#{
    domain_module => my_constants,
    tool_modules  => [my_hims_tools, my_mis_tools, my_lims_tools]
  }),
  my_sup:start_link().

stop(_State) -> ok.
```

That's all that's required. Everything else uses framework defaults.

**Full init options:**

```erlang
af_config:init(#{
  %% Your constants module — must export agents/0
  domain_module => my_constants,

  %% All tool modules your agents use
  tool_modules  => [my_hims_tools, my_mis_tools],

  %% Custom LLM profiles (optional — built-ins always available)
  llm_profiles  => [
    {my_fast_groq, [
      {provider,    groq},
      {api_key,     {env, "GROQ_API_KEY"}},
      {model,       <<"llama3-70b-8192">>},
      {max_tokens,  1024},
      {temperature, 0.0},
      {timeout_ms,  10000}
    ]}
  ],

  %% Override pipeline settings (all optional)
  pipeline_timeout_ms  => 60000,
  retry_attempts       => 3,
  react_max_iterations => 10,
  max_parallel_agents  => 10
}).
```

---

## 6. Run Agents

All agent execution goes through the `agent_framework` module.

### Single agent

```erlang
Ctx = #{
  role    => doctor,          %% your app's role atom
  user_id => <<"user_123">>   %% for session history
},

{ok, Response} = agent_framework:run(hims_agent, <<"How many patients were admitted today?">>, Ctx),
io:format("~s~n", [Response]).
```

### Multiple agents in parallel

```erlang
Results = agent_framework:run_all([
  {hims_agent, <<"Get patient count">>},
  {mis_agent,  <<"Get department summary">>},
  {lims_agent, <<"Get pending lab tests">>}
], #{role => admin, user_id => <<"u1">>}),

%% Results is a map keyed by agent id:
%% #{
%%   hims_agent => {ok, <<"15 patients admitted today...">>},
%%   mis_agent  => {ok, <<"Department summary: ...">>},
%%   lims_agent => {ok, <<"3 tests pending...">>}
%% }

{ok, HimsResp} = maps:get(hims_agent, Results).
```

Max concurrent agents is controlled by `max_parallel_agents` (default 10). If you pass more agents than the limit, they are chunked and each chunk runs concurrently.

---

## 7. Dynamic Management

All changes take effect on the next request. In-flight requests complete with their existing configuration.

### Add a new agent

```erlang
agent_framework:add_agent(#{
  id            => pharmacy_agent,
  domain        => hospital,
  description   => <<"Pharmacy and drug dispensing">>,
  tools         => [my_pharmacy_tools],
  workflow      => workflow_constants:fast_workflow(),
  intent_prompt => <<"Extract the pharmacy query intent.">>,
  format_prompt => <<"Format pharmacy data clearly.">>
}).
```

### Remove an agent

```erlang
agent_framework:remove_agent(pharmacy_agent).
```

### Update agent fields

```erlang
%% Switch workflow type
agent_framework:update_agent(hims_agent, #{
  workflow => workflow_constants:react_workflow(claude_standard)
}).

%% Update prompts
agent_framework:update_agent(hims_agent, #{
  intent_prompt => <<"New intent prompt for the updated domain.">>
}).

%% Change multiple fields at once
agent_framework:update_agent(hims_agent, #{
  workflow      => workflow_constants:standard_workflow(),
  tools         => [my_hims_tools, my_new_search_tool],
  format_prompt => <<"Updated format prompt.">>
}).
```

### Add / remove tools from an agent

```erlang
%% Add a tool (no-op if already present)
agent_framework:add_agent_tool(hims_agent, my_new_tool).

%% Remove a tool (no-op if not present)
agent_framework:remove_agent_tool(hims_agent, my_old_tool).
```

### Change config at runtime

```erlang
%% Any config key
af_config:set(retry_attempts, 5).
af_config:set(pipeline_timeout_ms, 30000).
af_config:set(react_max_iterations, 10).
af_config:set(max_parallel_agents, 20).

%% Add or override an LLM profile
af_config:set_llm_profile(my_fast, [
  {provider, groq},
  {api_key,  {env, "GROQ_API_KEY"}},
  {model,    <<"llama3-70b-8192">>},
  {max_tokens, 1024},
  {timeout_ms, 10000}
]).

%% Update a single field in an existing profile
af_config:update_llm_profile(claude_standard, #{
  model      => <<"claude-opus-4-8">>,
  max_tokens => 4096
}).

%% Read a value
af_config:get(retry_attempts).   %% → 5

%% Reset everything to framework defaults
af_config:reset().
```

### Introspection

```erlang
%% List all registered agent IDs
agent_framework:agents().
%% → [hims_agent, mis_agent, lims_agent]

%% List tools for an agent
agent_framework:tools(hims_agent).
%% → {ok, [my_hims_tools]}
```

---

## 8. Configuration Reference

| Key | Default | Description |
|---|---|---|
| `domain_module` | `undefined` | Your module exporting `agents/0` |
| `tool_modules` | `[]` | All tool modules across all agents |
| `agents` | `[]` | Inline agent definitions (alternative to `domain_module`) |
| `llm_profiles` | `[]` | Your custom LLM profiles |
| `llm_profiles_builtin` | `true` | Set `false` to disable built-in profiles |
| `pipeline_timeout_ms` | `60000` | Max pipeline duration per request (ms) |
| `retry_attempts` | `3` | LLM call retries on failure |
| `retry_base_ms` | `1000` | Base retry delay, doubles each attempt (ms) |
| `session_ttl_seconds` | `1800` | Session history lifetime (seconds) |
| `max_parallel_agents` | `10` | Max agents running concurrently in `run_all` |
| `max_parallel_tools` | `5` | Max tools running concurrently within one agent |
| `react_max_iterations` | `5` | Max ReAct loop steps before stopping |

---

## 9. LLM Profiles

### Built-in profiles

Always available — no configuration needed.

| Profile | Provider | Model | Best for |
|---|---|---|---|
| `claude_standard` | Claude | claude-sonnet-4-20250514 | General quality responses |
| `claude_fast` | Claude | claude-haiku-4-5-20251001 | Fast, cheap steps (intent, plan) |
| `openai_standard` | OpenAI | gpt-4o | OpenAI preference |
| `gemini_standard` | Gemini | gemini-1.5-pro | Google stack |
| `groq_standard` | Groq | mixtral-8x7b-32768 | Fast inference |

### Add a custom profile

```erlang
af_config:set_llm_profile(my_fast, [
  {provider,    groq},
  {api_key,     {env, "GROQ_API_KEY"}},
  {model,       <<"llama3-70b-8192">>},
  {max_tokens,  1024},
  {temperature, 0.0},
  {timeout_ms,  10000}
]).
```

### Override a built-in profile

Use the same name — yours takes precedence:

```erlang
af_config:set_llm_profile(claude_standard, [
  {provider,    claude},
  {api_key,     {env, "ANTHROPIC_API_KEY"}},
  {model,       <<"claude-opus-4-8">>},
  {max_tokens,  4096},
  {temperature, 0.0},
  {timeout_ms,  60000}
]).
```

### Update a single field in a profile

```erlang
%% Rotate the model
af_config:update_llm_profile(claude_standard, #{
  model => <<"claude-opus-4-8">>
}).

%% Rotate the API key env var
af_config:update_llm_profile(claude_standard, #{
  api_key => {env, "NEW_ANTHROPIC_KEY"}
}).

%% Multiple fields
af_config:update_llm_profile(groq_standard, #{
  model      => <<"llama3-70b-8192">>,
  max_tokens => 2048
}).
```

---

## 10. Workflow Types

Workflows control which LLM profile runs at each pipeline step.

### `workflow_constants:fast_workflow()`

Best for most queries. Haiku on intent + plan (cheap), Sonnet on format (quality).

```
Query → Intent (claude_fast) → Plan (claude_fast) → Execute (tools) → Format (claude_standard)
```

### `workflow_constants:standard_workflow()`

Higher quality throughout. Sonnet at every step. Good for complex queries.

```
Query → Intent (claude_standard) → Plan (claude_standard) → Execute (tools) → Format (claude_standard)
```

### `workflow_constants:planning_workflow()`

Haiku for intent, Sonnet for plan + format. For queries where planning quality matters more than speed.

```
Query → Intent (claude_fast) → Plan (claude_standard) → Execute (tools) → Format (claude_standard)
```

### `workflow_constants:react_workflow(LLMProfile)`

ReAct loop — the LLM calls tools iteratively until it has enough information, then gives a final answer. Best for open-ended or multi-step queries.

```
Query → LLM sees tools → calls tool → observes result → calls another tool → ... → Final Answer
```

```erlang
%% Use claude_standard for the ReAct loop
workflow => workflow_constants:react_workflow(claude_standard)

%% Use a custom fast profile
workflow => workflow_constants:react_workflow(my_fast_groq)
```

Requires `react_prompt` in the agent definition.

### Using a custom profile in any workflow step

You can use any profile name — built-in or your own:

```erlang
workflow => [
  #{step => intent,  llm_profile => my_fast_groq},
  #{step => plan,    llm_profile => claude_standard},
  #{step => execute, llm_profile => none},
  #{step => format,  llm_profile => claude_standard}
]
```

---

## 11. Error Handling

All functions return tagged tuples.

```erlang
case agent_framework:run(hims_agent, Query, Ctx) of
  {ok, Response} ->
    %% Response is a binary string — send to user
    send_to_user(Response);

  {error, {unknown_agent, AgentId}} ->
    %% AgentId was not registered
    {reply, 404, <<"Agent not found">>};

  {error, rate_limited} ->
    %% User exceeded request rate
    {reply, 429, <<"Too many requests">>};

  {error, timeout} ->
    %% Pipeline exceeded pipeline_timeout_ms
    {reply, 504, <<"Request timed out">>};

  {error, Reason} ->
    %% Other errors — log and return generic error
    logger:error("Agent error: ~p", [Reason]),
    {reply, 500, <<"Internal error">>}
end.
```

### run_all errors

Each agent result is independent. One agent failing does not affect others.

```erlang
Results = agent_framework:run_all(Agents, Ctx),
maps:foreach(fun(AgentId, Result) ->
  case Result of
    {ok, Resp}      -> handle_response(AgentId, Resp);
    {error, timeout} -> logger:warning("~p timed out", [AgentId]);
    {error, Reason}  -> logger:error("~p failed: ~p", [AgentId, Reason])
  end
end, Results).
```

### Tool errors

Tool functions should return `{error, Reason}` for expected failures. The framework logs and propagates the error up the pipeline.

```erlang
get_patient_count(Params) ->
  case my_db:count_patients(maps:get(<<"ward">>, Params, <<"all">>)) of
    {ok, Count}      -> {ok, #{count => Count}};
    {error, no_data} -> {error, <<"No patient data available">>};
    {error, Reason}  -> {error, Reason}
  end.
```
