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

-module(rcb_config).
-author("Georges Younes <georges.r.younes@gmail.com>").

-include("rcb.hrl").

-export([get/1,
         get/2,
         set/2]).
%% @doc
-spec get(atom()) -> term().
get(Property) ->
    {ok, Value} = application:get_env(?APP, Property),
    Value.

-spec get(atom(), term()) -> term().
get(Property, Default) ->
    application:get_env(?APP, Property, Default).

-spec set(atom(), term()) -> ok.
set(Property, Value) ->
    application:set_env(?APP, Property, Value).
