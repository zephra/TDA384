-module(server).
-export([start/1,stop/1]).

-record(channelState, {
    name,
    users = []
}).

-record(serverState, {
    channels = [],
    nicks = []
}).

% Start a new server process with the given name
% Do not change the signature of this function.
start(ServerAtom) ->
    State = #serverState{},
    Pid = genserver:start(ServerAtom, State, fun handle_server/2),
    Pid.

% Stop the server process registered to the given name,
% together with any other associated processes
stop(ServerAtom) ->
    genserver:request(ServerAtom, stop),
    genserver:stop(ServerAtom).

list_find(_, []) ->
  false;
list_find(Needle, Haystack) ->
  Nick = hd(Haystack),
  if
    Needle == Nick -> true;
    true -> list_find(Needle, tl(Haystack))
  end.

handle_server(State, Data) ->
  AllChannels = State#serverState.channels,

  case Data of
    {join, Channel, Nick, Sender} ->
      ChannelExists = list_find(Channel, AllChannels),
      if
        ChannelExists ->
          genserver:request(list_to_atom(Channel), {join, Sender, self()}),
          receive
            error -> {reply, error, State};
            ok ->
              NickExists = list_find(Nick, State#serverState.nicks),
              if
                NickExists == true ->
                  {reply, join, State};
                true ->
                  NewState = #serverState{nicks = [ Nick | State#serverState.nicks ], channels = State#serverState.channels},
                  {reply, join, NewState}
              end
          end;

        true ->
          genserver:start(list_to_atom(Channel), #channelState{ name=Channel, users=[ Sender ]}, fun handle_channel/2),
          NewState = State#serverState{channels = [ Channel | AllChannels ], nicks = State#serverState.nicks},
          {reply, join, NewState}
      end;

    {leave, Channel, Sender} ->
      { ChannelExists, ChannelPid } = list_find(Channel, AllChannels),

      if
        ChannelExists ->
          genserver:request(ChannelPid, {leave, Sender, self()}),
          receive
            error -> {reply, error, State};
            ok -> {reply, leave, State}
          end;

        true ->
          {reply, error, State}
      end;

    {message_send, Channel, Nick, Msg, Sender} ->

      ChannelExists = list_find(Channel, AllChannels),

      if
        ChannelExists ->
          genserver:request(list_to_atom(Channel), {message_send, Nick, Msg, Sender, self()}),
          receive
            error -> {reply, error, State};
            ok -> {reply, message_send, State}
          end;

        true ->
          {reply, error, State}
      end;

    {nick, Nick} ->
      NickExists = list_find(Nick, State#serverState.nicks),
      if
        NickExists == true ->
          {reply, error, State};
        true ->
          NewState = #serverState{nicks = [ Nick | State#serverState.nicks ], channels = State#serverState.channels},
          { reply, ok, NewState }
      end;
    stop ->
      [ genserver:stop(list_to_atom(Channel)) || Channel <- State#serverState.channels ],
  end.

% --- This may only be moved to where it is needed, since it's just one row?
send_to_all(Receivers, Channel, Nick, Message, Sender) ->
  spawn(fun() -> [ genserver:request(X, {message_receive, Channel, Nick, Message}) || X <- Receivers, X =/= Sender] end ).

list_remove(_, [], Rest) ->
  Rest;
list_remove(Needle, Haystack, Rest) ->
  User = hd(Haystack),
  if
    Needle == User ->
      list_remove(Needle, tl(Haystack), Rest);
    true ->
      list_remove(Needle, tl(Haystack), [ hd(Haystack) | Rest ])
  end.

user_exists_in_channel(_, []) ->
  false;
user_exists_in_channel(Needle, Haystack) ->
  User = hd(Haystack),
  if
    Needle == User -> true;
    true -> user_exists_in_channel(Needle, tl(Haystack))
  end.

handle_channel(State, Data) ->
  case Data of
    {join, Sender, Server} ->
      IsMember = user_exists_in_channel(Sender, State#channelState.users),
      case IsMember of
        true ->
          Server ! error,
          {reply, join, State};
        false ->
          NewState = State#channelState{users = [ Sender | State#channelState.users ]},
          Server ! ok,
          {reply, join, NewState}
      end;

    {leave, Sender, Server} ->
      IsMember = user_exists_in_channel(Sender, State#channelState.users),
      case IsMember of
        true ->
          OldUsers = State#channelState.users,
          NewUsers = list_remove(Sender, OldUsers, []),
          NewState = State#channelState{users = NewUsers},
          Server ! ok,
          {reply, leave, NewState};
        false ->
          Server ! error,
          {reply, error, State}
      end;

    {message_send, Nick, Msg, Sender, Server} ->
      IsMember = user_exists_in_channel(Sender, State#channelState.users),
      case IsMember of
        true ->
          send_to_all(State#channelState.users, State#channelState.name, Nick, Msg, Sender),
          Server ! ok,
          {reply, message_send, State};
        false ->
          Server ! error,
          {reply, error, State}
      end
  end.
