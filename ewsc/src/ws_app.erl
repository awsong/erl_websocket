-module(ws_app).
%-behaviour(callbacks).
-export([onmessage/1,onopen/0,onclose/0]).

onmessage(_Msg) ->
%    io:format("Received Msg: ~p", [_Msg]),
    ok.

onopen() ->
    ok.

onclose() ->
    ok.
