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
%%

-module(rcb_SUITE).
-author("Georges Younes <georges.r.younes@gmail.com>").

%% common_test callbacks
-export([%% suite/0,
         init_per_suite/1,
         end_per_suite/1,
         init_per_testcase/2,
         end_per_testcase/2,
         all/0]).

%% tests
-compile([nowarn_export_all, export_all]).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("kernel/include/inet.hrl").


-include("rcb.hrl").

-define(PEER_PORT, 9000).

suite() ->
[{timetrap, {minutes, 1}}].

%% ===================================================================
%% common_test callbacks
%% ===================================================================

init_per_suite(_Config) ->
    _Config.

end_per_suite(_Config) ->
    _Config.

init_per_testcase(Case, _Config) ->
    ct:pal("Beginning test case ~p", [Case]),

    _Config.

end_per_testcase(Case, _Config) ->
    ct:pal("Ending test case ~p", [Case]),

    _Config.

all() ->
    [
     default_causal_test1,
     default_causal_test2,
     default_causal_test3
    ].

%% ===================================================================
%% Tests.
%% ===================================================================

%% Test causal delivery with full membership
default_causal_test1(Config) ->
  test(Config, 5, 50, 50, 0),
  ok.
default_causal_test2(Config) ->
  test(Config, 5, 50, 100, 0),
  ok.
default_causal_test3(Config) ->
  test(Config, 5, 50, 200, 0),
  ok.

test(Config, NodesNumber, MaxMsgNumber, MaxRate, Latency) ->

  %% Use the default peer service manager.
  Manager = partisan_default_peer_service_manager,

  %% Specify clients.
  Clients = node_list(1, NodesNumber, "node"),

  %% Start nodes.
  Nodes = start(default_manager_test, Config,
                [{partisan_peer_service_manager, Manager},
                 {clients, Clients},
                 {latency, Latency}]),

  %% start causal delivery and stability test
  fun_causal_test(Nodes, MaxMsgNumber, MaxRate),

  %% Stop nodes.
  stop(Nodes),

  ok.

%% ===================================================================
%% Internal functions.
%% ===================================================================

%% @private
start(_Case, _Config, Options) ->
    %% Launch distribution for the test runner.
    ct:pal("Launching Erlang distribution..."),

    os:cmd(os:find_executable("epmd") ++ " -daemon"),
    {ok, Hostname} = inet:gethostname(),
    case net_kernel:start([list_to_atom("runner@" ++ Hostname), shortnames]) of
        {ok, _} ->
            ok;
        {error, {already_started, _}} ->
            ok
    end,

    %% Load sasl.
    application:load(sasl),
    ok = application:set_env(sasl,
                             sasl_error_logger,
                             false),
    application:start(sasl),

    %% Load lager.
    {ok, _} = application:ensure_all_started(lager),

    Servers = proplists:get_value(servers, Options, []),
    Clients = proplists:get_value(clients, Options, []),
    Latency = proplists:get_value(latency, Options, 0),

    NodeNames = lists:flatten(Servers ++ Clients),

    Manager = proplists:get_value(partisan_peer_service_manager, Options),
    
    %% Start all nodes.
    InitializerFun = fun(Name) ->
      ct:pal("Starting node: ~p", [Name]),

      NodeConfig = [{monitor_master, true}, {startup_functions, [{code, set_path, [codepath()]}]}],

      case ct_slave:start(Name, NodeConfig) of
          {ok, Node} ->
              {Name, Node};
          Error ->
              ct:fail(Error)
      end
    end,
    Nodes = lists:map(InitializerFun, NodeNames),

    %% Load applications on all of the nodes.
    LoaderFun = fun({_Name, Node}) ->
      ct:pal("Loading applications on node: ~p", [Node]),

      PrivDir = code:priv_dir(?APP),

      NodeDir = filename:join([PrivDir, "lager", Node]),

      %% Manually force sasl loading, and disable the logger.   
      ct:pal("P ~p N ~p", [PrivDir, NodeDir]),
  
      ok = rpc:call(Node, application, load, [sasl]),

      ok = rpc:call(Node, application, set_env, [sasl, sasl_error_logger, false]),

      ok = rpc:call(Node, application, start, [sasl]),

      ok = rpc:call(Node, application, load, [partisan]),

      ok = rpc:call(Node, application, load, [?APP]),

      ok = rpc:call(Node, application, load, [lager]),

      ok = rpc:call(Node, application, set_env, [sasl, sasl_error_logger, false]),

      ok = rpc:call(Node, application, set_env, [lager, log_root, NodeDir]),

      ok = rpc:call(Node, application, set_env, [?APP, rcb_latency, Latency])

   end,
  
  lists:foreach(LoaderFun, Nodes),

    %% Configure settings.
    ConfigureFun = fun({Name, Node}) ->
      %% Configure the peer service.
      ct:pal("Setting peer service manager on node ~p to ~p", [Node, Manager]),
      ok = rpc:call(Node, partisan_config, set,
                    [partisan_peer_service_manager, Manager]),

      MaxActiveSize = proplists:get_value(max_active_size, Options, 5),
      ok = rpc:call(Node, partisan_config, set,
                    [max_active_size, MaxActiveSize]),

      Servers = proplists:get_value(servers, Options, []),
      Clients = proplists:get_value(clients, Options, []),

      %% Configure servers.
      case lists:member(Name, Servers) of
        true ->
          ok = rpc:call(Node, partisan_config, set, [tag, server]);
        false ->
          ok
      end,

      %% Configure clients.
      case lists:member(Name, Clients) of
        true ->
          ok = rpc:call(Node, partisan_config, set, [tag, client]);
        false ->
          ok
      end
    end,
    lists:foreach(ConfigureFun, Nodes),

    ct:pal("Starting nodes."),

    StartFun = fun({_Name, Node}) ->
      %% Start partisan.
      {ok, _} = rpc:call(Node, application, ensure_all_started, [?APP])
    end,
    lists:foreach(StartFun, Nodes),

    ct:pal("Clustering nodes."),
    lists:foreach(fun(Node) -> cluster(Node, Nodes) end, Nodes),

    timer:sleep(1000),

    %% Verify membership.
    %%
    VerifyFun = fun({_Name, Node}) ->
      {ok, Members} = rpc:call(Node, Manager, members, []),

      %% If this node is a server, it should know about all nodes.
      SortedNodes = lists:usort([N || {_, N} <- Nodes]) -- [Node],
      SortedMembers = lists:usort(Members) -- [Node],
      case SortedMembers =:= SortedNodes of
        true ->
          ok;
        false ->
          ct:fail("Membership incorrect; node ~p should have ~p but has ~p", [Node, SortedNodes, SortedMembers])
      end
    end,

    %% Verify the membership is correct.
    lists:foreach(VerifyFun, Nodes),

    ct:pal("Partisan fully initialized."),

    Nodes.

%% @private
codepath() ->
    lists:filter(fun filelib:is_dir/1, code:get_path()).

%% @private
omit(OmitNameList, Nodes0) ->
  FoldFun = fun({Name, _Node} = N, Nodes) ->
    case lists:member(Name, OmitNameList) of
      true ->
        Nodes;
      false ->
        Nodes ++ [N]
    end
  end,
  lists:foldl(FoldFun, [], Nodes0).

%% @private
cluster({Name, _Node} = Myself, Nodes) when is_list(Nodes) ->
  
  %% Omit just ourselves.
  OtherNodes = omit([Name], Nodes),

  lists:foreach(fun(OtherNode) -> join(Myself, OtherNode) end, OtherNodes).

join({_, Node}, {_, OtherNode}) ->
  PeerPort = rpc:call(OtherNode,
    partisan_config,
    get,
    [peer_port, ?PEER_PORT]),
  ct:pal("Joining node: ~p to ~p at port ~p", [Node, OtherNode, PeerPort]),
  ok = rpc:call(Node,
    partisan_peer_service,
    join,
    [{OtherNode, {127, 0, 0, 1}, PeerPort}]).

%% @private
stop(Nodes) ->
  StopFun = fun({Name, _Node}) ->
    case ct_slave:stop(Name) of
      {ok, _} ->
        ok;
      Error ->
        ct:fail(Error)
    end
  end,
  lists:foreach(StopFun, Nodes),
  ok.

%% @private
node_list(_Start, 0, _Str) -> [];
node_list(Start, End, Str) ->
  [list_to_atom(string:join([Str, integer_to_list(X)], "_")) || X <- lists:seq(Start, End) ].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @private
fun_receive(Me, TotalMessages, TotalDelivered, DelvQ, Receiver) ->
  receive
    rcbcast ->
      ok = rpc:call(Me, rcb, rcbcast, [msg]),
      % ct:pal("Sending msg"),
      fun_receive(Me, TotalMessages, TotalDelivered, DelvQ, Receiver);
    {delivery, _Origin, MsgVV, _Msg} ->
      DelvQ1 = DelvQ ++ [MsgVV],
      %% For each node, update the number of delivered messages on every node
      TotalDelivered1 = TotalDelivered + 1,

      % ct:pal("delivered ~p out of ~p", [TotalDelivered1, TotalMessages]),

      %% check if all msgs were delivered on all the nodes
      case TotalMessages =:= TotalDelivered1 of
        true ->
          Receiver ! {done, Me, DelvQ1};
        false ->
          fun_receive(Me, TotalMessages, TotalDelivered1, DelvQ1, Receiver)
      end;
    M ->
      ct:fail("UNKWONN ~p", [M])
    end.

%% @private
fun_ready_to_check(Nodes, N, Dict, Runner) ->
  ct:pal("fun_ready_to_check"),
  receive
    {done, Node, DelvQ1} ->
      Dict1 = dict:store(Node, DelvQ1, Dict),
      case N > 1 of
        true -> 
          fun_ready_to_check(Nodes, N-1, Dict1, Runner);
        false ->
          Runner ! {done, Nodes, Dict1}
      end;
    M ->
      ct:fail("fun_ready_to_check :: received incorrect message: ~p", [M])
  end.

%% @private
fun_send(_NodeReceiver, 0, _MaxRate) ->
  ok;
fun_send(NodeReceiver, Times, MaxRate) ->
  % timer:sleep(rand:uniform(MaxRate)),
  timer:sleep(MaxRate),
  NodeReceiver ! rcbcast,
  fun_send(NodeReceiver, Times - 1, MaxRate).

%% @private
fun_check_delivery(Nodes, NodeMsgInfoMap) ->
ct:pal("fun_check_delivery"),
  
  %% check that all delivered VVs are the same
  {_, Node} = lists:nth(1, Nodes),
  DelMsgQ = lists:usort(dict:fetch(Node, NodeMsgInfoMap)),

  Test1 = lists:foldl(
    fun(I, AccI) ->
      {_, Node1} = lists:nth(I, Nodes),
      DelMsgQ1 = lists:usort(dict:fetch(Node1, NodeMsgInfoMap)),
      AccI andalso DelMsgQ =:= DelMsgQ1
    end,
    true,
  lists:seq(2, length(Nodes))),
  
  Test2 = lists:foldl(
    fun({_Name2, Node2}, Acc) ->
      DelMsgQ2 = dict:fetch(Node2, NodeMsgInfoMap),
      Acc andalso lists:foldl(
        fun(I, AccI) ->
          lists:foldl(
            fun(J, AccJ) ->
              AccJ andalso not vclock:descends(lists:nth(I, DelMsgQ2), lists:nth(J, DelMsgQ2))
            end,
            AccI,
          lists:seq(I+1, length(DelMsgQ2))) 
        end,
        true,
      lists:seq(1, length(DelMsgQ2)-1))
    end,
    Test1,
  Nodes),

  case Test2 of
    true ->
      ok;
    false ->
      ct:fail("fun_check_delivery")
  end.

%% @private
fun_check() ->
ct:pal("fun_check"),
  receive
    {done, Nodes, Dict} ->
      fun_check_delivery(Nodes, Dict);
    M ->
      ct:fail("fun_check :: received incorrect message: ~p", [M])
  end.

fun_intialize_dict_info(Nodes, MaxMsgNumber) ->
  lists:foldl(
  fun({_Name, Node}, Acc) ->
    dict:store(Node, MaxMsgNumber, Acc)
    % dict:store(Node, rand:uniform(MaxMsgNumber), Acc)
  end,
  dict:new(),
  Nodes).

%% private   
fun_update_full_membership(Nodes) ->   
  lists:foreach(fun({_Name, Node}) ->    
      ok = rpc:call(Node, rcb, rcbfullmembership, [Nodes])    
  end, Nodes).

fun_causal_test(Nodes, MaxMsgNumber, MaxRate) ->

  fun_update_full_membership(Nodes),

  timer:sleep(1000),

  DictInfo = fun_intialize_dict_info(Nodes, MaxMsgNumber),

  %% Calculate the number of Messages that will be delivered by each node
  %% result = sum of msgs sent per node * number of nodes (Broadcast)
  TotNumMsgToRecv = dict:fold(
    fun(_Key, V, Acc)->
      Acc + V
    end,
    0,
    DictInfo),

  Self = self(),

  %% Spawn a receiver process to collect all delivered msgs per node
  Receiver = spawn(?MODULE, fun_ready_to_check, [Nodes, length(Nodes), DictInfo, Self]),
     
  timer:sleep(1000),

  NewDictInfo = lists:foldl(
  fun({_Name, Node}, Acc) ->
    NumMsgToSend = dict:fetch(Node, Acc),
    
    %% Spawn a receiver process for each node to rcbcast and deliver msgs
    NodeReceiver = spawn(?MODULE, fun_receive, [Node, TotNumMsgToRecv, 0, [], Receiver]),
    
    ok = rpc:call(Node,
      rcb,
      rcbdelivery,
      [NodeReceiver]),    
    dict:store(Node, {NumMsgToSend, NodeReceiver}, Acc)
  end,
  DictInfo,
  Nodes),

  timer:sleep(1000),

  %% Sending random messages and recording on delivery the VV of the messages in delivery order per Node
  lists:foreach(fun({_Name, Node}) ->
    {MsgNumToSend, NodeReceiver} = dict:fetch(Node, NewDictInfo),
    spawn(?MODULE, fun_send, [NodeReceiver, MsgNumToSend, MaxRate])
  end, Nodes),

  fun_check().