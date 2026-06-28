# Agent Framework with Rebar2 Setup Guide

This guide explains how to integrate the Agent Framework into a **rebar2**-based Erlang project.

## Prerequisites

- **Erlang/OTP**: 24+ 
- **rebar2**: installed and available in PATH
- Environment variables for LLM providers (optional):
  - `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `GROQ_API_KEY`

## Setup Steps

### 1. Add Agent Framework as a Dependency

In your project's `rebar.config`, add the framework to the deps list:

```erlang
{deps, [
  {agent_framework, ".*", {git, "https://github.com/your-org/agent_framework.git", {branch, "main"}}},
  {jsx, "3.1.0"}
]}.
```

### 2. Update Your rebar.config for Rebar2

Rebar2 uses a different configuration syntax. Ensure your `rebar.config` matches:

```erlang
{erl_opts, [debug_info, warnings_as_errors]}.

{deps, [
  {agent_framework, ".*", {git, "https://github.com/your-org/agent_framework.git", {branch, "main"}}},
  {jsx, "3.1.0"}
]}.

{cover_enabled, true}.
{eunit_opts, [verbose]}.
```

### 3. Copy Configuration Files

Copy the agent framework's configuration to your project:

```bash
cp -r agent_framework/config/* your_project/config/
```

Then reference it in your application's sys.config:

```erlang
%% config/sys.config
[
  {agent_framework, [
    {agents, [
      {mis_agent, #{...}},
      {hims_agent, #{...}},
      {lims_agent, #{...}}
    ]},
    {llm_routes, [
      {intent, claude},
      {planning, openai},
      {execution, gemini},
      {formatting, groq}
    ]}
  ]},
  {sasl, [
    {sasl_error_logger, {file, "log/sasl.log"}}
  ]}
].
```

### 4. Update Your Application Supervisor

Ensure your application includes the Agent Framework supervisor. Add to your app's supervisor tree:

```erlang
%% In your_app_sup.erl

init([]) ->
    SupFlags = {one_for_one, 1, 5},
    Children = [
      {agent_framework_sup, 
       {agent_framework_sup, start_link, []}, 
       permanent, 5000, supervisor, [agent_framework_sup]},
      %% Your other children...
    ],
    {ok, {SupFlags, Children}}.
```

### 5. Build and Compile

```bash
# Fetch dependencies
rebar get-deps

# Compile
rebar compile

# Run tests
rebar eunit

# Run common test suites
rebar ct
```

### 6. Start in Shell

```bash
# Start Erlang shell with your application and agent_framework loaded
erl -pa ebin -pa deps/*/ebin -config config/sys.config -s your_app

%% In the shell:
(your_app@host)1> agent_framework:agents().
[mis_agent, hims_agent, lims_agent]

(your_app@host)2> agent_framework:run(mis_agent, 
     <<"Get Q1 revenue report">>, 
     #{user_id => <<"user_1">>}).
```

## Key Differences from Rebar3

| Feature | Rebar2 | Rebar3 |
|---------|--------|--------|
| Dependency fetching | `rebar get-deps` | `rebar3 deps` |
| Compilation | `rebar compile` | `rebar3 compile` |
| Test execution | `rebar eunit` | `rebar3 eunit` |
| Output directory | `ebin/`, `deps/` | `_build/default/lib/`, `_build/test/` |
| Configuration | `rebar.config` (tuple-based) | `rebar.config` (map-based options) |
| Shell startup | Manual `erl` command | `rebar3 shell` |

## Troubleshooting

### Compilation Errors

If you see errors like `undefined callback module`, ensure:
1. All dependencies are fetched: `rebar get-deps`
2. Agent Framework supervisor is properly started
3. `sys.config` is loaded with `-config` flag

### Module Not Found

```bash
# Clear and rebuild
rebar clean
rebar get-deps
rebar compile
```

### LLM Provider Errors

Ensure environment variables are set before starting the shell:

```bash
export ANTHROPIC_API_KEY="sk-..."
export OPENAI_API_KEY="sk-..."
erl -pa ebin -pa deps/*/ebin -config config/sys.config -s your_app
```

## Migrating from Rebar2 to Rebar3 (Optional)

If you later decide to upgrade to rebar3, the `rebar.config` can largely remain the same, and you'll gain:
- Better dependency resolution
- Faster compilation
- Built-in release management
- Improved shell integration

Run `rebar3 upgrade` for automated migration.

## Support

For issues specific to the Agent Framework, see [README.md](../README.md) and [TOOL_DEFINITIONS_GUIDE.md](../TOOL_DEFINITIONS_GUIDE.md).

For rebar2 documentation, visit: https://github.com/rebar/rebar
