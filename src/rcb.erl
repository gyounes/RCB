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

-module(rcb).
-author("Georges Younes <georges.r.younes@gmail.com>").

-export([start/0,
         stop/0]).

%% API
-export([rcbdelivery/1,
         rcbcast/2,
         rcbmemory/1,
         rcbfullmembership/1]).

-include("rcb.hrl").

%% @doc Start the application.
start() ->
    application:ensure_all_started(rcb).

%% @doc Stop the application.
stop() ->
    application:stop(rcb).

%%%===================================================================
%%% API
%%%===================================================================

%% Set delivery Notification function.
-spec rcbdelivery(term()) -> ok.
rcbdelivery(Node) ->
    ?HANDLER:rcbdelivery(Node).

%% Broadcast message.
-spec rcbcast(message(), vclock()) -> ok.
rcbcast(MessageBody, VV) ->
    ?HANDLER:rcbcast(MessageBody, VV).

%% Receives a function to calculate rcb memory size.
-spec rcbmemory(term()) -> non_neg_integer().
rcbmemory(CalcFunction) ->
    ?HANDLER:rcbmemory(CalcFunction).

%% callback for setting fullmemberhsip of the group.
-spec rcbfullmembership(term()) -> ok.
rcbfullmembership(Nodes) ->
    ?HANDLER:rcbfullmembership(Nodes).