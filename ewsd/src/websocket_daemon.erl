%% 
%% Basic implementation of the WebSocket draft-hybi-10:
%% http://tools.ietf.org/html/draft-ietf-hybi-thewebsocketprotocol-10
%% However, it's not completely compliant with the WebSocket spec.
%%
%% @author Andy W. Song
%%
-module(websocket_daemon).
-compile(export_all).

%% API

%% Ready States
-define(CONNECTING,0).
-define(OPEN,1).
-define(CLOSED,2).

-export([behaviour_info/1]).

behaviour_info(callbacks) ->
    [{onmessage,1},{onopen,0},{onclose,0}];
behaviour_info(_) ->
    undefined.

-record(state, {socket,readystate=undefined,headers=[],accept,callback,fpid}).

check_headers(Headers, RequiredHeaders) ->
    F = fun ({Tag, Val}) ->
	if
	    is_atom (Tag) ->
		Term = Tag;
	    true ->
		Term = string:to_lower(Tag)
	end,
	% see if the required Tag is in the Headers
	case proplists:get_value(Term, Headers) of
	    undefined -> true; % header not found, keep in list
	    HVal ->
		case Val of
		    ignore -> false; % ignore value -> ok, remove from list
		    HVal -> false;	 % expected val -> ok, remove from list
		    _A ->
			error_logger:error_msg("Expected: ~p, actual ~p~n",[_A,HVal]),
			true		 % val is different, keep in list
		end		
	end
    end,
    case lists:filter(F, RequiredHeaders) of
	[] -> true;
	MissingHeaders -> MissingHeaders
    end.

acceptor(LSocket) ->
    case gen_tcp:accept(LSocket) of
	{ok, Sock} ->
	    Pid = spawn(?MODULE,handshake_loop, [#state{readystate=undefined,socket=Sock}]),
	    gen_tcp:controlling_process(Sock, Pid),
	    ok = inet:setopts(Sock, [{active,true},{packet,http}]);
	{error, Reason} ->
	    error_logger:error_msg("gen_tcp:connect error Reason: ~p~n", [Reason])
    end,
    acceptor(LSocket).

handshake_loop(State) ->
    receive
	{http, _Socket, {http_request, 'GET', _Path, _Version}} ->
	    State1 = State#state{readystate=?CONNECTING},
	    handshake_loop(State1);
	{http,_Socket,{http_header, _, Name, _, Value}} when is_atom(Name) ->
	    case State#state.readystate of
		?CONNECTING ->
		    H = [{Name,Value} | State#state.headers],
		    State1 = State#state{headers=H},
		    ?MODULE:handshake_loop(State1);
		undefined ->
		    error_logger:error_msg("PID ~p undefined state1~n, Name: ~p, Value ~p", [self(),Name,Value]),
		    %% Bad state should have received response first
		    {stop,error,State}
	    end;
	{http,_Socket,{http_header, _, Name, _, Value}} ->
	    case State#state.readystate of
		?CONNECTING ->
		    H = [{string:to_lower(Name),Value} | State#state.headers],
		    State1 = State#state{headers=H},
		    ?MODULE:handshake_loop(State1);
		undefined ->
		    error_logger:error_msg("PID ~p undefined state1~n, Name: ~p, Value ~p", [self(),Name,Value]),
		    %% Bad state should have received response first
		    {stop,error,State}
	    end;
	%% Once we have all the headers check for the 'Upgrade' flag 
	{http,Socket,http_eoh} ->
	    %% Validate headers, set state, change packet type back to raw
	    Headers = State#state.headers,
	    RequiredHeaders = [
		{'Host', ignore},
		{'Upgrade', "WebSocket"},
		{'Connection', "Upgrade"},
		{"Sec-WebSocket-Key", ignore},
		{"Sec-WebSocket-Origin", ignore},
		{"Sec-WebSocket-Version", "8"}
	    ],
	    % check for headers existance
	    case check_headers(Headers, RequiredHeaders) of
		true -> 
		    Key = proplists:get_value(string:to_lower("Sec-WebSocket-Key"),Headers),
		    KeyString = base64:decode(Key),
		    AcceptString = <<KeyString/binary, <<"258EAFA5-E914-47DA-95CA-C5AB0DC85B11">>/binary>>,
		    Accept = base64:encode_to_string(AcceptString),
		    Res = "HTTP/1.1 101 Switching Protocols\r\n" ++
			"Upgrade: WebSocket\r\n" ++
			"Connection: Upgrade\r\n" ++ 
			"Sec-WebSocket-Accept: " ++ Accept ++ "\r\n\r\n",
		    gen_tcp:send(Socket,Res),
		    inet:setopts(Socket, [{packet, raw}]),
%		    Mod = State#state.callback,
%		    Mod:onopen(),
%		    error_logger:info_msg("Finishing Handshake"),
		    State1 = State#state{readystate=?OPEN,socket=Socket,headers=[],accept=none},
		    erlang:hibernate(?MODULE, websocket_loop, [State1,none]);

		_RemainingHeaders ->
		    error_logger:error_msg("Missing headers: ~p, of headers ~p", [_RemainingHeaders,Headers]),
		    {stop,error,State}
	    end;
	_Any ->
	    error_logger:error_msg("Shouldn't receive anything here: ~p", [_Any])
    end.

unmask(Key, <<_:512,_Rest/binary>>=Data) ->
   K = binary:copy(Key, 512 div 32),
   <<LongKey:512>> = K,
   <<ShortKey:32>> = Key,
   unmask(ShortKey, LongKey, Data, <<>>);
unmask(Key, Data) ->
   <<ShortKey:32>> = Key,
   unmask(ShortKey,none, Data, <<>>).

unmask(Key, LongKey, Data,Accu) ->
   case Data of
       <<A:512, Rest/binary>> ->
           C = A bxor LongKey,
           unmask(Key, LongKey, Rest, <<Accu/binary, C:512>>);
       <<A:32,Rest/binary>> ->
           C = A bxor Key,
           unmask(Key,LongKey,Rest,<<Accu/binary,C:32>>);
       <<A:24>> ->
           <<B:24, _:8>> = <<Key:32>>,
           C = A bxor B,
           <<Accu/binary,C:24>>;
       <<A:16>> ->
           <<B:16, _:16>> = <<Key:32>>,
           C = A bxor B,
           <<Accu/binary,C:16>>;
       <<A:8>> ->
           <<B:8, _:24>> = <<Key:32>>,
           C = A bxor B,
           <<Accu/binary,C:8>>;
       <<>> ->
           Accu
   end.

websocket_loop(State,Buffer) ->
    receive
	{send,BData} ->
            Len = erlang:size(BData),
            if
                Len < 126 ->
                    Msg = [<<1:1, 0:3,2:4,0:1,Len:7>>,BData];
                Len < 65536 ->
                    Msg = [<<1:1, 0:3,2:4,0:1,126:7,Len:16>>,BData];
                true ->
                    Msg = [<<1:1, 0:3,2:4,0:1,127:7,Len:64>>,BData]
            end,
	    gen_tcp:send(State#state.socket,Msg),
	    erlang:hibernate(?MODULE, websocket_loop, [State,Buffer]);
	{tcp, _Socket, Data} ->
	    handle_data(Data,Buffer,State);
	close ->
%	    Mod = State#state.callback,
%	    Mod:onclose(),
	    error_logger:info_msg("Closing"),
	    gen_tcp:close(State#state.socket),
	    State1 = State#state{readystate=?CLOSED},
	    error_logger:error_msg("PID ~p Closed~n", [self()]),
	    {stop,normal,State1};
	{tcp_closed, _Socket} ->
%	    Mod = State#state.callback,
%	    Mod:onclose(),
	    error_logger:info_msg("Closing"),
	    {stop,normal,State};
	{tcp_error, _Socket} ->
	    error_logger:error_msg("PID ~p TCP error~n", [self()]),
	    {stop,tcp_error,State};
	Any ->
	    io:format("PID ~p, msg: ~p~n", [self(),Any])
    end.

%%  0                   1                   2                   3
%%  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
%% +-+-+-+-+-------+-+-------------+-------------------------------+
%% |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
%% |I|S|S|S|  (4)  |A|     (7)     |             (16/63)           |
%% |N|V|V|V|       |S|             |   (if payload len==126/127)   |
%% | |1|2|3|       |K|             |                               |
%% +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
%% |     Extended payload length continued, if payload len == 127  |
%% + - - - - - - - - - - - - - - - +-------------------------------+
%% |                               |Masking-key, if MASK set to 1  |
%% +-------------------------------+-------------------------------+
%% | Masking-key (continued)       |          Payload Data         |
%% +-------------------------------- - - - - - - - - - - - - - - - +
%% :                     Payload Data continued ...                :
%% + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
%% |                     Payload Data continued ...                |
%% +---------------------------------------------------------------+
-define(OP_CONT,0).
-define(OP_TEXT,1).
-define(OP_BIN,2).
-define(OP_CLOSE,8).
-define(OP_PING,9).
-define(OP_PONG,10).

%Last frame of a segment
handle_frame(1,?OP_CONT,_Len,_MaskKey,_Data,_State) ->
    io:format("Segment is not supported 1~n");
%Frame w/o segment
handle_frame(1,Opcode,Len,MaskKey,Data,State) ->
    <<Data1:Len/binary,Rest/binary>> = Data,
    case Opcode of
	?OP_BIN ->
%	    Mod = State#state.callback,
%	    Mod:onmessage(unmask(MaskKey,Data1));
%	    error_logger:info_msg("Received Msg: ~p",[unmask(MaskKey,Data1)]),
	    self() ! {send, unmask(MaskKey,Data1)};
	?OP_PING ->
	    self() ! {send,?OP_PONG,Data1};
	?OP_PONG ->
	    ok;
	?OP_CLOSE ->
	    self() ! close;
	_Any ->
	    self() ! close
    end,

    case Rest of 
	<<>> ->
	    erlang:hibernate(?MODULE, websocket_loop, [State,none]);
%	    websocket_loop(State,none);
	_ ->
	    handle_data(Rest,none,State)
    end;
%Cont. frame of a segment
handle_frame(0,?OP_CONT,_Len,_MaskKey,_Data,_State) ->
    io:format("Segment is not supported 2~n");
%first frame of a segment
handle_frame(0,_Opcode,_Len,_MaskKey,_Data,_State) ->
    io:format("Segment is not supported 3~n").

handle_data(<<Fin:1,0:3,Opcode:4,1:1,PayloadLen:7,MaskKey:4/binary,PayloadData/binary>>,none,State) when PayloadLen < 126 andalso PayloadLen =< size(PayloadData) ->
    handle_frame(Fin,Opcode,PayloadLen,MaskKey,PayloadData,State);
handle_data(<<Fin:1,0:3,Opcode:4,1:1,126:7,PayloadLen:16,MaskKey:4/binary,PayloadData/binary>>,none,State) when PayloadLen =< size(PayloadData) ->
    handle_frame(Fin,Opcode,PayloadLen,MaskKey,PayloadData,State);
handle_data(<<Fin:1,0:3,Opcode:4,1:1,127:7,0:1,PayloadLen:63,MaskKey:4/binary,PayloadData/binary>>,none,State) when PayloadLen =< size(PayloadData) ->
    handle_frame(Fin,Opcode,PayloadLen,MaskKey,PayloadData,State);
% Error, the MSB of extended payload length must be 0
handle_data(<<_Fin:1,0:3,_Opcode:4,_:1,127:7,1:1,_PayloadLen:63,_PayloadData/binary>>,none,_State) ->
    error_logger:error_msg("the MSB of extended payload length must be 0.~n"),
    self() ! close;
% Error, Client to server message must be masked 
handle_data(<<_Fin:1,0:3,_Opcode:4,0:1,_PayloadLen:7,_Data/binary>>,none,_State) ->
    error_logger:error_msg("Client to server message must be masked.~n"),
    self() ! close;
handle_data(Data,none,State) ->
    erlang:hibernate(?MODULE, websocket_loop, [State,Data]);
handle_data(Data,Buffer,State) ->
    handle_data(<<Buffer/binary,Data/binary>>,none,State).
%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

