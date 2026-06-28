%% =============================================================================
%% config/domains/ecommerce_constants.erl
%%
%% Domain-specific constants for E-Commerce System
%% Converted from ecommerce.config to Erlang constant module.
%% =============================================================================

-module(ecommerce_constants).

%% Public API
-export([
  agents/0,
  order_agent/0,
  product_agent/0,
  payment_agent/0,
  agent/1
]).

%% =============================================================================
%% ORDER AGENT (Order management)
%% =============================================================================

order_agent() ->
  #{
    id          => order_agent,
    domain      => ecommerce,
    description => "E-Commerce Order Management agent",
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

    workflow    => workflow_constants:fast_workflow()
  }.

%% =============================================================================
%% PRODUCT AGENT (Product search & recommendations)
%% =============================================================================

product_agent() ->
  #{
    id          => product_agent,
    domain      => ecommerce,
    description => "E-Commerce Product Discovery agent",
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

    workflow    => workflow_constants:fast_workflow()
  }.

%% =============================================================================
%% PAYMENT AGENT (Payment processing)
%% =============================================================================

payment_agent() ->
  #{
    id          => payment_agent,
    domain      => ecommerce,
    description => "E-Commerce Payment Processing agent",
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

    workflow    => [
      #{step => intent,   llm_profile => claude_fast},
      #{step => plan,     llm_profile => claude_fast},
      #{step => execute,  llm_profile => none},
      #{step => format,   llm_profile => claude_standard}
    ]
  }.

%% Returns all e-commerce domain agents as a list
agents() ->
  [
    order_agent(),
    product_agent(),
    payment_agent()
  ].

%% Lookup agent by ID
agent(AgentId) ->
  case AgentId of
    order_agent   -> order_agent();
    product_agent -> product_agent();
    payment_agent -> payment_agent();
    _             -> {error, agent_not_found}
  end.
