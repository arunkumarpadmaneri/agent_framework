agent_framework/
│
├── config/
│   └── sys.config                      ← ALL config: agents, workflows, LLM per step
│
├── src/
│   │
│   ├── agent_framework.erl             ← PUBLIC API — your app calls this only
│   ├── agent_framework_app.erl         ← OTP application
│   ├── agent_framework_sup.erl         ← Top supervisor
│   │
│   ├── agents/                         ← One file per agent domain
│   │   ├── agent_registry.erl          ← Lookup agent by ID → definition
│   │   ├── agent_mis.erl               ← MIS agent definition
│   │   ├── agent_hims.erl              ← HIMS agent definition
│   │   └── agent_lims.erl              ← LIMS agent definition
│   │
│   ├── orchestrator/                   ← Core pipeline — domain-agnostic
│   │   ├── agent_orchestrator.erl      ← Runs workflow steps, routes per-step LLM
│   │   ├── agent_intent.erl            ← Step: classify query
│   │   ├── agent_planner.erl           ← Step: build tool execution plan
│   │   ├── agent_executor.erl          ← Step: run tools (single/seq/parallel)
│   │   └── agent_formatter.erl         ← Step: format results to narrative
│   │
│   ├── llm/                            ← LLM routing + adapters
│   │   ├── llm_router.erl              ← Routes to adapter based on step config
│   │   ├── llm_claude.erl              ← Anthropic Claude adapter
│   │   ├── llm_openai.erl              ← OpenAI adapter
│   │   └── llm_gemini.erl              ← Google Gemini adapter
│   │
│   ├── tools/                          ← Tools namespaced per domain
│   │   ├── tool_registry.erl           ← Register + execute tools by name
│   │   ├── mis/
│   │   │   ├── mis_tool_revenue.erl
│   │   │   ├── mis_tool_expenses.erl
│   │   │   └── mis_tool_report.erl
│   │   ├── hims/
│   │   │   ├── hims_tool_patient.erl
│   │   │   ├── hims_tool_billing.erl
│   │   │   └── hims_tool_appointment.erl
│   │   └── lims/
│   │       ├── lims_tool_sample.erl
│   │       ├── lims_tool_test_result.erl
│   │       └── lims_tool_lab_report.erl
│   │
│   └── lib/                            ← Shared utilities
│       ├── af_logger.erl               ← Structured logger
│       ├── af_error.erl                ← Error formatting
│       └── af_lib.erl                  ← req_id, helpers
│
└── rebar.config
