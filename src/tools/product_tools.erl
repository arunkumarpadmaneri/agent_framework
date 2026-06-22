%% =============================================================================
%% src/tools/product_tools.erl
%% E-Commerce product discovery tools.
%% =============================================================================
-module(product_tools).
-export([search_products/1, get_product_details/1, get_recommendations/1, schemas/0]).

schemas() ->
  [
    {search_products, #{
      function => search_products,
      description => <<"Search products by keywords, category, or price range">>,
      input => #{query => <<"required search query">>, category => <<"optional category">>, price_range => <<"optional price range">>},
      output => #{results => <<"list">>, total => <<"integer">>}
    }},
    {get_product_details, #{
      function => get_product_details,
      description => <<"Get detailed product information by product id">>,
      input => #{product_id => <<"required product id">>},
      output => #{product_id => <<"string">>, name => <<"string">>, price => <<"number">>, description => <<"string">>}
    }},
    {get_recommendations, #{
      function => get_recommendations,
      description => <<"Get recommended products based on user interests or category">>,
      input => #{category => <<"optional category">>, customer_id => <<"optional customer id">>},
      output => #{recommendations => <<"list">>}
    }}
  ].

search_products(Params) ->
  Query = maps:get(<<"query">>, Params, <<"all products">>),
  {ok, #{results => [
    #{product_id => <<"prod-101">>, name => <<"Smartphone XL">>, price => 499.99, description => <<"Large screen smartphone">>},
    #{product_id => <<"prod-102">>, name => <<"Noise-cancelling Headphones">>, price => 129.95, description => <<"Wireless over-ear headphones">>}
  ], total => 2, query => Query}}.

get_product_details(Params) ->
  ProductId = maps:get(<<"product_id">>, Params, <<"prod-101">>),
  {ok, #{product_id => ProductId, name => <<"Smartphone XL">>, price => 499.99,
        description => <<"A premium smartphone with long battery life and dual cameras">>}}.

get_recommendations(_Params) ->
  {ok, #{recommendations => [
    #{product_id => <<"prod-103">>, name => <<"Portable Charger">>, price => 29.95},
    #{product_id => <<"prod-104">>, name => <<"Wireless Earbuds">>, price => 59.95}
  ]}}.
