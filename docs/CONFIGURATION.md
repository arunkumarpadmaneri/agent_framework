# Configuration Guide

No sys.config needed. Everything is set via functions.

---

## Quick start

Call `af_config:init/1` once when your app starts:

```erlang
af_config:init(#{
  domain_module => my_constants,
  tool_modules  => [my_hims_tools, my_mis_tools]
}).
```

That's it. Everything else uses framework defaults.

---

## init/1 — startup config

```erlang
af_config:init(#{
  %% Your constants module (agents/0 and optional llm_profiles/0)
  domain_module => my_constants,

  %% Tool modules your agents can call
  tool_modules  => [my_hims_tools, my_mis_tools, my_lims_tools],

  %% Custom LLM profiles (optional — built-ins are always available)
  llm_profiles  => [
    {my_groq_fast, [
      {provider,    groq},
      {api_key,     {env, "GROQ_API_KEY"}},
      {model,       <<"llama3-70b-8192">>},
      {max_tokens,  1024},
      {temperature, 0.0},
      {timeout_ms,  10000}
    ]}
  ],

  %% Override pipeline settings (all optional)
  pipeline_timeout_ms  => 30000,
  retry_attempts       => 5,
  react_max_iterations => 10
}).
```

---

## set/2 — change a value at runtime

Takes effect immediately, no restart:

```erlang
af_config:set(retry_attempts, 5).
af_config:set(pipeline_timeout_ms, 30000).
af_config:set(domain_module, my_other_constants).
af_config:set(react_max_iterations, 10).
```

---

## set_llm_profile/2 — add or override a profile at runtime

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

If a profile with that name already exists it is replaced. Built-in profiles are not affected.

---

## get/1 — read a value

```erlang
af_config:get(retry_attempts).          %% → 3 (default)
af_config:get(domain_module).           %% → my_constants (if set)
af_config:get(unknown_key).             %% → undefined
af_config:get(unknown_key, <<"none">>). %% → <<"none">> (your default)
```

---

## reset/0 — restore all defaults

```erlang
af_config:reset().
```

Clears everything set via `init/1` or `set/2`. Framework defaults take over again.

---

## All config keys

| Key | Default | Description |
|---|---|---|
| `domain_module` | `undefined` | Your module exporting `agents/0` |
| `tool_modules` | `[]` | Tool modules loaded per agent run |
| `agents` | `[]` | Inline agent definitions (alternative to domain_module) |
| `llm_profiles` | `[]` | Your LLM profiles, merged with built-ins |
| `llm_profiles_builtin` | `true` | `false` to disable built-in profiles |
| `pipeline_timeout_ms` | `60000` | Max time for the full pipeline (ms) |
| `retry_attempts` | `3` | LLM call retry count on failure |
| `retry_base_ms` | `1000` | Base delay between retries (ms) |
| `session_ttl_seconds` | `1800` | Session lifetime in memory |
| `max_parallel_tools` | `5` | Max concurrent tool executions |
| `react_max_iterations` | `5` | Max ReAct loop steps before stopping |

---

## Built-in LLM profiles

Always available — no config needed. API keys come from environment variables.

| Profile | Provider | Model |
|---|---|---|
| `claude_standard` | Claude | claude-sonnet-4-20250514 |
| `claude_fast` | Claude | claude-haiku-4-5-20251001 |
| `openai_standard` | OpenAI | gpt-4o |
| `gemini_standard` | Gemini | gemini-1.5-pro |
| `groq_standard` | Groq | mixtral-8x7b-32768 |

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."
export GEMINI_API_KEY="AI..."
export GROQ_API_KEY="gsk_..."
```

Override a built-in by using the same name:

```erlang
af_config:set_llm_profile(claude_standard, [
  {provider,   claude},
  {api_key,    {env, "ANTHROPIC_API_KEY"}},
  {model,      <<"claude-opus-4-8">>},
  {max_tokens, 4096},
  {timeout_ms, 60000}
]).
```

---

## Typical usage in your app supervisor

```erlang
init([]) ->
  af_config:init(#{
    domain_module => my_constants,
    tool_modules  => [my_hims_tools, my_mis_tools]
  }),
  Children = [...],
  {ok, {#{strategy => one_for_one}, Children}}.
```
