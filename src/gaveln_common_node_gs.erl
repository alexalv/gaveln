%%%---------------------------------------------------------------------
%%% @author Aleksandr Shevelev <alexalv91@yandex.ru>
%%% [http://ainecloud.tk/]
%%%
%%% @doc gaveln module of ainecloud. 
%%%      This module purpose is to tie together the other parts of
%%%      ainecloud. Basically it's a management server and a dispatcher
%%% @end
%%%---------------------------------------------------------------------
-module(gaveln_common_node_gs).
-include("amqp_client.hrl").
-behaviour(gen_server).

-export([init/1, terminate/2, code_change/3, handle_call/3,
         handle_cast/2, handle_info/2]).
-export([start/1,stop/1]).
-record(state,{channel,handler}).

start(Fun) ->
    {ok,Pid} = gen_server:start(?MODULE, [Fun], []),
    {ok,Pid}.

stop(Pid) ->
    gen_server:call(Pid, stop, infinity).


init([Fun])->
    [{_, Connection}] = ets:lookup(connection_info, connection),
    {ok, Channel} = amqp_connection:open_channel(
                        Connection, {amqp_direct_consumer, [self()]}),
    amqp_channel:call(Channel, #'queue.declare'{queue = <<"common.node.to.mng">>}),
    amqp_channel:call(Channel, #'basic.consume'{queue = <<"common.node.to.mng">>}),
    io:format(" [xx] Common node gs started, woohoo!~n"),
    {ok, #state{channel = Channel, handler = Fun} }.

handle_info(shutdown, State) ->
    {stop, normal, State};


handle_info({#'basic.consume'{}, _}, State) ->
    {noreply, State};

handle_info(#'basic.consume_ok'{}, State) ->
    {noreply, State};

handle_info(#'basic.cancel'{}, State) ->
    {noreply, State};

handle_info(#'basic.cancel_ok'{}, State) ->
    {stop, normal, State};

handle_info({#'basic.deliver'{delivery_tag = DeliveryTag},
             #amqp_msg{payload = Payload}},
             State = #state{handler = Fun, channel = Channel}) ->
    {struct,JsonData} = mochijson2:decode(Payload),
    io:format(" [xx] BTW jsondata ~w~n",[JsonData]),
    case proplists:get_value(<<"action">>, JsonData) of
        <<"NEWSERVER">> ->
            {struct, Params} = proplists:get_value(<<"params">>,JsonData),
            Ip = proplists:get_value(<<"ip">>,Params),
            Uuid = proplists:get_value(<<"uuid">>,Params),
            gen_server:call(gaveln_gs,{newserver, [Ip,Uuid]});
        Other ->
            io:format(" [xx] Wrong message!")
    end,
    amqp_channel:call(Channel, #'basic.ack'{delivery_tag = DeliveryTag}),
    {noreply, State};

handle_info({'DOWN', _MRef, process, _Pid, _Info}, State) ->
    {noreply, State}.

handle_call(stop, _From, State) ->
    {stop, normal, ok, State}.

handle_cast(_Message, State) ->
    {noreply, State}.

terminate(_Reason, #state{channel = Channel}) ->
    amqp_channel:close(Channel),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.