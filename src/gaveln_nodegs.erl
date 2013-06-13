-module(gaveln_nodegs).

-include("amqp_client.hrl").

-behaviour(gen_server).

-record(state, {channel,
                reply_queue,
                exchange,
                routing_key,
                continuations = dict:new(),
                correlation_id = 0}).


-export([start/1, stop/1]).
-export([call/2]).
-export([init/1, 
     terminate/2, 
     code_change/3, 
     handle_call/3,
         handle_cast/2, 
         handle_info/2]).

start(Queue) ->
  [{_, Connection}] = ets:lookup(connection_info, connection),
    {ok, Pid} = gen_server:start(?MODULE, [Connection, Queue], []),
    {ok, Pid}.

stop(Pid) ->
    gen_server:call(Pid, stop, infinity).


call(RpcClient, Payload) ->
    gen_server:call(RpcClient, {call, Payload}, infinity).


setup_reply_queue(State = #state{channel = Channel}) ->
    #'queue.declare_ok'{queue = Q} =
        amqp_channel:call(Channel, #'queue.declare'{}),
    State#state{reply_queue = Q}.

setup_consumer(#state{channel = Channel, reply_queue = Q}) ->
    amqp_channel:call(Channel, #'basic.consume'{queue = Q}).

publish(Payload, From,
       State = #state{channel = Channel,
                       reply_queue = Q,
                       exchange = X,
                       routing_key = RoutingKey,
                       correlation_id = CorrelationId,
                       continuations = Continuations}) ->

    Props = #'P_basic'{correlation_id = <<CorrelationId:64>>,
                       content_type = <<"application/octet-stream">>,
                       reply_to = Q},
    Publish = #'basic.publish'{exchange = X,
                               routing_key = RoutingKey,
                               mandatory = true},
    amqp_channel:call(Channel, Publish, #amqp_msg{props = Props,
                                                  payload = Payload}),
    State#state{correlation_id = CorrelationId + 1,
                continuations = dict:store(CorrelationId, From, Continuations)}.

init([Connection, RoutingKey]) ->
    {ok, Channel} = amqp_connection:open_channel(
                        Connection, {amqp_direct_consumer, [self()]}),
    InitialState = #state{channel     = Channel,
                          exchange    = <<>>,
                          routing_key = RoutingKey},
    State = setup_reply_queue(InitialState),
    setup_consumer(State),
    io:format(" [***] Nodegs specific started!~n"),
    {ok, State}.

terminate(_Reason, #state{channel = Channel}) ->
    amqp_channel:close(Channel),
    ok.

%% @private
handle_call(stop, _From, State) ->
    {stop, normal, ok, State};

%% @private
handle_call({msg, Payload}, From, State) ->
  io:format(" [***] Node got called ~p~n",[Payload]),
    NewState = publish(Payload, From, State),
    {noreply, NewState};

handle_call({call, Payload}, From, State) ->
  io:format(" [***] Node got called ~p~n",[Payload]),
    NewState = publish(Payload, From, State),
    {noreply, NewState}.

%% @private
handle_cast({msg, Payload}, State) ->
  io:format(" [***] Node got called ~p~n",[Payload]),
    NewState = publish(Payload, self(), State),
    {noreply, NewState};

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info({#'basic.consume'{}, _Pid}, State) ->
    {noreply, State};

%% @private
handle_info(#'basic.consume_ok'{}, State) ->
    {noreply, State};

%% @private
handle_info(#'basic.cancel'{}, State) ->
    io:format(" [***] Got canceled"),
    {noreply, State};

%% @private
handle_info(#'basic.cancel_ok'{}, State) ->
    io:format(" [***] Got canceled"),
    {stop, normal, State};

%% @private
handle_info({#'basic.deliver'{delivery_tag = DeliveryTag},
             #amqp_msg{props = #'P_basic'{correlation_id = <<Id:64>>},
                       payload = Payload}},
            State = #state{continuations = Conts, channel = Channel}) ->
    From = dict:fetch(Id, Conts),
    gen_server:reply(From, Payload),
    amqp_channel:call(Channel, #'basic.ack'{delivery_tag = DeliveryTag}),
    send_to_ui(Payload),
    {noreply, State#state{continuations = dict:erase(Id, Conts) }}.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

send_to_ui(Payload) ->
    [{_, Connection}] = ets:lookup(connection_info, connection),
    {ok, Channel} = amqp_connection:open_channel(Connection),
    amqp_channel:call(Channel, #'queue.declare'{queue = <<"mng.to.ui2">>}),
    amqp_channel:cast(Channel,
                      #'basic.publish'{
                        routing_key = <<"mng.to.ui2">>},
                      #amqp_msg{payload = Payload}),
    io:format(" [***] Sent ~p~n",[Payload]),
    ok = amqp_channel:close(Channel).