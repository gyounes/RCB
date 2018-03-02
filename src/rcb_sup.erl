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

-module(rcb_sup).
-author("Georges Younes <georges.r.younes@gmail.com>").

-behaviour(supervisor).

-include("rcb.hrl").

-export([start_link/0]).

-export([init/1]).

-define(CHILD(I, Type, Timeout),
        {I, {I, start_link, []}, permanent, Timeout, Type, [I]}).
-define(CHILD(I, Type), ?CHILD(I, Type, 5000)).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    configure(),

    Handler = {rcb_handler,
               {rcb_handler, start_link, []},
               permanent, 5000, worker, [rcb_handler]},

    Resender = {rcb_resender,
                 {rcb_resender, start_link, []},
                 permanent, 5000, worker, [rcb_resender]},

    Children = [Handler, Resender],

    RestartStrategy = {one_for_one, 10, 10},
    {ok, {RestartStrategy, Children}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @private
configure() ->
    %% configure metrics
    configure_var("LMETRICS",
                            lmetrics,
                            ?METRICS_DEFAULT).

%% @private
configure_var(Env, Var, Default) ->
    To = fun(V) -> atom_to_list(V) end,
    From = fun(V) -> list_to_atom(V) end,
    configure(Env, Var, Default, To, From).

%% @private
configure(Env, Var, Default, To, From) ->
    Current = rcb_config:get(Var, Default),
    Val = From(
        os:getenv(Env, To(Current))
    ),
    rcb_config:set(Var, Val),
    Val.
