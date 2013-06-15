%%%---------------------------------------------------------------------
%%% @author Aleksandr Shevelev <alexalv91@yandex.ru>
%%% [http://ainecloud.tk/]
%%%
%%% @doc gaveln module of ainecloud. 
%%%      This module purpose is to tie together the other parts of
%%%      ainecloud. Basically it's a management server and a dispatcher
%%% @end
%%%---------------------------------------------------------------------
-module(gaveln_app).

-behaviour(application).
-include("amqp_client.hrl").



%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
	{ok, Connection} =
        amqp_connection:start(#amqp_params_network{host = "192.168.1.101"}),
    ets:new(connection_info, [named_table, protected, set, {keypos, 1}]),
    ets:insert(connection_info, {connection, Connection}),
    io:format("Starting!~n"),
    case gaveln_sup:start_link() of
    	{ok,Pid} ->
    		{ok,Pid};
    	Other ->
    		{error,Other}
    end.

stop(_State) ->
    ok.
