%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%
%
%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- module unify_gen.

:- interface.

:- import_module list, hlds, llds, code_info, code_util.

	% Generate code for an assignment unification.
	% (currently implemented as a cached assignment).
:- pred unify_gen__generate_assignment(var, var, code_tree,
							code_info, code_info).
:- mode unify_gen__generate_assignment(in, in, out, in, out) is det.

	% Generate a construction unification
:- pred unify_gen__generate_construction(var, cons_id,
				list(var), list(uni_mode),
					code_tree, code_info, code_info).
:- mode unify_gen__generate_construction(in, in, in, in, out, in, out) is det.

:- pred unify_gen__generate_det_deconstruction(var, cons_id,
				list(var), list(uni_mode),
					code_tree, code_info, code_info).
:- mode unify_gen__generate_det_deconstruction(in, in, in, in, out,
							in, out) is det.

:- pred unify_gen__generate_semi_deconstruction(var, cons_id,
				list(var), list(uni_mode),
					code_tree, code_info, code_info).
:- mode unify_gen__generate_semi_deconstruction(in, in, in, in, out,
							in, out) is det.

:- pred unify_gen__generate_test(var, var, code_tree, code_info, code_info).
:- mode unify_gen__generate_test(in, in, out, in, out) is det.

:- pred unify_gen__generate_tag_test(var, cons_id, code_tree,
						code_info, code_info).
:- mode unify_gen__generate_tag_test(in, in, out, in, out) is det.

:- pred unify_gen__generate_tag_rval(var, cons_id, rval, code_tree,
						code_info, code_info).
:- mode unify_gen__generate_tag_rval(in, in, out, out, in, out) is det.

%---------------------------------------------------------------------------%
:- implementation.

:- import_module tree, int, map, require, std_util.
:- import_module prog_io, mode_util.

:- type uni_val		--->	ref(var)
			;	lval(lval).

%---------------------------------------------------------------------------%

	% assignment unifications are generated by simply caching the
	% bound variable as the expression that generates the free
	% variable. No immediate code is generated.

unify_gen__generate_assignment(VarA, VarB, empty) -->
	(
		code_info__variable_is_live(VarA)
	->
		code_info__cache_expression(VarA, var(VarB))
	;
		{ true }
	).

%---------------------------------------------------------------------------%

	% A [simple] test unification is generated by flushing both
	% variables from the cache, and producing code that branches
	% to the fall-through point if the two values are not the same.
	% Simple tests are in-in unifications on enumerations, integers,
	% strings and floats. XXX handle strings and floats.

unify_gen__generate_test(VarA, VarB, Code) -->
	code_info__flush_variable(VarA, Code0),
	code_info__get_variable_register(VarA, RegA),
	code_info__flush_variable(VarB, Code1),
	code_info__get_variable_register(VarB, RegB),
	{ CodeA = tree(Code0, Code1) },
	code_info__generate_test_and_fail(
			binop(eq, lval(RegA), lval(RegB)), FailCode),
	{ Code = tree(CodeA, FailCode) }.

%---------------------------------------------------------------------------%

unify_gen__generate_tag_test(Var, ConsId, Code) -->
        code_info__flush_variable(Var, VarCode),
	code_info__get_variable_register(Var, Lval),
	code_info__cons_id_to_tag(Var, ConsId, Tag),
	unify_gen__generate_tag_test_2(Tag, Lval, TestCode),
	{ Code = tree(VarCode, TestCode) }.

:- pred unify_gen__generate_tag_test_2(cons_tag, lval, code_tree,
							code_info, code_info).
:- mode unify_gen__generate_tag_test_2(in, in, out, in, out) is det.

unify_gen__generate_tag_test_2(string_constant(String), Lval, TestCode) -->
	code_info__generate_test_and_fail(
				binop(streq, lval(Lval), sconst(String)),
								TestCode).
unify_gen__generate_tag_test_2(float_constant(_String), _, _) -->
	{ error("Float tests unimplemented") }.
unify_gen__generate_tag_test_2(int_constant(Int), Lval, TestCode) -->
	code_info__generate_test_and_fail(
				binop(eq,lval(Lval), iconst(Int)),
								TestCode).
unify_gen__generate_tag_test_2(simple_tag(SimpleTag), Lval, TestCode) -->
	code_info__generate_test_and_fail(
			binop(eq,tag(lval(Lval)), mktag(iconst(SimpleTag))),
								TestCode).
unify_gen__generate_tag_test_2(complicated_tag(Bits, Num), Lval, TestCode) -->
	code_info__generate_test_and_fail(
			binop(eq,tag(lval(Lval)), mktag(iconst(Bits))), Test1),
	code_info__generate_test_and_fail(
			binop(eq,field(Bits, lval(Lval), 0), iconst(Num)),
									Test2),
	{ TestCode = tree(Test1, Test2) }.
unify_gen__generate_tag_test_2(complicated_constant_tag(Bits, Num), Lval,
		TestCode) -->
	code_info__generate_test_and_fail(
		binop(eq, lval(Lval), mkword(Bits, mkbody(iconst(Num)))),
								TestCode).

%---------------------------------------------------------------------------%

unify_gen__generate_tag_rval(Var, ConsId, Rval, Code) -->
        code_info__flush_variable(Var, Code),
	code_info__get_variable_register(Var, Lval),
	code_info__cons_id_to_tag(Var, ConsId, Tag),
	{ unify_gen__generate_tag_rval_2(Tag, Lval, Rval) }.

:- pred unify_gen__generate_tag_rval_2(cons_tag, lval, rval).
:- mode unify_gen__generate_tag_rval_2(in, in, out) is det.

unify_gen__generate_tag_rval_2(string_constant(String), Lval, Rval) :-
	Rval = binop(streq, lval(Lval), sconst(String)).
unify_gen__generate_tag_rval_2(float_constant(_String), _, _) :-
	error("Float tests unimplemented").
unify_gen__generate_tag_rval_2(int_constant(Int), Lval, Rval) :-
	Rval = binop(eq,lval(Lval), iconst(Int)).
unify_gen__generate_tag_rval_2(simple_tag(SimpleTag), Lval, Rval) :-
	Rval = binop(eq,tag(lval(Lval)), mktag(iconst(SimpleTag))).
unify_gen__generate_tag_rval_2(complicated_tag(Bits, Num), Lval, Rval) :-
	Rval = binop(and, binop(eq,tag(lval(Lval)), mktag(iconst(Bits))), 
			binop(eq,field(Bits, lval(Lval), 0), iconst(Num))).
unify_gen__generate_tag_rval_2(complicated_constant_tag(Bits, Num), Lval,
		Rval) :-
	Rval = binop(eq, lval(Lval), mkword(Bits, mkbody(iconst(Num)))).

%---------------------------------------------------------------------------%

	% A construction unification consists of a heap-increment to
	% create a term, and a series of [optional] assignments to
	% instansiate the arguments of that term. XXX Need to handle
	% strings, etc.

	% The current implementation generates the construction
	% in an eager manner.

unify_gen__generate_construction(Var, Cons, Args, Modes, Code) -->
	code_info__cons_id_to_tag(Var, Cons, Tag),
	(
		{ Tag = string_constant(String) }
	->
		{ Code = empty },
		code_info__cache_expression(Var, sconst(String))
	;
		{ Tag = int_constant(Int) }
	->
		{ Code = empty },
		code_info__cache_expression(Var, iconst(Int))
	;
		{ Tag = float_constant(_Float) }
	->
		{ error("Float constructions unimplemented") }
	;
		{ Tag = simple_tag(SimpleTag) }
	->
		{ unify_gen__generate_cons_args(Args, RVals) },
		code_info__cache_expression(Var, create(SimpleTag, RVals)),
		code_info__flush_variable(Var, CodeA),
		code_info__get_variable_register(Var, Lval),
		{ unify_gen__make_fields_and_argvars(Args, Lval, 0, SimpleTag,
							Fields, ArgVars) },
		unify_gen__generate_det_unify_args(Fields, ArgVars,
								Modes, CodeB),
		{ Code = tree(CodeA, CodeB) }
	;
		{ Tag = complicated_tag(Bits0, Num0) }
	->
		{ unify_gen__generate_cons_args(Args, RVals0) },
		{ RVals = [iconst(Num0)|RVals0] },
		code_info__cache_expression(Var, create(Bits0, RVals)),
		code_info__flush_variable(Var, CodeA),
		code_info__get_variable_register(Var, Lval),
		{ unify_gen__make_fields_and_argvars(Args, Lval, 1,
						Bits0, Fields, ArgVars) },
		unify_gen__generate_det_unify_args(Fields, ArgVars,
								Modes, CodeB),
		{ Code = tree(CodeA, CodeB) }
	;
		{ Tag = complicated_constant_tag(Bits1, Num1) }
	->
			% XXX check
		code_info__cache_expression(Var,
				mkword(Bits1, mkbody(iconst(Num1)))),
		{ Code = empty }
	;
		{ error("Unrecognised tag type in construction") }
	).

:- pred unify_gen__generate_cons_args(list(var), list(rval)).
:- mode unify_gen__generate_cons_args(in, out) is det.

	% Create a list of rvals `unused' for each of the arguments
	% for a construction unification. When lazy constructions
	% are implemented, these fields will contain var(Var).

unify_gen__generate_cons_args([], []).
unify_gen__generate_cons_args([_Var|Vars], [unused|RVals]) :-
	unify_gen__generate_cons_args(Vars, RVals).

%---------------------------------------------------------------------------%

:- pred unify_gen__make_fields_and_argvars(list(var), lval, int, int,
						list(uni_val), list(uni_val)).
:- mode unify_gen__make_fields_and_argvars(in, in, in, in, out, out) is det.

	% Construct a pair of lists that associates the fields of
	% a term with variables.

unify_gen__make_fields_and_argvars([], _, _, _, [], []).
unify_gen__make_fields_and_argvars([Var|Vars], Lval, Field0, TagNum,
							[F|Fs], [A|As]) :-
	F = lval(field(TagNum, Lval, Field0)),
	A = ref(Var),
	Field1 is Field0 + 1,
	unify_gen__make_fields_and_argvars(Vars, Lval, Field1, TagNum, Fs, As).

%---------------------------------------------------------------------------%

	% Generate a deterministic deconstruction. In a deterministic
	% deconstruction, we know the value of the tag, so we don't
	% need to generate a test.

	% Deconstructions are generated semi-eagerly. Any test sub-
	% unifications are generate eagerly (they _must_ be), but
	% assignment unifications are cached.

unify_gen__generate_det_deconstruction(Var, Cons, Args, Modes, Code) -->
	code_info__cons_id_to_tag(Var, Cons, Tag),
	% For constants, if the deconstruction is det, then we already know
	% the value of the constant, so Code = empty.
	(
		{ Tag = string_constant(_String) }
	->
		{ Code = empty }
	;
		{ Tag = int_constant(_Int) }
	->
		{ Code = empty }
	;
		{ Tag = float_constant(_Float) }
	->
		{ Code = empty }
	;
		{ Tag = simple_tag(SimpleTag) }
	->
		code_info__flush_variable(Var, CodeA),
		code_info__get_variable_register(Var, Lval),
		{ unify_gen__make_fields_and_argvars(Args, Lval, 0,
						SimpleTag, Fields, ArgVars) },
		unify_gen__generate_det_unify_args(Fields, ArgVars,
								Modes, CodeB),
		{ Code = tree(CodeA, CodeB) }
	;
		{ Tag = complicated_tag(Bits0, _Num0) }
	->
		code_info__flush_variable(Var, CodeA),
		code_info__get_variable_register(Var, Lval),
		{ unify_gen__make_fields_and_argvars(Args, Lval, 1,
						Bits0, Fields, ArgVars) },
		unify_gen__generate_det_unify_args(Fields, ArgVars,
								Modes, CodeB),
		{ Code = tree(CodeA, CodeB) }
	;
		{ Tag = complicated_constant_tag(_Bits1, _Num1) }
	->
		{ Code = empty } % if this is det, then nothing happens
	;
		{ error("Unrecognised tag in deconstruction") }
	).

%---------------------------------------------------------------------------%

	% Generate a semideterministic deconstruction.
	% A semideterministic deconstruction unification is tag-test
	% followed by a deterministic deconstruction.

unify_gen__generate_semi_deconstruction(Var, Tag, Args, Modes, Code) -->
	unify_gen__generate_tag_test(Var, Tag, CodeA),
	unify_gen__generate_det_deconstruction(Var, Tag, Args, Modes, CodeB),
	{ Code = tree(CodeA, CodeB) }.

%---------------------------------------------------------------------------%

	% Generate code to perform a list of deterministic subunifications
	% for the arguments of a construction.

:- pred unify_gen__generate_det_unify_args(list(uni_val), list(uni_val),
			list(uni_mode), code_tree, code_info, code_info).
:- mode unify_gen__generate_det_unify_args(in, in, in, out, in, out) is det.

unify_gen__generate_det_unify_args(Ls, Rs, Ms, Code) -->
	( unify_gen__generate_det_unify_args_2(Ls, Rs, Ms, Code0) ->
		{ Code = Code0 }
	;
		{ error("unify_gen__generate_det_unify_args: length mismatch") }
	).

:- pred unify_gen__generate_det_unify_args_2(list(uni_val), list(uni_val),
			list(uni_mode), code_tree, code_info, code_info).
:- mode unify_gen__generate_det_unify_args_2(in, in, in, out, in, out)
	is semidet.

unify_gen__generate_det_unify_args_2([], [], [], empty) --> [].
unify_gen__generate_det_unify_args_2([L|Ls], [R|Rs], [M|Ms], Code) -->
	unify_gen__generate_det_sub_unify(L, R, M, CodeA),
	unify_gen__generate_det_unify_args_2(Ls, Rs, Ms, CodeB),
	{ Code = tree(CodeA, CodeB) }.

%---------------------------------------------------------------------------%

	% Generate code to perform a list of semideterministic sub-
	% unifications for the arguments of a [de]construction.
:- pred unify_gen__generate_semi_unify_args(list(uni_val), list(uni_val),
			list(uni_mode), code_tree, code_info, code_info).
:- mode unify_gen__generate_semi_unify_args(in, in, in, out, in, out) is det.

unify_gen__generate_semi_unify_args(Ls, Rs, Ms, Code) -->
	( unify_gen__generate_semi_unify_args_2(Ls, Rs, Ms, Code0) ->
	    { Code = Code0 }
	;
	    { error("unify_gen__generate_semi_unify_args: length mismatch") }
	).

:- pred unify_gen__generate_semi_unify_args_2(list(uni_val), list(uni_val),
			list(uni_mode), code_tree, code_info, code_info).
:- mode unify_gen__generate_semi_unify_args_2(in, in, in, out, in, out)
	is semidet.

unify_gen__generate_semi_unify_args_2([], [], [], empty) --> [].
unify_gen__generate_semi_unify_args_2([L|Ls], [R|Rs], [M|Ms], Code) -->
	unify_gen__generate_semi_sub_unify(L, R, M, CodeA),
	unify_gen__generate_semi_unify_args_2(Ls, Rs, Ms, CodeB),
	{ Code = tree(CodeA, CodeB) }.

%---------------------------------------------------------------------------%

	% Generate a subunification between two [field|variable].

:- pred unify_gen__generate_det_sub_unify(uni_val, uni_val, uni_mode, code_tree,
							code_info, code_info).
:- mode unify_gen__generate_det_sub_unify(in, in, in, out, in, out) is det.

unify_gen__generate_det_sub_unify(L, R, M, Code) -->
	{ M = ((LI - RI) -> (LF - RF)) },
	code_info__get_module_info(ModuleInfo),
	(
			% Input - input == test unification
			% == not allowed in det code.
		{ mode_is_input(ModuleInfo, (LI -> LF)) },
		{ mode_is_input(ModuleInfo, (RI -> RF)) }
	->
		% { true }
		{ error("Det unifications may not contain tests") }
	;
			% Input - Output== assignment ->
		{ mode_is_input(ModuleInfo, (LI -> LF)) },
		{ mode_is_output(ModuleInfo, (RI -> RF)) }
	->
		unify_gen__generate_sub_assign(R, L, Code)
	;
			% Input - Output== assignment <-
		{ mode_is_output(ModuleInfo, (LI -> LF)) },
		{ mode_is_input(ModuleInfo, (RI -> RF)) }
	->
		unify_gen__generate_sub_assign(L, R, Code)
	;
			% Bizzare! [sp?]
		{ mode_is_output(ModuleInfo, (LI -> LF)) },
		{ mode_is_output(ModuleInfo, (RI -> RF)) }
	->
		{ error("Some strange unify") }
	;
		{ Code = empty } % free-free - ignore
	).

%---------------------------------------------------------------------------%

:- pred unify_gen__generate_semi_sub_unify(uni_val, uni_val, uni_mode,
					code_tree, code_info, code_info).
:- mode unify_gen__generate_semi_sub_unify(in, in, in, out, in, out) is det.

unify_gen__generate_semi_sub_unify(L, R, M, Code) -->
	{ M = ((LI - RI) -> (LF - RF)) },
	code_info__get_module_info(ModuleInfo),
	(
			% Input - input == test unification
		{ mode_is_input(ModuleInfo, (LI -> LF)) },
		{ mode_is_input(ModuleInfo, (RI -> RF)) }
	->
		% This shouldn't happen, since the transformation to
		% super-homogeneous form should avoid tests in the arguments
		% of a construction or deconstruction unification.
		{ error("test in arg of [de]construction - tell fjh to fix that bug in make_hlds.nl") },
		unify_gen__generate_sub_test(L, R, Code)
	;
			% Input - Output== assignment ->
		{ mode_is_input(ModuleInfo, (LI -> LF)) },
		{ mode_is_output(ModuleInfo, (RI -> RF)) }
	->
		unify_gen__generate_sub_assign(R, L, Code)
	;
			% Input - Output== assignment <-
		{ mode_is_output(ModuleInfo, (LI -> LF)) },
		{ mode_is_input(ModuleInfo, (RI -> RF)) }
	->
		unify_gen__generate_sub_assign(L, R, Code)
	;
			% Weird! [and you thought I was cutting and pasting]
		{ mode_is_output(ModuleInfo, (LI -> LF)) },
		{ mode_is_output(ModuleInfo, (RI -> RF)) }
	->
		{ error("Some strange unify") }
	;
		{ Code = empty } % free-free - ignore
	).

%---------------------------------------------------------------------------%

:- pred unify_gen__generate_sub_assign(uni_val, uni_val, code_tree,
							code_info, code_info).
:- mode unify_gen__generate_sub_assign(in, in, out, in, out) is det.

	% Assignment between to lvalues - cannot cache [yet]
	% so generate immediate code
unify_gen__generate_sub_assign(lval(Lval), lval(Rval), Code) -->
	{ Code = node([
		assign(Lval, lval(Rval)) - "Copy field"
	]) }.
	% assignment from a variable to an lvalue - cannot cache
	% so generate immediately
unify_gen__generate_sub_assign(lval(Lval), ref(Var), Code) -->
	code_info__flush_variable(Var, Code0),
	code_info__get_variable_register(Var, Source),
	{ Code = tree(
		Code0,
		node([
			assign(Lval, lval(Source)) - "Copy value"
		])
	) }.
	% assignment to a variable, so cache it.
unify_gen__generate_sub_assign(ref(Var), lval(Rval), empty) -->
	(
		code_info__variable_is_live(Var)
	->
		code_info__cache_expression(Var, lval(Rval))
	;
		{ true }
	).
	% assignment to a variable, so cache it.
unify_gen__generate_sub_assign(ref(Lvar), ref(Rvar), empty) -->
	(
		code_info__variable_is_live(Lvar)
	->
		code_info__cache_expression(Lvar, var(Rvar))
	;
		{ true }
	).

%---------------------------------------------------------------------------%

:- pred unify_gen__generate_sub_test(uni_val, uni_val, code_tree,
							code_info, code_info).
:- mode unify_gen__generate_sub_test(in, in, out, in, out) is det.

	% Generate code to evaluate the two arguments of a sub-test
	% and compare them. XXX strings?
unify_gen__generate_sub_test(UnivalX, UnivalY, Code) -->
	unify_gen__evaluate_uni_val(UnivalX, LvalX, CodeX),
	unify_gen__evaluate_uni_val(UnivalY, LvalY, CodeY),
	code_info__get_failure_cont(FallThrough),
	{ Code = tree(CodeX, tree(CodeY,
		node([test(lval(LvalX), lval(LvalY), FallThrough) -
				"simple test in [de]construction"])
	)) }.

:- pred unify_gen__evaluate_uni_val(uni_val, lval, code_tree,
					code_info, code_info).
:- mode unify_gen__evaluate_uni_val(in, out, out, in, out) is det.

	% Lvalue - do nothing
unify_gen__evaluate_uni_val(lval(Lval), Lval, empty) --> [].
	% Var - cached, so flush it.
unify_gen__evaluate_uni_val(ref(Var), Lval, Code) -->
	code_info__flush_variable(Var, Code),
	code_info__get_variable_register(Var, Lval).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%
