-module(emq_kafka_bridge).

-include_lib("emqttd/include/emqttd.hrl").

-include_lib("emq_kafka_bridge.hrl").

-include("ejabberd_logger.hrl").

-export([load/1, unload/0]).

%% Hooks functions

-export([on_client_subscribe/4, on_client_unsubscribe/4]).

-export([on_session_created/3, on_session_subscribed/4, on_session_unsubscribed/4, on_session_terminated/4]).

-export([on_message_publish/2]).

-export([on_client_connected/3, on_client_disconnected/3]).

-export([on_message_delivered/4, on_message_acked/4]).


%% Called when the plugin application start
load(Env) ->
    io:format(">>>>>>> LOAD KAFKA BRIDGE <<<<<<<<<~n"),
    ejabberd_loglevel:set(4),
    error_logger:add_report_handler(ejabberd_logger_h, "/tmp/logfile.log"),
    configure_ekaf(Env),
    emqttd:hook('client.connected', fun ?MODULE:on_client_connected/3, [Env]),
    emqttd:hook('client.disconnected', fun ?MODULE:on_client_disconnected/3, [Env]),
    emqttd:hook('client.subscribe', fun ?MODULE:on_client_subscribe/4, [Env]),
    emqttd:hook('client.unsubscribe', fun ?MODULE:on_client_unsubscribe/4, [Env]),
    emqttd:hook('session.created', fun ?MODULE:on_session_created/3, [Env]),
    emqttd:hook('session.subscribed', fun ?MODULE:on_session_subscribed/4, [Env]),
    emqttd:hook('session.unsubscribed', fun ?MODULE:on_session_unsubscribed/4, [Env]),
    emqttd:hook('session.terminated', fun ?MODULE:on_session_terminated/4, [Env]),
    emqttd:hook('message.publish', fun ?MODULE:on_message_publish/2, [Env]),
    emqttd:hook('message.delivered', fun ?MODULE:on_message_delivered/4, [Env]),
    emqttd:hook('message.acked', fun ?MODULE:on_message_acked/4, [Env]).


%% Called when the plugin application stop
unload() ->
    io:format(">>>>>>> UNLOAD KAFKA BRIDGE <<<<<<<<<~n"),
    emqttd:unhook('client.connected', fun ?MODULE:on_client_connected/3),
    emqttd:unhook('client.disconnected', fun ?MODULE:on_client_disconnected/3),
    emqttd:unhook('client.subscribe', fun ?MODULE:on_client_subscribe/4),
    emqttd:unhook('client.unsubscribe', fun ?MODULE:on_client_unsubscribe/4),
    emqttd:unhook('session.created', fun ?MODULE:on_session_created/3),
    emqttd:unhook('session.subscribed', fun ?MODULE:on_session_subscribed/4),
    emqttd:unhook('session.unsubscribed', fun ?MODULE:on_session_unsubscribed/4),
    emqttd:unhook('session.terminated', fun ?MODULE:on_session_terminated/4),
    emqttd:unhook('message.publish', fun ?MODULE:on_message_publish/2),
    emqttd:unhook('message.delivered', fun ?MODULE:on_message_delivered/4),
    emqttd:unhook('message.acked', fun ?MODULE:on_message_acked/4).

%% ===================================================================
%% CALLBACKS
%% ===================================================================
on_client_connected(ConnAck, Client = #mqtt_client{client_id = ClientId}, Env) ->
    io:format("client ~s connected, connack: ~w~n", [ClientId, ConnAck]),
    
    Json = mochijson2:encode([
        {type, <<"connected">>},
        {client_id, ClientId},
        {cluster_node, node()},
        {ts, emqttd_time:now_secs()}
    ]),
    
    produce_to_kafka(Env, Json),
    {ok, Client}.

on_client_disconnected(Reason, _Client = #mqtt_client{client_id = ClientId}, Env) ->
    io:format("client ~s disconnected, reason: ~w~n", [ClientId, Reason]),

    Json = mochijson2:encode([
        {type, <<"disconnected">>},
        {client_id, ClientId},
        {cluster_node, node()},
        {ts, emqttd_time:now_secs()}
    ]),
    
    produce_to_kafka(Env, Json),
    ok.

on_message_delivered(ClientId, Username, Message, Env) ->
    io:format("delivered to client(~s/~s): ~s~n", [Username, ClientId, emqttd_message:format(Message)]),

    Json = mochijson2:encode([
        {type, <<"delivered">>},
        {username, Username},
        {cluster_node, node()},
        {ts, emqttd_time:now_secs()}
    ]),
    
    produce_to_kafka(Env, Json),
    {ok, Message}.

on_message_acked(ClientId, Username, Message, Env) ->
    io:format("client(~s/~s) acked: ~s~n", [Username, ClientId, emqttd_message:format(Message)]),

    Json = mochijson2:encode([
        {type, <<"acked">>},
        {username, Username},
        {cluster_node, node()},
        {ts, emqttd_time:now_secs()}
    ]),
    
    produce_to_kafka(Env, Json),
    {ok, Message}.


on_client_subscribe(ClientId, Username, TopicTable, _Env) ->
    io:format("client(~s/~s) will subscribe: ~p~n", [Username, ClientId, TopicTable]),
    io:format("ClientId: ~p~n", [ClientId]),
    io:format("TopicTable: ~p~n", [TopicTable]),
    [{Topic, [{qos, _Qos}| _Opts]}] = TopicTable,
    io:format("Topic: ~p~n", [Topic]),
    ClientId1 = binary_to_list(ClientId),
    Topic1 = binary_to_list(Topic),

    ClientId2 = lists:sublist(ClientId1, string:length(ClientId1) - 13),
    io:format("ClientId2: ~p~n", [ClientId2]),
    Pos =  string:chr(Topic1, $/),
    io:format("Pos: ~p~n", [Pos]),

    Topic2 = lists:sublist(Topic1, Pos - 1),
    io:format("Topic2: ~p~n", [Topic2]),

    io:format("ClientId2: ~p~n", [ClientId2]),
    io:format("Topic2: ~p~n", [Topic2]),

    %Allowed = false,
    case ClientId2 =:= Topic2 of
        true ->
            io:format("!!!!!!!!Allowed: ~p~n", [Topic1]),
            {ok, TopicTable};
        _ ->
%%            throw ({forbidden, <<"not allowed">>})
            io:format("~~~~~~~~~~~NOT Allowed: ~p~n", [Topic1]),

            {stop, TopicTable}
    end.
    
on_client_unsubscribe(ClientId, Username, TopicTable, _Env) ->
    io:format("client(~s/~s) unsubscribe ~p~n", [ClientId, Username, TopicTable]),
    {ok, TopicTable}.

on_session_created(ClientId, Username, _Env) ->
    io:format("session(~s/~s) created.", [ClientId, Username]).

on_session_subscribed(ClientId, Username, {Topic, Opts}, _Env) ->
    io:format("session(~s/~s) subscribed: ~p~n", [Username, ClientId, {Topic, Opts}]),
    {ok, {Topic, Opts}}.

on_session_unsubscribed(ClientId, Username, {Topic, Opts}, _Env) ->
    io:format("session(~s/~s) unsubscribed: ~p~n", [Username, ClientId, {Topic, Opts}]),
    ok.

on_session_terminated(ClientId, Username, Reason, _Env) ->
    io:format("session(~s/~s) terminated: ~p.", [ClientId, Username, Reason]).

%% transform message and return
on_message_publish(Message = #mqtt_message{topic = <<"$SYS/", _/binary>>}, _Env) ->
    {ok, Message};

on_message_publish(Message, _Env) ->
    io:format("publish ~s~n", [emqttd_message:format(Message)]),
    {ok, Message}.

%% ===================================================================
%% HELPER FUNCTIONS
%% ===================================================================

% Produce to kafka, decide produce strategy here
produce_to_kafka(Env, Data) ->
    Topic = proplists:get_value(topic, Env, "emqtt"),
    Response = ekaf:produce_async(list_to_binary(Topic), list_to_binary(Data)),
    ?INFO_MSG("~p~n", [Data]),
    io:format("produce response ~p~n",[Response]).

% Configure ekaf from environmental variables
configure_ekaf(Env) ->
    application:load(ekaf),
    
    % Set topic
    Server = proplists:get_value(server, Env, "127.0.0.1"),
    Topic = proplists:get_value(topic, Env, "emqtt"),
    Port = proplists:get_value(port, Env, 9092),

    application:set_env(ekaf, ekaf_bootstrap_topics, list_to_binary(Topic)),
    application:set_env(ekaf, ekaf_bootstrap_broker, {Server, Port}),

    {ok, _} = application:ensure_all_started(ekaf),
    io:format("Init ekaf with ip ~s:~p, topic: ~s~n", [Server, Port, Topic]).

