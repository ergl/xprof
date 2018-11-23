-module(xprof_core_cmd_funlatency).

-export([mandatory_params/0,
         optional_params/0,
         param_from_ast/2,
         param_to_internal/2,
         format_error/1,

         get_cmd_id/1,

         %% tracer callbacks
         init/2,
         handle_event/3,
         take_snapshot/1
        ]).

mandatory_params() ->
    [mfa].

optional_params() ->
    [retmatch].

param_from_ast(mfa, MfaStr) when is_list(MfaStr) ->
    {ok, MfaStr};
param_from_ast(mfa, _WrongValue) ->
    {error, wrong_value};
param_from_ast(retmatch, RetMatchAst) ->
    case RetMatchAst of
        {'fun', _Loc, _Clauses} ->
            xprof_core_query:param_to_fun(RetMatchAst);
        Pattern ->
            Loc = element(2, Pattern),
            %% fun(Pattern) -> true;(_) -> false
            Fun = {'fun', Loc,
                   {clauses,
                    [{clause, Loc, [Pattern], [], [{atom, Loc, true}]},
                     {clause, Loc, [{var, Loc, '_'}], [], [{atom, Loc, false}]}
                    ]}},
            xprof_core_query:param_to_fun(Fun)
    end;
param_from_ast(_, _) ->
    {error, unknown_param}.

param_to_internal(mfa, Value) ->
    xprof_core_ms:fun2ms(Value);
param_to_internal(retmatch, Fun) ->
    if is_function(Fun, 1) -> {ok, Fun};
       is_function(Fun, 2) -> {ok, {exception_from, Fun}};
       is_function(Fun) -> {error, wrong_arity};
       true -> {error, not_fun}
    end;
param_to_internal(_, _) ->
   {error, unknown_param}.

format_error(not_fun) ->
    "Must be a fun of arity 1 or 2";
format_error(wrong_arity) ->
    "Must be a fun of arity 1 or 2";
format_error(Str) when is_list(Str) ->
    %% already formatted error from `fun2ms'
    Str.

get_cmd_id(Options) ->
    MFASpec = proplists:get_value(mfa, Options),
    MFAId = xprof_core_lib:mfaspec2id(MFASpec),
    MFAId.

%% tracer

%% The largest duration value that can be stored in the HDR histogram in ms
-define(MAX_DURATION, 30*1000).

-record(state, {hdr_ref,
                max_duration,
                ignore_recursion,
                retmatch,
                nomatch_count :: non_neg_integer() | undefined
               }).

init(Options, _MFASpec) ->
    MaxDuration = application:get_env(xprof, max_duration, ?MAX_DURATION) * 1000,
    IgnoreRecursion = application:get_env(xprof, ignore_recursion, true),
    RetMatchFun = proplists:get_value(retmatch, Options),
    NoMatch = case RetMatchFun of
                  undefined -> undefined;
                  _ -> 0
              end,
    {ok, HDR} = hdr_histogram:open(MaxDuration, 3),
    {ok, #state{hdr_ref = HDR,
                max_duration = MaxDuration,
                ignore_recursion = IgnoreRecursion,
                retmatch = RetMatchFun,
                nomatch_count = NoMatch}}.

handle_event({trace_ts, Pid, call, _MFA, Args, StartTime}, _, State) ->
    put_ts_args(Pid, StartTime, Args, State#state.ignore_recursion),
    ok;
handle_event({trace_ts, Pid, Tag, MFA, RetOrExc, EndTime},
             CaptureThreshold,
             State = #state{hdr_ref = Ref,
                            max_duration = MaxDuration})
  when Tag =:= return_from;
       Tag =:= exception_from ->

    case get_ts_args(Pid, State#state.ignore_recursion) of
        undefined ->
            ok;
        {StartTime, Args} ->
            case matching_parsing(State#state.retmatch, Tag, RetOrExc) of
                false ->
                    {ok, State#state{nomatch_count = State#state.nomatch_count + 1}};
                {true, NewRet} ->
                    CallTime = timer:now_diff(EndTime, StartTime),
                    if CallTime > MaxDuration ->
                            lager:error("Call ~p took ~p ms that is larger than the maximum "
                                        "that can be stored (~p ms)",
                                        [MFA, CallTime/1000, MaxDuration div 1000]),
                            ok = hdr_histogram:record(Ref, MaxDuration);
                       true ->
                            ok = hdr_histogram:record(Ref, CallTime)
                    end,

                    maybe_capture({Pid, CallTime, Args, {Tag, NewRet}},
                                  CaptureThreshold, State)
            end
    end.

take_snapshot(State = #state{hdr_ref = Ref, nomatch_count = NoMatch}) ->
    Snapshot = get_current_hist_stats(Ref, NoMatch),
    hdr_histogram:reset(Ref),
    maybe_reset_nomatch_count(Snapshot, State, NoMatch).

maybe_reset_nomatch_count(Snapshot, _State, _NoMatch = undefined) ->
    Snapshot;
maybe_reset_nomatch_count(Snapshot, State, _) ->
    {Snapshot, State#state{nomatch_count = 0}}.


%% helpers for tracer callbacks

put_ts_args(Pid, StartTime, Args, IgnoreRecursion) ->
    %% Count the depth of recursion in this process
    CD = case get({Pid, call_depth}) of
             undefined -> 1;
             CallDepth -> CallDepth + 1
         end,
    put({Pid, call_depth}, CD),
    case CD =:= 1 orelse not IgnoreRecursion of
        true ->
            put({Pid, CD, ts_args}, {StartTime, Args});
        false ->
            ok
    end.

%% @doc If IgnoreRecursion is true only return start time and args
%% of the outermost call
get_ts_args(Pid, IgnoreRecursion) ->
    case get({Pid, call_depth}) of
        undefined ->
            %% we missed the call of this function
            undefined;
        1 ->
            erase({Pid, call_depth}),
            erase({Pid, 1, ts_args});
        CD when CD > 1 ->
            put({Pid, call_depth}, CD - 1),
            case IgnoreRecursion of
                false ->
                    erase({Pid, CD, ts_args});
                true ->
                    undefined
            end
    end.

-spec matching_parsing(fun() | {exception_from, fun()} | undefined,
                       return_from | exception_from, any()) ->
    false | {true, NewRet :: any()}.
matching_parsing(undefined, _, RetOrExc) ->
    {true, RetOrExc};
matching_parsing({exception_from, RetMatch}, exception_from, {Class, Reason} = Error) ->
    try RetMatch(Class, Reason) of
        false -> false;
        true -> {true, Error};
        {true, NewValue} -> {true, NewValue};
        _ -> false
    catch _:_ ->
            false
    end;
matching_parsing({exception_from, _}, _, _) ->
    false;
matching_parsing(RetMatch, _, RetOrExc) ->
    try RetMatch(RetOrExc) of
        false -> false;
        true -> {true, RetOrExc};
        {true, NewValue} -> {true, NewValue};
        _ -> false
    catch _:_ ->
            false
    end.

maybe_capture(_, _Threshold = undefined, _State) ->
    ok;
maybe_capture({_Pid, CallTime, Args, _Res} = Item, Threshold, _State) ->
    case Threshold of
        _ when CallTime > Threshold * 1000 andalso
               Args =/= arity ->
            {capture, Item};
        _ ->
            ok
    end.

get_current_hist_stats(HistRef, NoMatch) ->
    Count = hdr_histogram:get_total_count(HistRef),
    TotalCountAndRate =
        case NoMatch of
            undefined ->
                [];
            _ ->
                TotalCount = Count + NoMatch,
                [{total_count, TotalCount},
                 {match_rate, percent(Count, TotalCount)}]
        end,
    [{min,         hdr_histogram:min(HistRef)},
     {mean,        hdr_histogram:mean(HistRef)},
     %%{median,      hdr_histogram:median(HistRef)},
     {max,         hdr_histogram:max(HistRef)},
     %%{stddev,      hdr_histogram:stddev(HistRef)},
     %%{p25,         hdr_histogram:percentile(HistRef,25.0)},
     {p50,         hdr_histogram:percentile(HistRef,50.0)},
     {p75,         hdr_histogram:percentile(HistRef,75.0)},
     {p90,         hdr_histogram:percentile(HistRef,90.0)},
     {p99,         hdr_histogram:percentile(HistRef,99.0)},
     %%{p9999999,    hdr_histogram:percentile(HistRef,99.9999)},
     %%{memsize,     hdr_histogram:get_memory_size(HistRef)},
     {count,       Count}
     |TotalCountAndRate].

percent(_, 0) ->
    0;
percent(Count, TotalCount) ->
    100 * Count / TotalCount.
