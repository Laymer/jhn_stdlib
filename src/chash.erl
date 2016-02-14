-module(chash).

-export([jump/2]).

-define(KSTEP, 2862933555777941757).
-define(JSTEP, 2147483648.0).

jump(Key, Buckets) -> jump(0, undefined, Key, Buckets).

jump(J, B, _, Buckets) when J >= Buckets -> B;
jump(J, _, Key, Buckets) ->
    <<Key0:64>> = <<(Key * ?KSTEP):64>>,
    Key1 = Key0 + 1,
    J1 = trunc((J + 1) * (?JSTEP / float((Key1 bsr 33) + 1))),
    jump(J1, J, Key1, Buckets).
