%% =============================================================================
%% test/domain_constants_example.erl
%%
%% REFERENCE EXAMPLE — copy this into your project as your own module.
%%
%% In your project:
%%   1. Copy this file to your_app/src/my_constants.erl
%%   2. Rename the module: -module(my_constants).
%%   3. Replace agents/0 with your own agents.
%%   4. Register it in your sys.config: {domain_module, my_constants}
%%
%% Single source of truth for ALL data that will move to DB.
%%
%% Contains two things:
%%   1. llm_profiles/0  — which models to use and how
%%   2. agents/0        — all agent definitions across all domains
%%
%% FUTURE DB MIGRATION
%% -------------------
%% Two DB tables map from this file:
%%
%%   TABLE: llm_profiles
%%     name         → profile atom (primary key)
%%     provider     → claude | openai | gemini | groq
%%     model        → model string
%%     max_tokens   → integer
%%     temperature  → float
%%     timeout_ms   → integer
%%     NOTE: api_key always comes from env vars, never stored in DB.
%%
%%   TABLE: agents
%%     id              → atom (primary key)
%%     domain          → atom
%%     description     → text
%%     tools           → JSON array
%%     intent_prompt   → text
%%     format_prompt   → text
%%     react_prompt    → text (nullable)
%%     workflow_type   → fast | standard | planning | react
%%     llm_profile     → FK → llm_profiles.name
%%
%% When ready to move to DB:
%%   llm_profiles() ->
%%     {ok, Rows} = my_db:query("SELECT * FROM llm_profiles"),
%%     [row_to_profile(R) || R <- Rows].
%%
%%   agents() ->
%%     {ok, Rows} = my_db:query("SELECT * FROM agents WHERE active = true"),
%%     [row_to_agent(R) || R <- Rows].
%% =============================================================================

-module(domain_constants_example).
-export([llm_profiles/0, agents/0, agent/1]).

%% ---------------------------------------------------------------------------
%% llm_profiles/0  —  all LLM profiles
%%                    Replace this with a DB query when ready.
%%
%% api_key is always {env, "VAR_NAME"} — secret, never stored in DB.
%% Everything else (model, temperature, tokens) is data → goes to DB.
%% ---------------------------------------------------------------------------
llm_profiles() ->
  [
    {claude_standard, [
      {provider,    claude},
      {api_key,     {env, "ANTHROPIC_API_KEY"}},
      {model,       <<"claude-sonnet-4-20250514">>},
      {max_tokens,  2048},
      {temperature, 0.0},
      {timeout_ms,  30000}
    ]},
    {claude_fast, [
      {provider,    claude},
      {api_key,     {env, "ANTHROPIC_API_KEY"}},
      {model,       <<"claude-haiku-4-5-20251001">>},
      {max_tokens,  1024},
      {temperature, 0.0},
      {timeout_ms,  15000}
    ]},
    {openai_standard, [
      {provider,    openai},
      {api_key,     {env, "OPENAI_API_KEY"}},
      {model,       <<"gpt-4o">>},
      {max_tokens,  2048},
      {temperature, 0.0},
      {timeout_ms,  30000}
    ]},
    {gemini_standard, [
      {provider,    gemini},
      {api_key,     {env, "GEMINI_API_KEY"}},
      {model,       <<"gemini-1.5-pro">>},
      {max_tokens,  2048},
      {temperature, 0.0},
      {timeout_ms,  30000}
    ]},
    {groq_standard, [
      {provider,    groq},
      {api_key,     {env, "GROQ_API_KEY"}},
      {model,       <<"mixtral-8x7b-32768">>},
      {max_tokens,  2048},
      {temperature, 0.0},
      {timeout_ms,  30000}
    ]}
  ].

%% ---------------------------------------------------------------------------
%% agents/0  —  full list of all agents across all domains
%%              Replace this with a DB query when ready.
%% ---------------------------------------------------------------------------
agents() ->
  [
    %% ── Hospital domain ──────────────────────────────────────────────────────
    mis_agent(),
    hims_agent(),
    lims_agent(),

    %% ── E-Commerce domain ────────────────────────────────────────────────────
    order_agent(),
    product_agent(),
    payment_agent(),

    %% ── Billing API domain ───────────────────────────────────────────────────
    billing_agent()
  ].

%% Lookup single agent by id.
agent(Id) ->
  case lists:keyfind(Id, 1, [{maps:get(id, A), A} || A <- agents()]) of
    {_, Def} -> {ok, Def};
    false    -> {error, agent_not_found}
  end.

%% =============================================================================
%% HOSPITAL DOMAIN
%% =============================================================================

mis_agent() -> #{
  id          => mis_agent,
  domain      => hospital,
  description => <<"Hospital MIS — financial reporting">>,
  tools       => [get_revenue, get_expenses, get_mis_report],
  intent_prompt =>
    <<"You are a query classifier for Hospital Financial Management.\n"
      "Classify and return ONLY valid JSON:\n"
      "{\"intent\":\"get_revenue|get_expenses|get_report|unknown\",\n"
      "\"entities\":{\"period\":null,\"department\":null},\n"
      "\"confidence\":0.0}\n"
      "Set intent='unknown' if confidence < 0.6. Return ONLY JSON.">>,
  format_prompt =>
    <<"You are a Hospital Financial Reporting assistant.\n"
      "Format the raw financial data into a clear, concise response.\n"
      "Include key numbers with ₹ symbol, trends, and observations.\n"
      "Plain text only — no JSON, no markdown headers.">>,
  workflow => workflow_constants:fast_workflow()
}.

hims_agent() -> #{
  id          => hims_agent,
  domain      => hospital,
  description => <<"Hospital HIMS — patient and clinical info">>,
  tools       => [get_patient, get_billing, get_appointment],
  intent_prompt =>
    <<"You are a query classifier for Hospital Patient Management.\n"
      "Classify and return ONLY valid JSON:\n"
      "{\"intent\":\"get_patient|get_billing|get_appointment|unknown\",\n"
      "\"entities\":{\"patient_id\":null,\"department\":null,\"date\":null},\n"
      "\"confidence\":0.0}\n"
      "Set intent='unknown' if confidence < 0.6. Return ONLY JSON.">>,
  format_prompt =>
    <<"You are a Hospital Information System assistant.\n"
      "Format patient, billing, or appointment data into a clear response.\n"
      "Be concise and clinically appropriate. Plain text only.">>,
  workflow => workflow_constants:fast_workflow()
}.

lims_agent() -> #{
  id          => lims_agent,
  domain      => hospital,
  description => <<"Hospital LIMS — laboratory information">>,
  tools       => [get_sample, get_test_result, get_lab_report],
  intent_prompt =>
    <<"You are a query classifier for Hospital Laboratory Management.\n"
      "Classify and return ONLY valid JSON:\n"
      "{\"intent\":\"get_sample|get_result|get_report|unknown\",\n"
      "\"entities\":{\"sample_id\":null,\"test_type\":null,\"patient_id\":null},\n"
      "\"confidence\":0.0}\n"
      "Set intent='unknown' if confidence < 0.6. Return ONLY JSON.">>,
  format_prompt =>
    <<"You are a Laboratory Information System assistant.\n"
      "Format lab results and sample data into a clear, accurate response.\n"
      "Include reference ranges where relevant. Plain text only.">>,
  workflow => workflow_constants:fast_workflow()
}.

%% =============================================================================
%% E-COMMERCE DOMAIN
%% =============================================================================

order_agent() -> #{
  id          => order_agent,
  domain      => ecommerce,
  description => <<"E-Commerce — order management">>,
  tools       => [list_orders, get_order_status, update_order],
  intent_prompt =>
    <<"You are a query classifier for E-Commerce Order Management.\n"
      "Classify and return ONLY valid JSON:\n"
      "{\"intent\":\"list|check_status|update|unknown\",\n"
      "\"entities\":{\"order_id\":null,\"customer_id\":null},\n"
      "\"confidence\":0.0}\n"
      "Set intent='unknown' if confidence < 0.6. Return ONLY JSON.">>,
  format_prompt =>
    <<"You are an E-Commerce Order Assistant.\n"
      "Format order information into a clear, concise response.\n"
      "Include order ID, status, items, and total price.\n"
      "Be friendly and professional. Plain text only.">>,
  workflow => workflow_constants:fast_workflow()
}.

product_agent() -> #{
  id          => product_agent,
  domain      => ecommerce,
  description => <<"E-Commerce — product discovery and recommendations">>,
  tools       => [search_products, get_product_details, get_recommendations],
  intent_prompt =>
    <<"You are a query classifier for E-Commerce Product Discovery.\n"
      "Classify and return ONLY valid JSON:\n"
      "{\"intent\":\"search|details|recommend|unknown\",\n"
      "\"entities\":{\"query\":null,\"category\":null,\"price_range\":null},\n"
      "\"confidence\":0.0}\n"
      "Set intent='unknown' if confidence < 0.6. Return ONLY JSON.">>,
  format_prompt =>
    <<"You are an E-Commerce Product Specialist.\n"
      "Format product information into an engaging response.\n"
      "Include product name, price, features, and customer reviews.\n"
      "Be enthusiastic and helpful. Plain text only.">>,
  workflow => workflow_constants:fast_workflow()
}.

payment_agent() -> #{
  id          => payment_agent,
  domain      => ecommerce,
  description => <<"E-Commerce — payment processing">>,
  tools       => [process_payment, check_payment_status, refund_order],
  intent_prompt =>
    <<"You are a query classifier for E-Commerce Payment Processing.\n"
      "Classify and return ONLY valid JSON:\n"
      "{\"intent\":\"process|check|refund|unknown\",\n"
      "\"entities\":{\"amount\":null,\"order_id\":null},\n"
      "\"confidence\":0.0}\n"
      "Set intent='unknown' if confidence < 0.6. Return ONLY JSON.">>,
  format_prompt =>
    <<"You are an E-Commerce Payment Assistant.\n"
      "Format payment information securely and clearly.\n"
      "Include transaction ID, status, and any warnings.\n"
      "Be clear and professional. Plain text only.">>,
  workflow => workflow_constants:fast_workflow()
}.

%% =============================================================================
%% BILLING API DOMAIN
%% =============================================================================

billing_agent() -> #{
  id          => billing_agent,
  domain      => billing,
  description => <<"Billing API — fetch bill lists from endpoint">>,
  tools       => [get_bill_list],
  intent_prompt =>
    <<"You are a billing query classifier. Return only valid JSON:\n"
      "{\"intent\":\"get_bill_list|unknown\",\n"
      "\"entities\":{\"entitykey\":null,\"date\":null},\n"
      "\"confidence\":0.0}\n"
      "Choose 'get_bill_list' for bill list requests, otherwise 'unknown'.">>,
  format_prompt =>
    <<"You are a billing assistant.\n"
      "Format the bill list response clearly and concisely.\n"
      "Plain text only.">>,
  workflow => workflow_constants:fast_workflow()
}.
