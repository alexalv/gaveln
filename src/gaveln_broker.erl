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
-behaviour(gen_server).

-export([init/1,
		 start_link/4,
		 handle_call/3,
		 handle_cast/2,
		 handle_info/2,
		 terminate/2,
		 code_change/3]).

start_link() ->
	gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

init(_) ->
	User  = gaveln_app:env_var(mq_user),
	Host  = gaveln_app:env_var(mq_host),
	Pass  = gaveln_app:env_var(mq_pass),
	Realm = gaveln_app:env_var(mq_realm),

	Exch = <<"Exchange">>
	%%RoutKey = <<"ui.to.mng">>

	RParams = #amqp_params{username = User,
     	  		           password = Pass,
                 	       virtual_host = Realm,
                      	   host = Host},

    RConn = amqp_connection:start_network(RParams),
    RChan = amqp_connection:open_channel(RConn),

    amqp_channel:call(
    	RChan, #'exchange_declare'{exchange = Exch,
    							   auto_delete = true}
    	),

    Queue = ClientKey = <<"ui.to.mng">>,
    OutKey = <<"mng.to.ui">>,

    amqp_channel:call(RChan,#'queue_declare'{queue = Queue,
    										 auto_delete =true}),

    amqp_channel:call(RChan, #'queue_bind'{queue = Queue,
    									   routing_key = ClientKey,
    									   exchange = Exch}),

    Tag = amqp_channel:subscribe(RChan, #'basic_consume'{queue = Queue}, self())




handle_call(Request, _From, State) ->
	{reply, Request, State}.

handle_cast(_Msg,State) ->
	{noreply,State}.

handle_info(#'basic.consume_ok'{consumer_tag = CTag},
            #state{conn = #conn{channel = _Channel,
                                exchange = _Exch,
                                route = _RoutKey}} = State) ->
	{noreply,State};

handle_info({#'basic.deliver'{consumer_tag = CTag,
                              delivery_tag = DeliveryTag,
                              exchange = Exch,
                              routing_key = RK},
             #amqp_msg{payload = Data} = Content},
            #state{conn = #conn{channel = RChan}, conf = Conf} = State) ->

	Payload = binary_to_term(Data),
	case Payload of
		{register,UniqKey} -> gaveln_app:start_clifs([{uniqkey, UniqKey},
			                                          {channel, RChan},
			                                          {exchange, Exch},
			                                          {conf, Conf}]);
		_ -> ok
	end,
	{noreply, State};

terminate(Reason, State) ->
    ok.

code_change(OldVsn, State, Extra) ->
    {ok, State}.