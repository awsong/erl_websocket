-module(ewsd_app).
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-behaviour(application).

%% Application callbacks
-export([start/0, start/2, stop/1]).

start() -> application:start(ewsd).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    {ok,LSocket} = gen_tcp:listen(80,[binary,{active,false},{reuseaddr, true}]),
    _Acceptors = [ spawn(websocket_daemon,acceptor,[LSocket])|| _X <- lists:seq(1,50)],
    ewsd_sup:start_link().

stop(_State) ->
    ok.

-ifdef(TEST).

mask_test() ->
    Data = <<16#7f,16#9f,16#4d,16#51,16#58>>,
    Key = <<16#37,16#fa,16#21,16#3d>>,
    Result = <<"Hello">>,
    ?assertEqual(Result, websocket_daemon:unmask(Key,Data)).
mask1_test() ->
    Data = <<115,155,76,83,94,142>>,
    Key = <<16#37,16#fa,16#21,16#3d>>,
    Result = <<"Damnit">>,
    ?assertEqual(Result, websocket_daemon:unmask(Key,Data)).
mask2_test() ->
    Data = binary:copy(<<50>>, 44),
    Key = <<14,14,14,14>>,
    Result = binary:copy(<<60>>,44),
    ?assertEqual(Result, websocket_daemon:unmask(Key,Data)).
mask3_test() ->
    Data = binary:copy(<<50>>, 556),
    Key = <<14,14,14,14>>,
    Result = binary:copy(<<60>>,556),
    ?assertEqual(Result, websocket_daemon:unmask(Key,Data)).
mask4_test() ->
    Data = binary:copy(<<50>>, 66666),
    Key = <<14,14,14,14>>,
    Result = binary:copy(<<60>>,66666),
    ?assertEqual(Result, websocket_daemon:unmask(Key,Data)).
-endif.
