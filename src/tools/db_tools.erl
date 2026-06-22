%% =============================================================================
%% src/tools/db_tools.erl
%% Generic DB query tool using ODBC. Configure DSN, user, password and SQL query.
%% =============================================================================
-module(db_tools).
-export([db_query/1, schemas/0]).

schemas() ->
  [
    {db_query, #{
      function => db_query,
      description => <<"Run a SQL query against an ODBC data source">>,
      input => #{dsn => <<"required ODBC DSN string">>, user => <<"optional DB user">>, password => <<"optional DB password">>, query => <<"required SQL query">>},
      output => #{cols => <<"list">>, rows => <<"list">>}
    }}
  ].

db_query(Params) when is_map(Params) ->
  Dsn      = maps:get(<<"dsn">>, Params, <<"">>),
  User     = maps:get(<<"user">>, Params, <<"">>),
  Password = maps:get(<<"password">>, Params, <<"">>),
  Query    = maps:get(<<"query">>, Params, <<"">>),
  ConnStr  = build_conn_string(Dsn, User, Password),
  case odbc:connect(binary_to_list(ConnStr), [{auto_commit, true}]) of
    {ok, Conn} ->
      Result = run_query(Conn, Query),
      odbc:disconnect(Conn),
      Result;
    Error ->
      {error, Error}
  end.

build_conn_string(Dsn, <<"">>, <<"">>) -> Dsn;
build_conn_string(Dsn, User, Password) ->
  io_lib:format("DSN=~s;UID=~s;PWD=~s", [binary_to_list(Dsn), binary_to_list(User), binary_to_list(Password)]).

run_query(Conn, Query) when is_binary(Query) ->
  case odbc:param_query(Conn, binary_to_list(Query), []) of
    {selected, Cols, Rows} -> {ok, #{cols => Cols, rows => Rows}};
    {updated, Count}      -> {ok, #{updated => Count}};
    Error                 -> {error, Error}
  end.
