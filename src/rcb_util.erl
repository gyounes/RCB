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

-module(rcb_util).
-author("Georges Younes <georges.r.younes@gmail.com>").

%% other
-export([send/4,
         get_timestamp/0,
         get_node/0,
         without_me/1]).

-include("rcb.hrl").

%%%===================================================================
%%% util common functions
%%%===================================================================

%% @private
send({Tag, Msg}, Peers, Metrics, Module) when is_list(Peers) ->
    MySelf = node(),
    lists:foreach(
        fun(Peer) ->
            case Peer of
                MySelf ->
                    gen_server:cast(Module, Msg);
                _ ->
                    ?PEER_SERVICE_MANAGER:cast_message(Peer, Module, Msg)
            end
        end,
    Peers),
    case Metrics of
        true ->
            metrics({Tag, Msg, length(Peers)});
        false ->
            ok
    end;
send(M, Peer, Metrics, Module) ->
    send(M, [Peer], Metrics, Module).

%% @private get current time in milliseconds
-spec get_timestamp() -> integer().
get_timestamp() ->
  {Mega, Sec, Micro} = os:timestamp(),
  (Mega*1000000 + Sec)*1000 + round(Micro/1000).

%% @private
get_node() ->
    node().

%% @private
get_byte_size(X) ->
    erlang:byte_size(erlang:term_to_binary(X)).

%% @private
without_me(Members) ->
    Members -- [node()].

%% @private
metrics({?FIRST_RCBCAST_TAG, {rcbcast, _MessageBody, MessageTimestamp, _Sender}, N}) ->
    M= {rcbcast, get_byte_size(MessageTimestamp)},
    record_message(M, N);
% metrics({?RESEND_RCBCAST_TAG, {rcbcast, _MessageBody, MessageTimestamp, _Sender}}) ->
    % M= {rcbcast_resend, get_byte_size(MessageTimestamp)},
    % record_message([M]);
    % ok;
metrics({_, {rcbcast_ack, MessageVV, _Actor}, N}) ->
    M= {rcbcast_ack, get_byte_size(MessageVV)},
    record_message(M, N).

%% @private
record_message({Type, Size}, N) ->
    [lmetrics:record_message(Type, Size) || _ <- lists:seq(1, N)].