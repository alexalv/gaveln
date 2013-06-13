%%%---------------------------------------------------------------------
%%% @author Aleksandr Shevelev <alexalv91@yandex.ru>
%%% [http://ainecloud.tk/]
%%%
%%% @doc gaveln module of ainecloud. 
%%%      This module purpose is to tie together the other parts of
%%%      ainecloud. Basically it's a management server and a dispatcher
%%% @end
%%%---------------------------------------------------------------------
-module(gaveln_sup).

-behaviour(supervisor).
-include("amqp_client.hrl").


%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).
-define(SERVER, ?MODULE).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
	Server = {gaveln_gs, {gaveln_gs, start_link, []},
			  permanent,2000,worker,[gaveln_gs]},
	CommonNS = {gaveln_common_node_gs, {gaveln_common_node_gs, start, [fun(_) -> <<"YAPAPA">> end]},
			  permanent,2000,worker,[gaveln_common_node_gs]},
	Children = [Server,CommonNS],
	RestartStrategy = {one_for_one, 5, 10},
    {ok, { RestartStrategy, Children } }.