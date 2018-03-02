%% -------------------------------------------------------------------
%%
%% Copyright (c) 2017 Georges Younes.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(rcb_handler).
-author("Georges Younes <georges.r.younes@gmail.com>").

-behaviour(gen_server).

%% API
-export([start_link/0]).

%% handler callbacks
-export([rcbcast/2,
         rcbmemory/1,
         rcbfullmembership/1]).

%% delivery callbacks
-export([rcbdelivery/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-include("rcb.hrl").

-record(state, {actor :: node(),
                metrics :: atom(),
                recv_cc :: causal_context:causal_context(),
                full_membership :: [node()],
                to_be_delv_queue :: [{actor(), message(), timestamp()}],
                gvv :: vclock:vclock(),
                delivery_function :: fun()}).

-type state_t() :: #state{}.

%%%===================================================================
%%% handler callbacks
%%%===================================================================

%% callback for setting fullmemberhsip of the group.
-spec rcbfullmembership(term()) -> ok.
rcbfullmembership(Nodes) ->
    gen_server:call(?MODULE, {rcbfullmembership, Nodes}, infinity).

%% Broadcast message.
-spec rcbcast(message(), timestamp()) -> ok.
rcbcast(MessageBody, VV) ->
    gen_server:cast(?MODULE, {cbcast, MessageBody, VV}).

%% Receives a function to calculate rcb memory size
-spec rcbmemory(term()) -> non_neg_integer().
rcbmemory(CalcFunction) ->
    gen_server:call(?MODULE, {rcbmemory, CalcFunction}, infinity).

%% Set delivery Fun.
-spec rcbdelivery(term()) -> ok.
rcbdelivery(Fun) ->
    gen_server:call(?MODULE, {rcbdelivery, Fun}, infinity).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Same as start_link([]).
-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%% gen_server callbacks
%%%===================================================================

%% @private
-spec init(list()) -> {ok, state_t()}.
init([]) ->
    %% Seed the process at initialization.
    rand_compat:seed(erlang:phash2([node()]),
                     erlang:monotonic_time(),
                     erlang:unique_integer()),

    Actor = rcb_util:get_node(),

    %% Generate local dependency dots list.
    ToBeDelvQueue = [],

    %% Generate global version vector.
    GVV = vclock:fresh(),

    F = fun(Msg) ->
        lager:info("Message unhandled: ~p", [Msg]),
        ok
    end,

    {ok, #state{actor=Actor,
                recv_cc=causal_context:new(),
                metrics=rcb_config:get(lmetrics),
                to_be_delv_queue=ToBeDelvQueue,
                gvv=GVV,
                delivery_function=F,
                full_membership=[]}}.

%% @private
-spec handle_call(term(), {pid(), term()}, state_t()) ->
    {reply, term(), state_t()}.

handle_call({rcbdelivery, Fun}, _From, State) ->

    {reply, ok, State#state{delivery_function=Fun}};

%% @todo Update other actors when this is changed
handle_call({rcbfullmembership, Nodes}, _From, State) ->
    Nodes1 = case lists:last(Nodes) of
        {_, _} ->
            [Node || {_Name, Node} <- Nodes];
        _ ->
            Nodes
    end,
    {reply, ok, State#state{full_membership=Nodes1}};

handle_call({tcbmemory, CalcFunction}, _From, State) ->
    %% @todo 
    %% calculate memory size
    Result = CalcFunction([]),
    {reply, Result, State}.

%% @private
-spec handle_cast(term(), state_t()) -> {noreply, state_t()}.
handle_cast({cbcast, MessageBody, MessageVV},
            #state{actor=Actor,
                   metrics=Metrics,
                   recv_cc=RecvCC0,
                   gvv=GVV0,
                   full_membership=Members}=State) ->

    %% measure time start local
    T1 = erlang:system_time(microsecond),

    %% Only send to others without me to deliver
    %% as this message is already delievered
    ToMembers = rcb_util:without_me(Members),

    GVV = vclock:increment(Actor, GVV0),

    %% Generate message.
    %% @todo rmv Actor; could infer it from Dot
    Msg = {rcbcast, MessageVV, MessageBody, Actor},
    TaggedMsg = {?FIRST_RCBCAST_TAG, Msg},

    %% Add members to the queue of not ack messages
    Dot = {Actor, vclock:get_counter(Actor, MessageVV)},
    ?RESENDER:add_exactly_once_queue(Dot, {MessageVV, MessageBody, ToMembers}),

    RecvCC = causal_context:add_dot(Dot, RecvCC0),

    %% Transmit to membership.
    rcb_util:send(TaggedMsg, ToMembers, Metrics, ?HANDLER),

    %% measure time end local
    T2 = erlang:system_time(microsecond),

    %% record latency creating this message
    case Metrics of
        true ->
            lmetrics:record_latency(local, T2-T1);
        false ->
            ok
    end,

    {noreply, State#state{gvv=GVV, recv_cc=RecvCC}};

handle_cast({rcbcast, MessageVV, MessageBody, MessageActor},
            #state{actor=Actor,
                   metrics=Metrics,
                   recv_cc=RecvCC0,
                   gvv=GVV0,
                   delivery_function=DeliveryFun,
                   to_be_delv_queue=ToBeDelvQueue0}=State) ->
    %% measure time start remote
    T1 = erlang:system_time(microsecond),

    Dot = {MessageActor, vclock:get_counter(MessageActor, MessageVV)},
    {RecvCC, GVV, ToBeDelvQueue} = case causal_context:is_element(Dot, RecvCC0) of
        true ->
            %% Already seen, do nothing.
            lager:info("Ignoring duplicate message from cycle, but send ack."),

            %% In some cases (e.g. ring with 3 participants), more than one node would
            %% be sending the same message. If a message was seen from one it should
            %% be ignored but an ack should be sent to the sender or it will be
            %% resent by that sender forever

            {RecvCC0, GVV0, ToBeDelvQueue0};
        false ->
            %% Check if the message should be delivered and delivers it or not.
            {GVV1, ToBeDelvQueue1} = rcb_dlvr:causal_delivery({MessageActor, MessageBody, MessageVV},
                GVV0,
                [{MessageActor, MessageBody, MessageVV} | ToBeDelvQueue0],
                DeliveryFun),

            {causal_context:add_dot(Dot, RecvCC0), GVV1, ToBeDelvQueue1}
    end,
    %% measure time end remote
    T2 = erlang:system_time(microsecond),

    %% Generate message.
    MessageAck = {tcbcast_ack, Dot, Actor},
    TaggedMessageAck = {ack, MessageAck},

    %% Send ack back to message sender.
    rcb_util:send(TaggedMessageAck, MessageActor, Metrics, ?RESENDER),

    %% record latency creating this message
    case Metrics of
        true ->
            lmetrics:record_latency(remote, T2-T1);
        false ->
            ok
    end,
    {noreply, State#state{recv_cc=RecvCC, gvv=GVV, to_be_delv_queue=ToBeDelvQueue}};

handle_cast(Msg, State) ->
    lager:warning("Unhandled cast messages: ~p", [Msg]),
    {noreply, State}.

%% @private
-spec handle_info(term(), state_t()) -> {noreply, state_t()}.
handle_info(Msg, State) ->
    lager:warning("Unhandled info messages: ~p", [Msg]),
    {noreply, State}.

%% @private
-spec terminate(term(), state_t()) -> term().
terminate(_Reason, _State) ->
    ok.

%% @private
-spec code_change(term() | {down, term()}, state_t(), term()) -> {ok, state_t()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
