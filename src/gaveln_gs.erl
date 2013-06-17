%%%---------------------------------------------------------------------
%%% @author Aleksandr Shevelev <alexalv91@yandex.ru>
%%% [http://ainecloud.tk/]
%%%
%%% @doc gaveln module of ainecloud. 
%%%      This module purpose is to tie together the other parts of
%%%      ainecloud. Basically it's a management server and a dispatcher
%%% @end
%%%---------------------------------------------------------------------
-module(gaveln_gs).

-define(NODEGSSPEC(Name,MFA),
          {Name,
          {gaveln_nodegs, start, [MFA]},
          permanent,
          10000,
          worker,
          [gaveln_nodegs]}).

-behaviour(gen_server).
-include("amqp_client.hrl").

-record(nodeproc,{pid,ip,routing_key,name}).

-export([init/1,
         start_link/0,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init(_) ->
    User  = "guest",
    Host  = "192.168.1.101",
    Pass  = "guest",
    Exch = <<"Exchange">>,
    ets:new(nodeprocs,[named_table,{keypos,#nodeproc.routing_key}]),

    [{_, Connection}] = ets:lookup(connection_info, connection),
    {ok, Channel} = amqp_connection:open_channel(Connection),

    #'queue.declare_ok'{queue=Queue} = amqp_channel:call(Channel, #'queue.declare'{queue = <<"ui.to.mng">>}),
    io:format(" [*] Waiting for messages. To exit press CTRL+C~n"),
    amqp_channel:subscribe(Channel, #'basic.consume'{queue = <<"ui.to.mng">>,
                                                     no_ack = true},
                           self()),
    {ok,go}.

handle_call({newserver, [Ip,Uuid]}, _From, State) ->
  Params = iolist_to_binary(<< <<"mng.to.node.">>/binary, Uuid/binary >>),
  {ok,Pid} = supervisor:start_child(gaveln_sup, ?NODEGSSPEC(binary_to_atom(Params,utf8),Params)),
  Msg = iolist_to_binary(mochijson2:encode({struct,[{<<"action">>, <<"NEWSERVER">>},{<<"params">>,[{<<"ip">>,Ip},{<<"uuid">>,Uuid}]}]})),
  send_to_ui(Msg),
  ets:insert(nodeprocs,#nodeproc{pid = Pid,ip = Ip, routing_key = Params,name = binary_to_atom(Params,utf8)}),
  {reply, Uuid, State};

handle_call(Request, _From, State) ->
  {reply, Request, State}.

handle_cast({got_error,{Pid,Payload}},State) ->
  % [TODO] handle error
  % will need an external function for error disambiguation
  {noreply,State};

handle_cast(_Msg,State) ->
  {noreply,State}.

handle_info(#'basic.consume_ok'{consumer_tag = CTag},State) ->
  io:format(" [x] Basic consumption started!~n"),
  {noreply, State};

handle_info({#'basic.deliver'{consumer_tag = CTag,
                              delivery_tag = DeliveryTag,
                              exchange = Exch,
                              routing_key = RK},
                  #amqp_msg{payload = Payload}}, State) ->
  io:format(" [x] Received ~p~n  From ~p~n", [Payload,RK]),
  {struct,JsonData} = mochijson2:decode(Payload),
  
  case proplists:get_value(<<"action">>, JsonData) of
    <<"REINDEX">> ->
          message_to_node({Payload});
    <<"START">> ->
          message_to_node({Payload});
    Other ->
          {struct,DataParams} = proplists:get_value(<<"params">>, JsonData),
          Uuid = proplists:get_value(<<"server_uuid">>, DataParams),
          RoutKey = iolist_to_binary(<< <<"mng.to.node.">>/binary, Uuid/binary >>),
          message_to_node({Payload,RoutKey})
  end,
  {noreply, State};

handle_info(Info, State) ->
    io:format("Handle Info noreply: ~p, ~p~n", [Info, State]),
    {noreply, State}.


terminate(Reason, State) ->
    ok.

code_change(OldVsn, State, Extra) ->
    {ok, State}.

send_to_ui(Payload) ->
    [{_, Connection}] = ets:lookup(connection_info, connection),
    {ok, Channel} = amqp_connection:open_channel(Connection),

    amqp_channel:call(Channel, #'queue.declare'{queue = <<"mng.to.ui2">>}),
    amqp_channel:cast(Channel,
                      #'basic.publish'{
                        routing_key = <<"mng.to.ui2">>},
                      #amqp_msg{payload = Payload}),
    io:format(" [*] Sent ~p~n",[Payload]),
    ok = amqp_channel:close(Channel),
    ok = amqp_connection:close(Connection).

message_to_node({Payload}) ->
  [#nodeproc{pid = Pid}] = ets:lookup(nodeprocs, ets:first(nodeprocs)),
  io:format(" [x] Calling ~p~n",[Pid]),
  gen_server:call(Pid,{msg,Payload},infinity);

message_to_node({Payload,RoutKey}) ->
  [#nodeproc{pid = Pid}] = ets:lookup(nodeprocs, RoutKey),
  io:format(" [x] FURIOUSLY Calling ~p~n",[Pid]),
  gen_server:call(Pid,{msg,Payload},infinity).
