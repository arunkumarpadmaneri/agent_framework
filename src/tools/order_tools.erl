%% =============================================================================
%% src/tools/order_tools.erl
%% E-Commerce order management tool adapters.
%% =============================================================================
-module(order_tools).
-export([list_orders/1, get_order_status/1, update_order/1, schemas/0]).

schemas() ->
  [
    {list_orders, #{
      function => list_orders,
      description => <<"List recent orders for a customer or all orders">>,
      input => #{customer_id => <<"optional customer id">>, status => <<"optional order status filter">>},
      output => #{orders => <<"list">>, count => <<"integer">>}
    }},
    {get_order_status, #{
      function => get_order_status,
      description => <<"Get the current status and details for an order">>,
      input => #{order_id => <<"required order id">>},
      output => #{order_id => <<"string">>, status => <<"string">>, total => <<"number">>, items => <<"list">>}
    }},
    {update_order, #{
      function => update_order,
      description => <<"Update order state or shipping details">>,
      input => #{order_id => <<"required order id">>, status => <<"optional new status">>, shipping_info => <<"optional map">>},
      output => #{order_id => <<"string">>, status => <<"string">>, message => <<"string">>}
    }}
  ].

list_orders(Params) ->
  CustomerId = maps:get(<<"customer_id">>, Params, <<"all_customers">>),
  Status = maps:get(<<"status">>, Params, <<"all">>),
  {ok, #{customer_id => CustomerId,
        status => Status,
        count => 2,
        orders => [
          #{order_id => <<"order-1001">>, status => <<"shipped">>, total => 259.95, items => [#{sku => <<"sku-101">>, qty => 1}]},
          #{order_id => <<"order-1002">>, status => <<"processing">>, total => 79.90, items => [#{sku => <<"sku-202">>, qty => 2}]}
        ]}}.

get_order_status(Params) ->
  OrderId = maps:get(<<"order_id">>, Params, <<"unknown">>),
  {ok, #{order_id => OrderId,
        status => <<"shipped">>,
        total => 259.95,
        items => [
          #{sku => <<"sku-101">>, name => <<"Wireless Mouse">>, qty => 1, price => 29.95},
          #{sku => <<"sku-102">>, name => <<"Mechanical Keyboard">>, qty => 1, price => 230.00}
        ]}}.

update_order(Params) ->
  OrderId = maps:get(<<"order_id">>, Params, <<"unknown">>),
  NewStatus = maps:get(<<"status">>, Params, <<"updated">>),
  {ok, #{order_id => OrderId, status => NewStatus, message => <<"Order updated successfully">>}}.
