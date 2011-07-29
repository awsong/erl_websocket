-module(ewsc_app).
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-behaviour(application).

%% Application callbacks
-export([start/2, start/0, stop/1, start_test/0, test_loop/3]).

start() -> application:start(ewsc).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    error_logger:info_msg("Starting ewsc application...~n"),
    spawn(?MODULE,start_test,[]),
    ewsc_sup:start_link().

start_test() ->
    io:format("Start testing...~n"),
    [self() ! sync || _N <- lists:seq(1,10)],
    io:format("Start real testing...~n"),
    test_loop(0,[],now()).

-define(CONNS, 400000).
test_loop(Count,Socks,Start) ->
    receive
	{sync, Sock} ->
	    if
		Count < ?CONNS ->
		    IPn = 2 + Count div 20000,
		    IP = {30,0,0,IPn},
		    Port = 20000 + Count rem 20000,
		    FPid = self(),
		    spawn(websocket_client, start, ["30.0.0.1",80,"/",IP,Port,ws_app,FPid]),
		    test_loop(Count+1,[Sock|Socks],Start);
		true ->
		    test_loop(Count+1,[Sock|Socks],Start)
	    end;
	sync ->
	    IPn = 2 + Count div 20000,
	    IP = {30,0,0,IPn},
	    Port = 20000 + Count rem 20000,
	    FPid = self(),
	    spawn(websocket_client, start, ["30.0.0.1",80,"/",IP,Port,ws_app,FPid]),
	    test_loop(Count+1,[],Start);
	_Any ->
	    io:format("Unexpected msg:~p~n",[_Any])
    after 1000->
	    End = now(),
	    TimeSpan = timer:now_diff(End, Start) / 1000,
	    io:format("~p Done with Count:~p, time spent: ~ps~n",[self(),Count,TimeSpan]),
	    pubsub(Socks)
    end.
pubsub(Socks) ->
    receive
	go ->
	    BData = binary:copy(<<"A">>, 512),
	    Key = crypto:rand_bytes(4),
	    Len = erlang:size(BData),
	    if
		Len < 126 ->
		    Msg = [<<1:1, 0:3,2:4,1:1,Len:7>>,Key,websocket_client:mask(Key,BData)];
		Len < 65536 ->
		    Msg = [<<1:1, 0:3,2:4,1:1,126:7,Len:16>>,Key,websocket_client:mask(Key,BData)];
		true ->
		    Msg = [<<1:1, 0:3,2:4,1:1,127:7,Len:64>>,Key,websocket_client:mask(Key,BData)]
	    end,
	    io:format("Start pub/sub testing... ~n"),
	    Start = now(),
	    erlang:process_flag(priority, high),
	    [ erlang:port_command(S, Msg) || S <- Socks],
	    End = now(),
	    erlang:process_flag(priority, normal),
	    io:format("cost time: ~p~n", [timer:now_diff(End, Start) / 1000]),
	    pubsub(Socks);
	{inet_reply, _Sock, _Error} ->
	    pubsub(Socks)
    end.

stop(_State) ->
    ok.

-ifdef(TEST).

mask_test() ->
    Data = <<"Hello">>,
    Key = <<16#37,16#fa,16#21,16#3d>>,
    Result = <<16#7f,16#9f,16#4d,16#51,16#58>>,
    ?assertEqual(Result, websocket_client:mask(Key,Data)).
mask1_test() ->
    Data = <<"Damnit">>,
    Key = <<16#37,16#fa,16#21,16#3d>>,
    Result = <<115,155,76,83,94,142>>,
    ?assertEqual(Result, websocket_client:mask(Key,Data)).
mask2_test() ->
    Data = binary:copy(<<50>>, 66666),
    Key = <<14,14,14,14>>,
    Result = binary:copy(<<60>>,66666),
    ?assertEqual(Result, websocket_client:mask(Key,Data)).
mask3_test() ->
    Data = binary:copy(<<50>>, 555),
    Key = <<14,14,14,14>>,
    Result = binary:copy(<<60>>,555),
    ?assertEqual(Result, websocket_client:mask(Key,Data)).
mask4_test() ->
    Data = binary:copy(<<50>>, 44),
    Key = <<14,14,14,14>>,
    Result = binary:copy(<<60>>,44),
    ?assertEqual(Result, websocket_client:mask(Key,Data)).
mask_slow_test() ->
    {timeout, 6,  mask2_test}.
%nif_mask_test() ->
%    Data = <<"Hello">>,
%    Key = <<16#37,16#fa,16#21,16#3d>>,
%    Result = <<16#7f,16#9f,16#4d,16#51,16#58>>,
%    ?assertEqual(Result, websocket_client:nif_mask(Key,Data,<<>>)).
%mask2_test() ->
%    Max = 1024*1024*8+1,
%    Step = 1024*512,
%    Key = <<16#37,16#fa,16#21,16#3d>>,
%    A = lists:seq(1,Max,Step),
%    B = lists:map(fun (D) -> binary:copy(<<100>>,D) end, A),
%    C = lists:map(fun (D) -> timer:tc(websocket_client, websocket_client:mask, [Key, D]) end, B),
%    D = lists:zip(A, C),
%    lists:map(fun ({Index,{Time,_Val}}) -> io:format(user,"~p: ~p~n", [Index,Time]) end, D).

%mask3_test() ->
%    Max = 1024*1024*32,
%    Key = binary:decode_unsigned(<<16#37,16#fa,16#21,16#3d>>),
%    B = binary:copy(<<100>>,Max),
%    io:format("~p~n",[erlang:memory()]),
%    timer:tc(websocket_client, websocket_client:mask, [Key, B]).

%mask4_test() ->
%    Max = 1024*1024*8+1,
%    Step = 1024*512,
%    Key = <<16#37,16#fa,16#21,16#3d>>,
%    A = lists:seq(1,Max,Step),
%    B = lists:map(fun (D) -> binary:copy(<<100>>,D) end, A),
%    C = lists:map(fun (D) -> timer:tc(websocket_client, nif_mask, [Key, D, <<>>]) end, B),
%    D = lists:zip(A, C),
%    lists:map(fun ({Index,{Time,_Val}}) -> io:format(user,"~p: ~p~n", [Index,Time]) end, D).

%mask5_test() ->
%    Max = 1024*1024*32,
%    Key = <<16#37,16#fa,16#21,16#3d>>,
%    B = binary:copy(<<100>>,Max),
%    io:format("~p~n",[erlang:memory()]),
%    timer:tc(websocket_client, nif_mask, [Key, B, <<>>]).

-endif.
