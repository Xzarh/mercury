%-----------------------------------------------------------------------------%
% Copyright (C) 1999-2003 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%-----------------------------------------------------------------------------%
% File: declarative_debugger.m
% Author: Mark Brown
%
% This module has two main purposes:
% 	- to define the interface between the front and back ends of
% 	  a Mercury declarative debugger, and
% 	- to implement a front end.
%
% The interface is defined by a procedure that can be called from
% the back end to perform diagnosis, and a typeclass which represents
% a declarative view of execution used by the front end.
%
% The front end implemented in this module analyses the EDT it is
% passed to diagnose a bug.  It does this by a simple top-down search.
%
% Because Mercury modules are able to be compiled with different levels
% of tracing, the trace sequences generated by the back end, and passed
% to the front end as "annotated traces", can include or exclude certain
% types of events.  This front end is able to cope with some variation in
% the trace events produced, but there are some basic requirements on
% trace sequences which the back end must meet:
%
%	1) if there are any events from a certain class (e.g. interface
%	   events, negation events, disj events) then we require all events
%	   of that class;
%
%	2) if there are any disj events, we require all negation events
%	   and if-then-else events.
%
%-----------------------------------------------------------------------------%

:- module mdb__declarative_debugger.

:- interface.

:- import_module mdb__declarative_execution.
:- import_module mdb__io_action.
:- import_module mdbcomp__program_representation.

:- import_module io, bool, list, std_util, string.

	% This type represents the possible truth values for nodes
	% in the EDT.
	%
:- type decl_truth == bool.

	% This type represents the possible responses to being
	% asked to confirm that a node is a bug.
	%
:- type decl_confirmation
	--->	confirm_bug
	;	overrule_bug
	;	abort_diagnosis.

	% This type represents the bugs which can be diagnosed.
	% The parameter of the constructor is the type of EDT nodes.
	%
:- type decl_bug
			% An EDT whose root node is incorrect,
			% but whose children are all correct.
			%
	--->	e_bug(decl_e_bug)

			% An EDT whose root node is incorrect, and
			% which has no incorrect children but at
			% least one inadmissible one.
			%
	;	i_bug(decl_i_bug).

:- type decl_e_bug
	--->	incorrect_contour(
			final_decl_atom,% The head of the clause, in its
					% final state of instantiation.
			decl_contour,	% The path taken through the body.
			event_number	% The exit event.
		)
	;	partially_uncovered_atom(
			init_decl_atom,	% The called atom, in its initial
					% state.
			event_number	% The fail event.
		)
	;	unhandled_exception(
			init_decl_atom,	% The called atom, in its initial
					% state.
			decl_exception, % The exception thrown.
			event_number	% The excp event.
		).

:- type decl_i_bug
	--->	inadmissible_call(
			init_decl_atom,	% The parent atom, in its initial
					% state.
			decl_position,	% The location of the call in the
					% parent's body.
			init_decl_atom,	% The inadmissible child, in its
					% initial state.
			event_number	% The call event.
		).

	% XXX not yet implemented.
	%
:- type decl_contour == unit.
:- type decl_position == unit.

	% Values of the following two types represent questions from the
	% analyser to the oracle about some aspect of program behaviour,
	% and responses from the oracle, respectively.  In both cases the
	% type parameter is for the type of EDT nodes -- each question and
	% answer keeps a reference to the node which generated it, so that
	% the analyser is able to figure out what to do when the answer
	% arrives back from the oracle.
	%
:- type decl_question(T)
			% The node is a suspected wrong answer.  The first
			% argument is the EDT node the question came from.
			% The second argument is the atom in its final
			% state of instantiatedness (ie. at the EXIT event).
			%
	--->	wrong_answer(T, final_decl_atom)

			% The node is a suspected missing answer.  The
			% first argument is the EDT node the question came
			% from. The second argument is the atom in its
			% initial state of instantiatedness (ie. at the
			% CALL event), and the third argument is the list
			% of solutions.
			%
	;	missing_answer(T, init_decl_atom, list(final_decl_atom))

			% The node is a possibly unexpected exception.
			% The first argument is the EDT node the question
			% came from.  The second argument is the atom in
			% its initial state of instantiation, and the third
			% argument is the exception thrown.
			%
	;	unexpected_exception(T, init_decl_atom, decl_exception).

:- type decl_answer(T)
			% The oracle knows the truth value of this node.
			%
	--->	truth_value(T, decl_truth)

			% The oracle does not say anything about the truth
			% value, but is suspicious of the subterm at the
			% given term_path and arg_pos.
			%
	;	suspicious_subterm(T, arg_pos, term_path).

	% The evidence that a certain node is a bug.  This consists of the
	% smallest set of questions whose answers are sufficient to
	% diagnose that bug.
	%
:- type decl_evidence(T) == list(decl_question(T)).

	% Extract the EDT node from a question.
	%
:- func get_decl_question_node(decl_question(T)) = T.

:- type some_decl_atom
	--->	init(init_decl_atom)
	;	final(final_decl_atom).

:- type init_decl_atom
	--->	init_decl_atom(
			init_atom		:: trace_atom
		).

:- type final_decl_atom
	--->	final_decl_atom(
			final_atom		:: trace_atom,
			final_io_actions	:: list(io_action)
		).

:- type decl_exception == univ.

	% The diagnoser eventually responds with a value of this type
	% after it is called.
	%
:- type diagnoser_response

			% There was a bug found and confirmed.  The
			% event number is for a call port (inadmissible
			% call), an exit port (incorrect contour),
			% a fail port (partially uncovered atom),
			% or an exception port (unhandled exception).
			%
	--->	bug_found(event_number)

			% There was another symptom of incorrect behaviour
			% found; this symptom will be closer, in a sense,
			% to the location of a bug.
			%
	;	symptom_found(event_number)

			% There was no symptom found, or the diagnoser
			% aborted before finding a bug.
			%
	;	no_bug_found

			% The analyser requires the back end to reproduce
			% part of the annotated trace, with a greater
			% depth bound.  The event number and sequence
			% number are for the final event required (the
			% first event required is the call event with
			% the same sequence number).
			%
	;	require_subtree(event_number, sequence_number).

:- type diagnoser_state(R).

:- pred diagnoser_state_init(io_action_map::in, io__input_stream::in,
	io__output_stream::in, diagnoser_state(R)::out) is det.

:- pred diagnosis(S::in, R::in, int::in, int::in, int::in,
	diagnoser_response::out,
	diagnoser_state(R)::in, diagnoser_state(R)::out,
	io__state::di, io__state::uo) is cc_multi <= annotated_trace(S, R).

:- pred unravel_decl_atom(some_decl_atom::in, trace_atom::out,
	list(io_action)::out) is det.

%-----------------------------------------------------------------------------%

	% The diagnoser generates exceptions of the following type.
	%
:- type diagnoser_exception
	--->	internal_error(
			string,			% predicate/function name
			string			% error message
		)
	;	io_error(
			string,			% predicate/function name
			string			% error message
		)
	;	unimplemented_feature(
			string			% feature that is NYI
		).

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module mdb__declarative_analyser.
:- import_module mdb__declarative_oracle.
:- import_module mdb__declarative_tree.

:- import_module exception, int, map.

unravel_decl_atom(DeclAtom, TraceAtom, IoActions) :-
	(
		DeclAtom = init(init_decl_atom(TraceAtom)),
		IoActions = []
	;
		DeclAtom = final(final_decl_atom(TraceAtom, IoActions))
	).

get_decl_question_node(wrong_answer(Node, _)) = Node.
get_decl_question_node(missing_answer(Node, _, _)) = Node.
get_decl_question_node(unexpected_exception(Node, _, _)) = Node.

%-----------------------------------------------------------------------------%

:- type diagnoser_state(R)
	--->	diagnoser(
			analyser_state	:: analyser_state(edt_node(R)),
			oracle_state	:: oracle_state
		).

:- pred diagnoser_get_analyser(diagnoser_state(R),
		analyser_state(edt_node(R))).
:- mode diagnoser_get_analyser(in, out) is det.

diagnoser_get_analyser(diagnoser(Analyser, _), Analyser).

:- pred diagnoser_set_analyser(diagnoser_state(R), analyser_state(edt_node(R)),
		diagnoser_state(R)).
:- mode diagnoser_set_analyser(in, in, out) is det.

diagnoser_set_analyser(diagnoser(_, B), A, diagnoser(A, B)).

:- pred diagnoser_get_oracle(diagnoser_state(R), oracle_state).
:- mode diagnoser_get_oracle(in, out) is det.

diagnoser_get_oracle(diagnoser(_, Oracle), Oracle).

:- pred diagnoser_set_oracle(diagnoser_state(R), oracle_state,
		diagnoser_state(R)).
:- mode diagnoser_set_oracle(in, in, out) is det.

diagnoser_set_oracle(diagnoser(A, _), B, diagnoser(A, B)).

diagnoser_state_init(IoActionMap, InStr, OutStr, Diagnoser) :-
	analyser_state_init(IoActionMap, Analyser),
	oracle_state_init(InStr, OutStr, Oracle),
	Diagnoser = diagnoser(Analyser, Oracle).

diagnosis(Store, NodeId, UseOldIoActionMap, IoActionStart, IoActionEnd,
		Response, Diagnoser0, Diagnoser) -->
	( { UseOldIoActionMap > 0 } ->
		{ Diagnoser1 = Diagnoser0 }
	;
		make_io_action_map(IoActionStart, IoActionEnd, IoActionMap),
		{ Analyser0 = Diagnoser0 ^ analyser_state },
		{ analyser_state_replace_io_map(IoActionMap,
			Analyser0, Analyser1) },
		{ Diagnoser1 = Diagnoser0 ^ analyser_state := Analyser1 }
	),
	try_io(diagnosis_2(Store, NodeId, Diagnoser1), Result),
	(
		{ Result = succeeded({Response, Diagnoser}) }
	;
		{ Result = exception(UnivException) },
		(
			{ univ_to_type(UnivException, DiagnoserException) }
		->
			handle_diagnoser_exception(DiagnoserException,
				Response, Diagnoser1, Diagnoser)
		;
			{ rethrow(Result) }
		)
	).

:- pred diagnosis_2(S::in, R::in, diagnoser_state(R)::in,
	{diagnoser_response, diagnoser_state(R)}::out,
	io__state::di, io__state::uo) is cc_multi <= annotated_trace(S, R).

diagnosis_2(Store, NodeId, Diagnoser0, {Response, Diagnoser}) -->
	{ Analyser0 = Diagnoser0 ^ analyser_state },
	{ start_analysis(wrap(Store), dynamic(NodeId), AnalyserResponse,
		Analyser0, Analyser) },
	{ diagnoser_set_analyser(Diagnoser0, Analyser, Diagnoser1) },
	{ debug_analyser_state(Analyser, MaybeOrigin) },
	handle_analyser_response(Store, AnalyserResponse, MaybeOrigin,
		Response, Diagnoser1, Diagnoser).

:- pred handle_analyser_response(S::in, analyser_response(edt_node(R))::in,
	maybe(subterm_origin(edt_node(R)))::in, diagnoser_response::out,
	diagnoser_state(R)::in, diagnoser_state(R)::out,
	io__state::di, io__state::uo) is cc_multi <= annotated_trace(S, R).

handle_analyser_response(_, no_suspects, _, no_bug_found, D, D) -->
	io__write_string("No bug found.\n").

handle_analyser_response(Store, bug_found(Bug, Evidence), _, Response,
	Diagnoser0, Diagnoser) -->

	confirm_bug(Store, Bug, Evidence, Response, Diagnoser0, Diagnoser).

handle_analyser_response(Store, oracle_queries(Queries), MaybeOrigin, Response,
		Diagnoser0, Diagnoser) -->
	{ diagnoser_get_oracle(Diagnoser0, Oracle0) },
	debug_origin(Flag),
	(
		{ MaybeOrigin = yes(Origin) },
		{ Flag > 0 }
	->
		io__write_string("Origin: "),
		write_origin(wrap(Store), Origin),
		io__nl
	;
		[]
	),
	query_oracle(Queries, OracleResponse, Oracle0, Oracle),
	{ diagnoser_set_oracle(Diagnoser0, Oracle, Diagnoser1) },
	handle_oracle_response(Store, OracleResponse, Response, Diagnoser1,
			Diagnoser).

handle_analyser_response(Store, require_explicit(Tree), _, Response,
		Diagnoser, Diagnoser) -->
	{
		edt_subtree_details(Store, Tree, Event, Seqno),
		Response = require_subtree(Event, Seqno)
	}.

:- pred handle_oracle_response(S::in, oracle_response(edt_node(R))::in,
	diagnoser_response::out,
	diagnoser_state(R)::in, diagnoser_state(R)::out,
	io__state::di, io__state::uo) is cc_multi <= annotated_trace(S, R).

handle_oracle_response(Store, oracle_answers(Answers), Response, Diagnoser0,
		Diagnoser) -->
	{ diagnoser_get_analyser(Diagnoser0, Analyser0) },
	{ continue_analysis(wrap(Store), Answers, AnalyserResponse,
		Analyser0, Analyser) },
	{ diagnoser_set_analyser(Diagnoser0, Analyser, Diagnoser1) },
	{ debug_analyser_state(Analyser, MaybeOrigin) },
	handle_analyser_response(Store, AnalyserResponse, MaybeOrigin,
		Response, Diagnoser1, Diagnoser).

handle_oracle_response(_, no_oracle_answers, no_bug_found, D, D) -->
	[].

handle_oracle_response(Store, exit_diagnosis(Node), Response, D, D) -->
	{ edt_subtree_details(Store, Node, Event, _) },
	{ Response = symptom_found(Event) }.

handle_oracle_response(_, abort_diagnosis, no_bug_found, D, D) -->
	io__write_string("Diagnosis aborted.\n").

:- pred confirm_bug(S::in, decl_bug::in, decl_evidence(T)::in,
	diagnoser_response::out, diagnoser_state(R)::in,
	diagnoser_state(R)::out, io__state::di, io__state::uo) is cc_multi
	<= annotated_trace(S, R).

confirm_bug(Store, Bug, Evidence, Response, Diagnoser0, Diagnoser) -->
	{ diagnoser_get_oracle(Diagnoser0, Oracle0) },
	oracle_confirm_bug(Bug, Evidence, Confirmation, Oracle0, Oracle),
	{ diagnoser_set_oracle(Diagnoser0, Oracle, Diagnoser1) },
	(
		{ Confirmation = confirm_bug },
		{ decl_bug_get_event_number(Bug, Event) },
		{ Response = bug_found(Event) },
		{ Diagnoser = Diagnoser1 }
	;
		{ Confirmation = overrule_bug },
		overrule_bug(Store, Response, Diagnoser1, Diagnoser)
	;
		{ Confirmation = abort_diagnosis },
		{ Response = no_bug_found },
		{ Diagnoser = Diagnoser1 }
	).

:- pred overrule_bug(S::in, diagnoser_response::out, diagnoser_state(R)::in,
	diagnoser_state(R)::out, io__state::di, io__state::uo) is cc_multi
	<= annotated_trace(S, R).

overrule_bug(Store, Response, Diagnoser0, Diagnoser) -->
	{ Analyser0 = Diagnoser0 ^ analyser_state },
	{ revise_analysis(wrap(Store), AnalyserResponse, Analyser0, Analyser) },
	{ Diagnoser1 = Diagnoser0 ^ analyser_state := Analyser },
	{ debug_analyser_state(Analyser, MaybeOrigin) },
	handle_analyser_response(Store, AnalyserResponse, MaybeOrigin,
		Response, Diagnoser1, Diagnoser).

%-----------------------------------------------------------------------------%

	% Export a monomorphic version of diagnosis_state_init/4, to
	% make it easier to call from C code.
	%
:- pred diagnoser_state_init_store(io__input_stream, io__output_stream,
		diagnoser_state(trace_node_id)).
:- mode diagnoser_state_init_store(in, in, out) is det.

:- pragma export(diagnoser_state_init_store(in, in, out),
		"MR_DD_decl_diagnosis_state_init").

diagnoser_state_init_store(InStr, OutStr, Diagnoser) :-
	diagnoser_state_init(map__init, InStr, OutStr, Diagnoser).

	% Export a monomorphic version of diagnosis/10, to make it
	% easier to call from C code.
	%
:- pred diagnosis_store(trace_node_store::in, trace_node_id::in,
	int::in, int::in, int::in, diagnoser_response::out,
	diagnoser_state(trace_node_id)::in,
	diagnoser_state(trace_node_id)::out, io__state::di, io__state::uo)
	is cc_multi.

:- pragma export(diagnosis_store(in, in, in, in, in, out, in, out, di, uo),
		"MR_DD_decl_diagnosis").

diagnosis_store(Store, Node, UseOldIoActionMap, IoActionStart, IoActionEnd,
		Response, State0, State) -->
	diagnosis(Store, Node, UseOldIoActionMap, IoActionStart, IoActionEnd,
		Response, State0, State).

	% Export some predicates so that C code can interpret the
	% diagnoser response.
	%
:- pred diagnoser_bug_found(diagnoser_response, event_number).
:- mode diagnoser_bug_found(in, out) is semidet.

:- pragma export(diagnoser_bug_found(in, out), "MR_DD_diagnoser_bug_found").

diagnoser_bug_found(bug_found(Event), Event).

:- pred diagnoser_symptom_found(diagnoser_response, event_number).
:- mode diagnoser_symptom_found(in, out) is semidet.

:- pragma export(diagnoser_symptom_found(in, out),
	"MR_DD_diagnoser_symptom_found").

diagnoser_symptom_found(symptom_found(Event), Event).

:- pred diagnoser_no_bug_found(diagnoser_response).
:- mode diagnoser_no_bug_found(in) is semidet.

:- pragma export(diagnoser_no_bug_found(in), "MR_DD_diagnoser_no_bug_found").

diagnoser_no_bug_found(no_bug_found).

:- pred diagnoser_require_subtree(diagnoser_response, event_number,
		sequence_number).
:- mode diagnoser_require_subtree(in, out, out) is semidet.

:- pragma export(diagnoser_require_subtree(in, out, out),
		"MR_DD_diagnoser_require_subtree").

diagnoser_require_subtree(require_subtree(Event, SeqNo), Event, SeqNo).

%-----------------------------------------------------------------------------%

:- pred handle_diagnoser_exception(diagnoser_exception::in,
	diagnoser_response::out, diagnoser_state(R)::in,
	diagnoser_state(R)::out, io__state::di, io__state::uo) is det.

handle_diagnoser_exception(internal_error(Loc, Msg), Response, D, D) -->
	io__stderr_stream(StdErr),
	io__write_strings(StdErr, [
		"An internal error has occurred; diagnosis will be aborted.  Debugging\n",
		"message follows:\n",
		Loc, ": ", Msg, "\n",
		"Please report bugs to mercury-bugs@cs.mu.oz.au.\n"]),
	{ Response = no_bug_found }.

handle_diagnoser_exception(io_error(Loc, Msg), Response, D, D) -->
	io__stderr_stream(StdErr),
	io__write_strings(StdErr, [
		"I/O error: ", Loc, ": ", Msg, ".\n",
		"Diagnosis will be aborted.\n"]),
	{ Response = no_bug_found }.

handle_diagnoser_exception(unimplemented_feature(Feature), Response, D, D) -->
	io__write_strings([
		"Sorry, the diagnosis cannot continue because it requires support for\n",
		"the following: ", Feature, ".\n",
		"The debugger is a work in progress, and this is not supported in the\n",
		"current version.\n"]),
	{ Response = no_bug_found }.

%-----------------------------------------------------------------------------%

:- pred decl_bug_get_event_number(decl_bug, event_number).
:- mode decl_bug_get_event_number(in, out) is det.

decl_bug_get_event_number(e_bug(EBug), Event) :-
	(
		EBug = incorrect_contour(_, _, Event)
	;
		EBug = partially_uncovered_atom(_, Event)
	;
		EBug = unhandled_exception(_, _, Event)
	).
decl_bug_get_event_number(i_bug(IBug), Event) :-
	IBug = inadmissible_call(_, _, _, Event).

%-----------------------------------------------------------------------------%

:- pred write_origin(wrap(S)::in, subterm_origin(edt_node(R))::in,
	io__state::di, io__state::uo) is det <= annotated_trace(S, R).

write_origin(wrap(Store), Origin) -->
	( { Origin = output(dynamic(NodeId), ArgPos, TermPath) } ->
		{ exit_node_from_id(Store, NodeId, ExitNode) },
		{ ProcName = ExitNode ^ exit_atom ^ proc_name },
		io__write_string("output("),
		io__write_string(ProcName),
		io__write_string(", "),
		io__write(ArgPos),
		io__write_string(", "),
		io__write(TermPath),
		io__write_string(")")
	;
		io__write(Origin)
	).

:- pragma foreign_code("C",
"

/*
** The declarative debugger will print diagnostic information about the origins
** computed by dependency tracking if this flag has a positive value.
*/

int	MR_DD_debug_origin = 0;

").

:- pragma foreign_decl("C",
"
extern	int	MR_DD_debug_origin;
").

:- pred debug_origin(int::out, io__state::di, io__state::uo) is det.

:- pragma foreign_proc("C",
	debug_origin(Flag::out, IO0::di, IO::uo),
	[will_not_call_mercury, promise_pure, tabled_for_io],
"
	Flag = MR_DD_debug_origin;
	IO = IO0;
").
debug_origin(_) -->
	{ private_builtin__sorry("declarative_debugger.debug_origin") }.
