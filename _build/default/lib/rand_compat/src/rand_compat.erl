%% -------------------------------------------------------------------
%%
%% Copyright (c) 2016 Christopher Meiklejohn.  All Rights Reserved.
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

-module(rand_compat).
-author("Christopher S. Meiklejohn <christopher.meiklejohn@gmail.com>").

-export([seed/3,
         seed/1,
         uniform/0,
         uniform/1]).

seed(SValue) ->
    case have_rand() of
        true  -> rand:seed(exsplus, SValue);
        false -> (fun random:seed/1)(SValue)
    end.

seed(A,B,C) ->
    case have_rand() of
        true  -> rand:seed(exsplus, {A,B,C});
        false -> (fun random:seed/3)(A,B,C)
    end.

uniform() ->
    case have_rand() of
        true  -> rand:uniform();
        false -> (fun random:uniform/0)()
    end.

uniform(N) ->
    case have_rand() of
        true  -> rand:uniform(N);
        false -> (fun random:uniform/1)(N)
    end.

%% random module is deprecated since releases 19 (ERTS >= 8.0)
have_rand() ->
    (code:which(rand) /= non_existing).
