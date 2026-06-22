**Agent Framework**

- **Description**: Multi-agent orchestration framework that coordinates intent classification, planning, tool execution and formatting using configurable agents and LLM adapters.
- **Status**: Development — bootable, services start in `rebar3 shell`.

**Prerequisites**:
- **Erlang/OTP**: 24+ (build tested on OTP 27)
- **rebar3**: latest
- Environment variables for LLM providers (if you plan to call real LLMs):
  - `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`

**Quick Start**

- From the project root:

```bash
cd /home/arunarch/Downloads/agent_framework
# fetch dependencies
rebar3 deps
# compile
rebar3 compile
# open an interactive shell (boots the app)
rebar3 shell
```

- In the Erlang shell (verification commands):

```erlang
%% Check supervisor
whereis(agent_framework_sup).
%% Check services
whereis(tool_registry).
whereis(llm_router).
whereis(session_mgr).
whereis(rate_limiter).
whereis(agent_registry).
whereis(agent_orchestrator).

%% Check public API
agent_framework:agents().
agent_framework:tools(mis_agent).

%% API-backed billing agent example
%% Ensure the sample domain config is loaded by using config/sys.config and the config/domains folder.
%% Then call the billing agent with a natural-language query.
agent_framework:run(billing_agent,
  <<"Fetch the bill list for entitykey 123 on 20240622">>,
  #{role => guest, user_id => <<"web_user">>}).

%% Utility checks
af_lib:req_id().
af_error:fmt(rate_limited).
rate_limiter:check(doctor).
session_mgr:enrich(#{user_id => <<"user_1">>}).
```

**Running tests**

```bash
rebar3 eunit
rebar3 ct
```

**Development notes**
- I added `src/agent_framework.app.src` (application descriptor) to ensure OTP can boot the app.
- Several multi-module source files were split into single-module files (e.g., `llm_router` adapters, `af_*` helpers).
- `src/orchestrator/agent_planner.erl` was hardened to avoid unsafe `binary_to_atom/1` usage.

**Documentation**
- Design and requirements docs are available in `docs/requirements.md` and `docs/architecture.md`.
- Agent and tool schema guidance is available in `docs/schemas.md`.

**Contributing**
- Fork the repo, create a feature branch, implement changes and open a pull request. Keep commits focused and include tests where possible.

**License**
- Add your chosen open-source license here (e.g., MIT, Apache-2.0) and a `LICENSE` file.
