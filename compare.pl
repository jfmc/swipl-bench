/*  Part of SWI-Prolog

    Author:        Jan Wielemaker
    E-mail:        jan@swi-prolog.org
    WWW:           http://www.swi-prolog.org
    Copyright (c)  2023, SWI-Prolog Solutions b.v.
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:

    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in
       the documentation and/or other materials provided with the
       distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
    COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
*/

:- module(compare,
          []).
:- use_module(library(strings)).
:- use_module(library(apply)).
:- use_module(library(main)).
:- use_module(library(option)).
:- use_module(library(process)).
:- use_module(library(csv)).
:- use_module(library(lists)).
:- use_module(library(pairs)).
:- use_module(library(solution_sequences)).
:- use_module(library(dcg/basics)).
:- use_module(library(error)).

:- meta_predicate
    progress(0, +, +, +).

/** <module> Compare multiple Prolog systems
*/

:- initialization(main, main).

main(Argv) :-
    argv_options(Argv, Systems, Options),
    bench(Systems, Options).

bench(_Systems, Options) :-
    option(list(true), Options),
    !,
    list_systems.
bench([], _Options) :-
    !,
    argv_usage(debug).
bench(Systems, Options) :-
    maplist(known_system(Options), Systems),
    maplist(prepare_system(Options), Systems),
    maplist(bench_system(Options), Systems, CSVFiles),
    csv_file(all, CSVOut, Options),
    csv_join(CSVOut, CSVFiles, Systems),
    option(output(OutFile), Options, 'bench.svg'),
    plot(CSVOut, Systems, OutFile, Options).

opt_type(speedup,  speedup,  number).
opt_type(s,        speedup,  number).
opt_type(verbose,  verbose,  boolean).
opt_type(v,        verbose,  boolean).
opt_type(quiet,    quiet,    boolean).
opt_type(q,        quiet,    boolean).
opt_type(list,     list,     boolean).
opt_type(l,        list,     boolean).
opt_type(output,   output,   file(write)).
opt_type(o,        output,   file(write)).
opt_type(tmp,      data_dir, directory).

opt_help(speedup,     "Run tests N times faster").
opt_help(verbose,     "Make stderr of process visible").
opt_help(quiet,       "No progress messages").
opt_help(list,        "List supported Prolog systems").
opt_help(output,      "File for (SVG) final chart (default `bench.svg`)").
opt_help(data_dir,    "Directory for intermediate files (default `data`)").
opt_help(help(usage), " [option ...] [system ...]").

opt_meta(speedup, 'SPEEDUP').

known_system(_Options, System) :-
    system(System),
    !.
known_system(_, System) :-
    existence_error(system, System).


system(Sys) :-
    clause(system(Sys, _Label, _Exe, _Speedup, _Argv, _Opts, _Input), _).

system_property(Sys, exe(Exe)) =>
    clause(system(Sys, _Label, Exe, _Speedup, _Argv, _Opts, _Input), _).
system_property(Sys, label(Label)) =>
    clause(system(Sys, Label0, _Exe, _Speedup, _Argv, _Opts, _Input), _),
    prolog_version(Sys, Version),
    interpolate_string(Label0, Label, ['Version'=Version], []).

%!  system(+Id, -Label, -Exe, +Speedup, -Argv, -Options, -Script) is det.

system(swi,
       'SWI-Prolog (-O,PGO) {Version}',
       path(swipl),
       Speedup,
       ['-O', 'run.pl', '--csv', '--speedup', Speedup],
       [],
       "").
system('swi-no-pgo',
       'SWI-Prolog (-O,no PGO) {Version}',
       '../linux/src/swipl',
       Speedup,
       ['-O', 'run.pl', '--csv', '--speedup', Speedup],
       [],
       "").
system('swi-no-O',
       'SWI-Prolog (PGO), {Version}',
       path(swipl),
       Speedup,
       ['run.pl', '--csv', '--speedup', Speedup],
       [],
       "").
system(gprolog,
       'GNU-Prolog {Version}',
       path(gprolog),
       Speedup,
       ['--quiet', '--consult-file', 'port/run/gprolog.pl',
        '--entry-goal', Goal, '--entry-goal', halt],
       [],
       "") :-
    Factor is 1.0/Speedup,
    format(string(Goal), '~q', [run(Factor)]).
system(yap,
       'YAP {Version}',
       path(yap),
       Speedup,
       ['-l', 'run.pl', '-g', Goal],
       [],
       "") :-
    Factor is 1.0/Speedup,
    format(string(Goal), '~q', [(run(Factor,csv),halt)]).
system(sicstus,
       'SICStus {Version}',
       path(sicstus),
       Speedup,
       ['-l', 'run.pl'],
       [],
       Script
      ) :-
    Factor is 1.0/Speedup,
    Script = {|string(Factor)||
              | run({Factor},csv).
              | halt.
              |}.
system(scryer,
       'Scryer Prolog {Version}',
       path('scryer-prolog'),
       Speedup,
       ['port/run/scryer.pl', '-g', Goal, '-g', halt],
       [],
       ""
      ) :-
    Factor is 1.0/Speedup,
    format(string(Goal), '~q', [run(Factor)]).
system(xsb,
       'XSB {Version}',
       path('xsb'),
       Speedup,
       ['--nobanner', '--quietload', '--noprompt'],
       [],
       Script
      ) :-
    Factor is 1.0/Speedup,
    Script = {|string(Factor)||
              | add_lib_dir('port/programs/xsb').
              | ['port/run/xsb'].
              | run({Factor}).
              |}.
system(trealla,
       'Trealla Prolog {Version}',
       path(tpl),
       Speedup,
       [ '-g', Goal, '-l', 'include_all.pl' ],
       [ cwd('port/programs/trealla') ],
       "") :-
    Factor is 1.0/Speedup,
    format(string(Goal), '~q', [(run(Factor),halt)]).

bench_system(Options, System, CSVOut) :-
    progress(bench_system_(Options, System, CSVOut),
             "Running benchmarks for \"~w\"", [System],
             Options).

bench_system_(Options, System, CSVOut) :-
    csv_file(System, CSVOut, Options),
    option(speedup(Speedup), Options, 1),
    system(System, _Label, Exe, Speedup, Argv, CreaeteOpts, Script),
    (   Script == ""
    ->  Stdin = std
    ;   Stdin = pipe(In)
    ),
    (   option(verbose(true), Options)
    ->  Stderr = std
    ;   Stderr = pipe(Error)
    ),
    process_create(Exe, Argv,
                   [ stdin(Stdin),
                     stdout(pipe(Out)),
                     stderr(Stderr),
                     process(PID)
                   | CreaeteOpts
                   ]),
    (   var(In)
    ->  true
    ;   thread_create(call_cleanup(write(In, Script), close(In)), TID1)
    ),
    thread_create(to_file(CSVOut, Out), TID2),
    (   nonvar(Error)
    ->  call_cleanup(
            read_string(Error, _, ErrorString),
            close(Error))
    ;   ErrorString = ""
    ),
    process_wait(PID, Status),
    (   nonvar(TID1)
    ->  thread_join(TID1)
    ;   true
    ),
    thread_join(TID2),
    report_failure(Status, System, ErrorString).

to_file(File, Stream) :-
    call_cleanup(
        setup_call_cleanup(
            open(File, write, Out),
            copy_lines(Stream, Out),
            close(Out)),
        close(Stream)).

copy_lines(In, Out) :-
    read_line_to_string(In, Line),
    (   Line == end_of_file
    ->  true
    ;   mask_line(Line)
    ->  copy_lines(In, Out)
    ;   format(Out, '~s~n', [Line]),
        copy_lines(In, Out)
    ).

mask_line("yes").                       % XSB cannot suppress this

report_failure(exit(0), _, _) :-
    !.
report_failure(Status, System, ErrorString) :-
    print_message(error, bench_failed(System, Status, ErrorString)),
    fail.

csv_file(System, File, Options) :-
    option(data_dir(Dir), Options, 'data'),
    ensure_directory(Dir),
    file_name_extension(System, csv, CSVFile),
    directory_file_path(Dir, CSVFile, File).

		 /*******************************
		 *            VERSION		*
		 *******************************/

list_systems :-
    forall(system(System), list(System)).

list(System) :-
    (   prolog_version(System, Version)
    ->  true
    ;   Version = '?'
    ),
    format('~w~t~w~30|~n', [System, Version]).

%!  prolog_version(+System, -Version) is semidet.
%
%   Try to get the version of the system by running it with `--version`.
%   May need specialized implementations for new Prolog systems

prolog_version(System, Version) :-
    system(System, _Label, Exe, 1, _Argv, _Opts, _Script),
    process_create(Exe, ['--version'],
                   [ stdin(null),
                     stdout(pipe(Out)),
                     stderr(pipe(Err))
                   ]),
    read_string(Out, _, Stdout),
    close(Out),
    read_string(Err, _, Stderr),
    close(Err),
    (   member(String, [Stdout, Stderr]),
        string_codes(String, Codes),
        phrase(version(Version), Codes, _)
    ->  true
    ).

version(Version) -->
    string(_),
    integer(Major), ".", integer(Minor), ".", integer(Patch),
    !,
    { atomic_list_concat([Major,Minor,Patch], '.', Version) }.
version(Version) -->
    string(_),
    integer(Major), ".", integer(Minor),
    !,
    { atomic_list_concat([Major,Minor], '.', Version) }.




		 /*******************************
		 *            PREPARE		*
		 *******************************/

prepare_system(Options, System) :-
    format(string(File), 'port/programs/~w/include_all.pl', [System]),
    exists_file(File),
    progress("Using existing prepared files for \"~w\"", System, Options),
    !.
prepare_system(Options, System) :-
    exists_source(port/prepare/System),
    !,
    use_module(port/prepare/System),
    progress(System:prepare(Options),
             "Preparing scripts for \"~w\"", System, Options).
prepare_system(_, _).



		 /*******************************
		 *            JOIN CSV		*
		 *******************************/

csv_join(Out, Files, Options) :-
    progress(csv_join(Out, Files),
             "Joining CSV data into file \"~w\"", [Out],
             Options).

csv_join(Out, Files) :-
    maplist(system, Files, Systems),
    maplist(csv_read_file, Files, Data),
    pairs_keys_values(Pairs, Systems, Data),
    findall(P, distinct(P, program(Data, P)), Programs),
    maplist(make_row(Systems, Pairs), Programs, Rows),
    maplist(system_label, Systems, Labels),
    Hdr =.. [row, program | Labels],
    csv_write_file(Out, [Hdr|Rows], [separator(0'|)]).

system(File, System) :-
    file_base_name(File, Plain),
    file_name_extension(System, _, Plain).

program(Data, P) :-
    member(System, Data),
    member(row(P, _, _), System),
    P \== program.

system_label(System, Label) :-
    system_property(System, label(Label)).

make_row(Systems, Pairs, Program, Row) :-
    maplist(system_time(Program, Pairs), Systems, SysTimes),
    Row =.. [row, Program | SysTimes].

system_time(Program, Pairs, System, Time) :-
    memberchk(System-Data, Pairs),
    (   memberchk(row(Program, UTime, GC), Data)
    ->  Time is UTime+GC
    ;   Time = (-)
    ).

		 /*******************************
		 *             PLOT		*
		 *******************************/

plot(Input, Systems, Output, Options) :-
    progress(plot_(Input, Systems, Output, Options),
             "Generating chart using gnuplot (~w)", [Output],
             Options).

plot_(Input, Systems, Output, _Options) :-
    length(Systems, NSys),
    MaxCol is NSys + 1,
    phrase(ti_cols(3, MaxCol), String),
    string_codes(TiCols, String),
    process_create(path(gnuplot), [],
                   [ stdin(pipe(Stdin))
                   ]),
    Script = {|string(Input,Output,TiCols)||
set term svg
set output "{Output}"

set datafile separator '|'
set boxwidth 0.9 absolute
set style fill solid 1.00 border lt -1
set key fixed right top vertical Right noreverse noenhanced autotitle nobox
set style histogram clustered gap 2 title textcolor lt -1
set datafile missing '-'
set style data histograms
set xtics border in scale 0,0 nomirror rotate by -45 autojustify noenhanced
set xtics norangelimit
set xtics ()
set title "Prolog benchmark suite from https://github.com/SWI-Prolog/bench.git"
set colorbox vertical origin screen 0.9, 0.2 size screen 0.05, 0.6 front noinvert bdefault
set yrange [0:*]
set linetype 1 lc rgb "red"
set linetype 2 lc rgb "green"
set linetype 3 lc rgb "blue"

plot '{Input}' using 2:xtic(1) ti col{TiCols}
             |},
    call_cleanup(write(Stdin, Script),
                 close(Stdin)).

ti_cols(Col, Max) -->
    { Col =< Max },
    !,
    ", '' u ", number(Col), " ti col",
    { Col2 is Col+1 },
    ti_cols(Col2, Max).
ti_cols(_,_) -->
    "".


		 /*******************************
		 *            PROGRESS		*
		 *******************************/

progress(Fmt, Args, Options) :-
    option(quiet(false), Options, false),
    !,
    print_message(informational, format(Fmt, Args)).
progress(_,_,_).

progress(Goal, Fmt, Args, Options) :-
    option(quiet(false), Options, false),
    !,
    print_message(informational, progress_start(Fmt, Args)),
    (   catch(call_time(Goal, Time), Error, true)
    ->  (   var(Error)
        ->  print_message(informational, progress_end(true(Time)))
        ;   print_message(error, progress_end(Error)),
            throw(Error)
        )
    ;   print_message(error, progress_end(false)),
        fail
    ).

		 /*******************************
		 *            MESSAGES		*
		 *******************************/

:- multifile prolog:message//1.

prolog:message(bench_failed(System, Status, ErrorString)) -->
    [ 'Benchmark run for "~w" failed with ~p:'-[System, Status], nl,
      '~w'-[ErrorString]
    ].
prolog:message(progress_start(Fmt, Args)) -->
    [ Fmt-Args, ' ...', flush ].
prolog:message(progress_end(true(Time))) -->
    [ at_same_line, ' done (~1f sec)'-Time.wall ].
prolog:message(progress_end(false)) -->
    [ at_same_line, ' FAILED' ].
prolog:message(progress_end(Error)) -->
    [ at_same_line, ' ERROR:', nl ],
    prolog:translate_message(Error).
