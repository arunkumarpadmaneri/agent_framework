%% =============================================================================
%% src/tools/payment_tools.erl
%% E-Commerce payment processing tools.
%% =============================================================================
-module(payment_tools).
-export([process_payment/1, check_payment_status/1, refund_order/1, schemas/0]).

schemas() ->
  [
    {process_payment, #{
      function => process_payment,
      description => <<"Process a payment for an order">>,
      input => #{order_id => <<"required order id">>, amount => <<"required amount">>, method => <<"required payment method">>},
      output => #{transaction_id => <<"string">>, status => <<"string">>, amount => <<"number">>}
    }},
    {check_payment_status, #{
      function => check_payment_status,
      description => <<"Check the status of a payment transaction">>,
      input => #{transaction_id => <<"required transaction id">>},
      output => #{transaction_id => <<"string">>, status => <<"string">>, settled => <<"boolean">>}
    }},
    {refund_order, #{
      function => refund_order,
      description => <<"Refund an order payment">>,
      input => #{order_id => <<"required order id">>, amount => <<"required refund amount">>},
      output => #{order_id => <<"string">>, refund_id => <<"string">>, status => <<"string">>}
    }}
  ].

process_payment(Params) ->
  OrderId = maps:get(<<"order_id">>, Params, <<"unknown">>),
  Amount = maps:get(<<"amount">>, Params, 0.0),
  {ok, #{transaction_id => <<"txn-789">>, order_id => OrderId, status => <<"completed">>, amount => Amount}}.

check_payment_status(Params) ->
  TransactionId = maps:get(<<"transaction_id">>, Params, <<"unknown">>),
  {ok, #{transaction_id => TransactionId, status => <<"settled">>, settled => true}}.

refund_order(Params) ->
  OrderId = maps:get(<<"order_id">>, Params, <<"unknown">>),
  Amount = maps:get(<<"amount">>, Params, 0.0),
  {ok, #{order_id => OrderId, refund_id => <<"refund-456">>, status => <<"refunded">>, amount => Amount}}.
