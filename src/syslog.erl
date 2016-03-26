%%==============================================================================
%% Copyright 2016 Jan Henry Nystrom <JanHenryNystrom@gmail.com>
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%==============================================================================

%%%-------------------------------------------------------------------
%%% @doc
%%%  A Syslog library based on:
%%%    The Syslog Protocol                                             (rfc5424)
%%%    Transmission of Syslog Messages over UDP                        (rfc5426)
%%%    Textual Conventions for Syslog Management                       (rfc5427)
%%%
%%% @end
%%%
%% @author Jan Henry Nystrom <JanHenryNystrom@gmail.com>
%% @copyright (C) 2016, Jan Henry Nystrom <JanHenryNystrom@gmail.com>
%%%-------------------------------------------------------------------
-module(syslog).
-copyright('Jan Henry Nystrom <JanHenryNystrom@gmail.com>').

%% Library functions
-export([encode/1, encode/2,
         decode/1, decode/2
        ]).

%% Exported types
-export_type([]).

%% Includes

%% Records
-record(opts, {return_type = iolist :: iolist | binary}).

%% -record(time_stamp, {date              :: {integer(), integer(), integer()},
%%                      time              :: {integer(), integer(), integer()},
%%                      fraction    = 0   :: integer(),
%%                      offset_sign = 'Z' :: 'Z' | '-' |'+',
%%                      offset            :: undefined | {integer(), integer()}
%%                     }).

%% -record(header, {facility         :: atom(),
%%                  severity         :: atom(),
%%                  version    = 1   :: integer(),
%%                  time_stamp = nil :: nil | #time_stamp{},
%%                  host_name  = nil :: nil | binary(),
%%                  app_name   = nil :: nil | binary(),
%%                  proc_id    = nil :: nil | binary(),
%%                  msg_id     = nil :: nil | binary()
%%                 }).

%% Types
-type opt() :: none.

%% Defines
-define(GREGORIAN_POSIX_DIFF, 62167219200).

%% ===================================================================
%% Library functions.
%% ===================================================================

%%--------------------------------------------------------------------
%% Function: encode(Term) -> Syslog entry.
%% @doc
%%   Encodes the structured Erlang term as an iolist.
%%   Equivalent of encode(Term, []) -> Syslog encode.
%% @end
%%--------------------------------------------------------------------
-spec encode(_) -> iolist().
%%--------------------------------------------------------------------
encode(Term) -> encode(Term, #opts{}).

%%--------------------------------------------------------------------
%% Function: encode(Term, Options) -> Syslog entry
%% @doc
%%   Encodes the structured Erlang term as an iolist or binary.
%%   Encode will give an exception if the erlang term is not well formed.
%%   Options are:
%%     binary -> a binary is returned
%%     iolist -> a iolist is returned
%% @end
%%--------------------------------------------------------------------
-spec encode(_, [opt()] | #opts{}) -> iolist() | binary().
%%--------------------------------------------------------------------
encode(Term, Opts = #opts{}) -> do_encode(Term, Opts);
encode(Term, Opts) ->
    ParsedOpts = parse_opts(Opts, #opts{}),
    case ParsedOpts#opts.return_type of
        iolist-> do_encode(Term, ParsedOpts);
        binary -> iolist_to_binary(do_encode(Term, ParsedOpts))
    end.

%%--------------------------------------------------------------------
%% Function: decode(Binary) -> Term.
%% @doc
%%   Decodes the binary into a structured Erlang term.
%%   Equivalent of decode(Binary, []) -> URI.
%% @end
%%--------------------------------------------------------------------
-spec decode(binary()) -> _.
%%--------------------------------------------------------------------
decode(Binary) -> decode(Binary, #opts{}).

%%--------------------------------------------------------------------
%% Function: decode(Binary, Options) -> Term.
%% @doc
%%   Decodes the binary into a structured Erlang.
%%   Decode will give an exception if the binary is not well formed
%%   Syslog entry.
%%   Options are:
%% @end
%%--------------------------------------------------------------------
-spec decode(binary(), [opt()] | #opts{}) -> _.
%%--------------------------------------------------------------------
decode(Binary, Opts = #opts{}) -> do_decode(Binary, Opts);
decode(Binary, Opts) -> do_decode(Binary, parse_opts(Opts, #opts{})).

%% ===================================================================
%% Internal functions.
%% ===================================================================

%% ===================================================================
%% Encoding
%% ===================================================================

do_encode(_, _) -> [].

encode_severity(emerg) -> 0;
encode_severity(alert) -> 1;
encode_severity(crit) -> 2;
encode_severity(err) -> 3;
encode_severity(warning) -> 4;
encode_severity(notice) -> 5;
encode_severity(info) -> 6;
encode_severity(debug) ->  7.

encode_facility(kern) -> 0;
encode_facility(user) -> 8;
encode_facility(mail) -> 16;
encode_facility(daemon) -> 24;
encode_facility(auth) -> 32;
encode_facility(syslog) -> 40;
encode_facility(lpr) -> 48;
encode_facility(news) -> 56;
encode_facility(uucp) -> 64;
encode_facility(cron) -> 72;
encode_facility(authpriv) -> 80;
encode_facility(ftp) -> 88;
encode_facility(ntp) -> 96;
encode_facility(audit) -> 104;
encode_facility(console) -> 112;
encode_facility(cron2) -> 120;
encode_facility(local0) -> 128;
encode_facility(local1) -> 136;
encode_facility(local2) -> 144;
encode_facility(local3) -> 152;
encode_facility(local4) -> 160;
encode_facility(local5) -> 168;
encode_facility(local6) -> 176;
encode_facility(local7) -> 184.

%% ===================================================================
%% Decoding
%% ===================================================================

do_decode(<<$<, T/binary>>, _) ->
    {Header, T1} = decode_header(T, <<>>),
    {Id, Params, T2} = decode_structured_data(T1).

decode_header(<<$>, T/binary>>, Acc) ->
    Priority = binary_to_integer(Acc),
    Facility = decode_facility(Priority div 8),
    Severity = decode_severity(Priority - (Facility * 8)),
    decode_version(T, #{facility => Facility, severity => Severity}, <<>>);
decode_header(<<H, T/binary>>, Acc) ->
    decode_header(T, <<Acc/binary, H>>).

decode_version(<<$\s, T/binary>>, Header, Acc) ->
    decode_timestamp(T, Header#{version => binary_to_integer(Acc)});
decode_version(<<H, T/binary>>, Header, Acc) ->
    decode_version(T, Header, <<Acc/binary ,H>>).

decode_timestamp(<<$-, $\s, T/binary>>, Header) ->
    decode_hostname(T, Header#{time_stamp => nil});
decode_timestamp(<<Y:32, $-, M:2/bytes, $-, D:2/bytes, $T,
                   H:2/bytes, $:, Mi:2/bytes, $:, S:2/bytes,
                   T/binary>>,
                 Header) ->
    Header1 = Header#{time_stamp => {{Y,
                                      binary_to_integer(M),
                                      binary_to_integer(D)},
                                     {binary_to_integer(H),
                                      binary_to_integer(Mi),
                                      binary_to_integer(S)}}},
    decode_timestamp1(T, Header1).

decode_timestamp1(<<$Z, $\s, T/binary>>, Header) -> decode_hostname(T, Header);
decode_timestamp1(<<$., T/binary>>, Header) -> decode_fraction(T, Header, <<>>);
decode_timestamp1(<<$+, T/binary>>, Header) ->
    decode_offset(T, Header#{offset_sign => '+'});
decode_timestamp1(<<$-, T/binary>>, Header ) ->
    decode_offset(T, Header#{offset_sign => '-'}).

decode_fraction(<<$Z, $\s, T/binary>>, Header, Acc) ->
    decode_hostname(T, Header#{fraction => Acc}).

decode_offset(<<H:2/bytes, $:, M:2/bytes, $\s, T/binary>>, Header) ->
    decode_hostname(T, Header#{offset => {H, M}}).

decode_hostname(<<$-, $\s, T/binary>>, Header) ->
    decode_appname(T, Header#{host_name => nil});
decode_hostname(Bin, Header) ->
    {HostName, T} = decode_string(Bin, <<>>),
    decode_appname(T, Header#{host_name => HostName}).

decode_appname(<<$-, $\s, T/binary>>, Header) ->
    decode_proc_id(T, Header#{app_name => nil});
decode_appname(Bin, Header) ->
    {AppName, T} = decode_string(Bin, <<>>),
    decode_proc_id(T, Header#{app_name => AppName}).

decode_proc_id(<<$-, $\s, T/binary>>, Header) ->
    decode_msg_id(T, Header#{proc_id => nil});
decode_proc_id(Bin, Header) ->
    {ProcId, T} = decode_string(Bin, <<>>),
    decode_msg_id(T, Header#{proc_id => ProcId}).

decode_msg_id(<<$-, $\s, T/binary>>, Header) -> {Header#{msg_id => nil}, T};
decode_msg_id(Bin, Header) ->
    {ProcId, T} = decode_string(Bin, <<>>),
    {Header#{msg_id => ProcId}, T}.

decode_structured_data(<<$-, T/binary>>) -> {nil, T};
decode_structured_data(<<$[, T/binary>>) -> decode_sd_id(T, <<>>).

decode_sd_id(<<$], T/binary>>, Acc) -> {Acc, [], T};
decode_sd_id(<<$\s, T/binary>>, Acc) ->
    {Params, T1} = decode_sd_params(T, []),
    {Acc, Params, T1}.

decode_sd_params(_, _) -> [].


decode_string(<<$\s, T/binary>>, Acc) -> {Acc, T};
decode_string(<<H, T/binary>>, Acc) -> decode_string(T, <<Acc/binary, H>>).

decode_severity(0) -> emerg;
decode_severity(1) -> alert;
decode_severity(2) -> crit;
decode_severity(3) -> err;
decode_severity(4) -> warning;
decode_severity(5) -> notice;
decode_severity(6) -> info;
decode_severity(7) ->  debug.

decode_facility(0) -> kern;
decode_facility(8) -> user;
decode_facility(16) -> mail;
decode_facility(24) -> daemon;
decode_facility(32) -> auth;
decode_facility(40) -> syslog;
decode_facility(48) -> lpr;
decode_facility(56) -> news;
decode_facility(64) -> uucp;
decode_facility(72) -> cron;
decode_facility(80) -> authpriv;
decode_facility(88) -> ftp;
decode_facility(96) -> ntp;
decode_facility(104) -> audit;
decode_facility(112) -> console;
decode_facility(120) -> cron2;
decode_facility(128) -> local0;
decode_facility(136) -> local1;
decode_facility(144) -> local2;
decode_facility(152) -> local3;
decode_facility(160) -> local4;
decode_facility(168) -> local5;
decode_facility(176) -> local6;
decode_facility(184) -> local7.

%% ===================================================================
%% Common parts
%% ===================================================================

parse_opts([], Rec) -> Rec;
parse_opts(Opts, Rec) -> lists:foldl(fun parse_opt/2, Rec, Opts).

parse_opt(binary, Opts) -> Opts#opts{return_type = binary};
parse_opt(iolist, Opts) -> Opts#opts{return_type = iolist};
parse_opt(list, Opts) -> Opts#opts{return_type = list};
parse_opt(_, Opts) -> erlang:error(badarg, Opts).
