%-----------------------------------------------------------------------------%
% Copyright (C) 1995 University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

% Original author: conway.
% Extensive modification by zs.

% Allocates the storage location for each live variable
% at the end of each branched structure, so that the code generator
% will generate code which puts the variable in the same place
% in each branch.

% This module requires arg_infos and livenesses to have already been computed,
% and stack slots allocated.

%-----------------------------------------------------------------------------%

:- module store_alloc.

:- interface.

:- import_module hlds_module, hlds_pred.

:- pred store_alloc_in_proc(proc_info, module_info, proc_info).
:- mode store_alloc_in_proc(in, in, out) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module hlds_goal, follow_vars, llds.
:- import_module options, globals, goal_util, mode_util, instmap.
:- import_module list, map, set, std_util, assoc_list.
:- import_module bool, int, require.

%-----------------------------------------------------------------------------%

store_alloc_in_proc(ProcInfo0, ModuleInfo, ProcInfo) :-
	module_info_globals(ModuleInfo, Globals),
	globals__lookup_bool_option(Globals, follow_vars, ApplyFollowVars),
	( ApplyFollowVars = yes ->
		globals__get_args_method(Globals, ArgsMethod),
		proc_info_goal(ProcInfo0, Goal0),

		find_final_follow_vars(ProcInfo0, FollowVars0),
		find_follow_vars_in_goal(Goal0, ArgsMethod, ModuleInfo,
			FollowVars0, Goal1, FollowVars),
		proc_info_set_follow_vars(ProcInfo0, FollowVars, ProcInfo1)
	;
		ProcInfo1 = ProcInfo0,
		proc_info_goal(ProcInfo1, Goal1)
	),
	initial_liveness(ProcInfo1, ModuleInfo, Liveness1),
	store_alloc_in_goal(Goal1, Liveness1, ModuleInfo, Goal, _Liveness),
	proc_info_set_goal(ProcInfo1, Goal, ProcInfo).

%-----------------------------------------------------------------------------%

:- pred store_alloc_in_goal(hlds__goal, liveness_info, module_info,
	hlds__goal, liveness_info).
:- mode store_alloc_in_goal(in, in, in, out, out) is det.

store_alloc_in_goal(Goal0 - GoalInfo0, Liveness0, ModuleInfo,
		Goal - GoalInfo0, Liveness) :-
	goal_info_get_code_model(GoalInfo0, CodeModel),
	goal_info_pre_births(GoalInfo0, PreBirths),
	goal_info_pre_deaths(GoalInfo0, PreDeaths),
	goal_info_post_births(GoalInfo0, PostBirths),
	goal_info_post_deaths(GoalInfo0, PostDeaths),
	goal_info_nondet_lives(GoalInfo0, NondetLives0),

	set__difference(Liveness0,  PreDeaths, Liveness1),
	set__union(Liveness1, PreBirths, Liveness2),
	store_alloc_in_goal_2(Goal0, Liveness2, NondetLives0,
			ModuleInfo, Goal1, Liveness3),
	set__difference(Liveness3, PostDeaths, Liveness4),
	% If any variables magically become live in the PostBirths,
	% then they have to mundanely become live somewhere else,
	% so we don't need to allocate anything for them here.
	set__union(Liveness4, PostBirths, Liveness),
	(
		Goal1 = disj(Disjuncts, FollowVars)
	->
		% For nondet disjunctions, we only want to allocate registers
		% for the variables that are generated by the disjunction
		% (the outputs).  For the inputs, the first disjunct will
		% use whichever registers they happen to be in,
		% and for subsequent disjuncts these variables need to be
		% put in framevars.
		( CodeModel = model_non ->
			set__difference(Liveness, Liveness0, OutputVars),
			set__to_sorted_list(OutputVars, LiveVarList)
		;
			set__to_sorted_list(Liveness, LiveVarList)
		),
		store_alloc_allocate_storage(LiveVarList, FollowVars,
			StoreMap),
		Goal = disj(Disjuncts, StoreMap)
	;
		Goal1 = switch(Var, CanFail, Cases, FollowVars)
	->
		set__to_sorted_list(Liveness, LiveVarList),
		store_alloc_allocate_storage(LiveVarList, FollowVars,
			StoreMap),
		Goal = switch(Var, CanFail, Cases, StoreMap)
	;
		Goal1 = if_then_else(Vars, Cond, Then, Else, FollowVars)
	->
		set__to_sorted_list(Liveness, LiveVarList),
		store_alloc_allocate_storage(LiveVarList, FollowVars,
			StoreMap),
		Goal = if_then_else(Vars, Cond, Then, Else, StoreMap)
	;
		Goal = Goal1
	).

%-----------------------------------------------------------------------------%

	% Here we process each of the different sorts of goals.

:- pred store_alloc_in_goal_2(hlds__goal_expr, liveness_info,
	set(var), module_info, hlds__goal_expr, liveness_info).
:- mode store_alloc_in_goal_2(in, in, in, in, out, out) is det.

store_alloc_in_goal_2(conj(Goals0), Liveness0, _NondetLives, ModuleInfo,
		conj(Goals), Liveness) :-
	store_alloc_in_conj(Goals0, Liveness0, ModuleInfo, Goals, Liveness).

store_alloc_in_goal_2(disj(Goals0, FV), Liveness0, _NondetLives, ModuleInfo,
		disj(Goals, FV), Liveness) :-
	store_alloc_in_disj(Goals0, Liveness0, ModuleInfo, Goals, Liveness).

store_alloc_in_goal_2(not(Goal0), Liveness0, NondetLives, ModuleInfo,
		not(Goal), Liveness) :-
	store_alloc_in_goal(Goal0, Liveness0, ModuleInfo, Goal1, Liveness),
	Goal1 = GoalGoal - GoalInfo0,
	set__union(Liveness, NondetLives, ContLives),
	goal_info_set_cont_lives(GoalInfo0, yes(ContLives), GoalInfo),
	Goal = GoalGoal - GoalInfo.

store_alloc_in_goal_2(switch(Var, Det, Cases0, FV), Liveness0, _NondetLives,
		ModuleInfo, switch(Var, Det, Cases, FV), Liveness) :-
	store_alloc_in_cases(Cases0, Liveness0, ModuleInfo, Cases, Liveness).

store_alloc_in_goal_2(if_then_else(Vars, Cond0, Then0, Else0, FV),
		Liveness0, NondetLives, ModuleInfo,
		if_then_else(Vars, Cond, Then, Else, FV), Liveness) :-
	store_alloc_in_goal(Cond0, Liveness0, ModuleInfo, Cond1, Liveness1),
	Cond1 = CondGoal - GoalInfo0,
	Else0 = _ElseGoal - ElseGoalInfo,
	goal_info_pre_deaths(ElseGoalInfo, Deaths),
	set__intersect(Liveness1, Liveness0, ContLiveness0),
	set__difference(ContLiveness0, Deaths, ContLiveness),
	set__union(ContLiveness, NondetLives, ContLives),
	goal_info_set_cont_lives(GoalInfo0, yes(ContLives), GoalInfo),
	Cond = CondGoal - GoalInfo,
	store_alloc_in_goal(Then0, Liveness1, ModuleInfo, Then, Liveness),
	store_alloc_in_goal(Else0, Liveness1, ModuleInfo, Else, _Liveness2).

store_alloc_in_goal_2(some(Vars, Goal0), Liveness0, _, ModuleInfo,
		some(Vars, Goal), Liveness) :-
	store_alloc_in_goal(Goal0, Liveness0, ModuleInfo, Goal, Liveness).

store_alloc_in_goal_2(higher_order_call(A, B, C, D, E), Liveness, _, _,
		higher_order_call(A, B, C, D, E), Liveness).

store_alloc_in_goal_2(call(A, B, C, D, E, F), Liveness, _, _,
		call(A, B, C, D, E, F), Liveness).

store_alloc_in_goal_2(unify(A,B,C,D,E), Liveness, _, _,
		unify(A,B,C,D,E), Liveness).

store_alloc_in_goal_2(pragma_c_code(A, B, C, D, E, F), Liveness, _, _,
		pragma_c_code(A, B, C, D, E, F), Liveness).

%-----------------------------------------------------------------------------%

:- pred store_alloc_in_conj(list(hlds__goal), liveness_info,
		module_info, list(hlds__goal), liveness_info).
:- mode store_alloc_in_conj(in, in, in, out, out) is det.

store_alloc_in_conj([], Liveness, _M, [], Liveness).
store_alloc_in_conj([Goal0 | Goals0], Liveness0, ModuleInfo,
		[Goal | Goals], Liveness) :-
	(
			% XXX should be threading the instmap
		Goal0 = _ - GoalInfo,
		goal_info_get_instmap_delta(GoalInfo, InstMapDelta),
		instmap_delta_is_unreachable(InstMapDelta)
	->
		store_alloc_in_goal(Goal0, Liveness0, ModuleInfo,
			Goal, Liveness),
		Goals = Goals0
	;
		store_alloc_in_goal(Goal0, Liveness0, ModuleInfo,
			Goal, Liveness1),
		store_alloc_in_conj(Goals0, Liveness1, ModuleInfo,
			Goals, Liveness)
	).

%-----------------------------------------------------------------------------%

:- pred store_alloc_in_disj(list(hlds__goal), liveness_info, module_info,
	list(hlds__goal), liveness_info).
:- mode store_alloc_in_disj(in, in, in, out, out) is det.

store_alloc_in_disj([], Liveness, _ModuleInfo, [], Liveness).
store_alloc_in_disj([Goal0 | Goals0], Liveness0, ModuleInfo,
		[Goal | Goals], Liveness) :-
	store_alloc_in_goal(Goal0, Liveness0, ModuleInfo, Goal, Liveness),
	store_alloc_in_disj(Goals0, Liveness0, ModuleInfo, Goals, _Liveness1).

%-----------------------------------------------------------------------------%

:- pred store_alloc_in_cases(list(case), liveness_info, module_info,
	list(case), liveness_info).
:- mode store_alloc_in_cases(in, in, in, out, out) is det.

store_alloc_in_cases([], Liveness, _ModuleInfo, [], Liveness).
store_alloc_in_cases([case(Cons, Goal0) | Goals0], Liveness0,
		ModuleInfo, [case(Cons, Goal) | Goals], Liveness) :-
	store_alloc_in_goal(Goal0, Liveness0, ModuleInfo, Goal, Liveness),
	store_alloc_in_cases(Goals0, Liveness0, ModuleInfo, Goals, _Liveness1).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred initial_liveness(proc_info, module_info, set(var)).
:- mode initial_liveness(in, in, out) is det.

initial_liveness(ProcInfo, ModuleInfo, Liveness) :-
	proc_info_headvars(ProcInfo, Vars),
	proc_info_argmodes(ProcInfo, Modes),
	proc_info_vartypes(ProcInfo, VarTypes),
	map__apply_to_list(Vars, VarTypes, Types),
	set__init(Liveness0),
	(
		initial_liveness_2(Vars, Modes, Types, ModuleInfo,
			Liveness0, Liveness1)
	->
		Liveness = Liveness1
	;
		error("initial_liveness: list length mis-match")
	).

:- pred initial_liveness_2(list(var), list(mode), list(type), module_info,
	set(var), set(var)).
:- mode initial_liveness_2(in, in, in, in, in, out) is semidet.

initial_liveness_2([], [], [], _ModuleInfo, Liveness, Liveness).
initial_liveness_2([Var | Vars], [Mode | Modes], [Type | Types],
		ModuleInfo, Liveness0, Liveness) :-
	(
		mode_to_arg_mode(ModuleInfo, Mode, Type, top_in)
	->
		set__insert(Liveness0, Var, Liveness1)
	;
		Liveness1 = Liveness0
	),
	initial_liveness_2(Vars, Modes, Types, ModuleInfo, Liveness1, Liveness).

%-----------------------------------------------------------------------------%

:- pred store_alloc_allocate_storage(list(var), map(var, lval), map(var, lval)).
:- mode store_alloc_allocate_storage(in, in, out) is det.

store_alloc_allocate_storage(LiveVars, FollowVars, StoreMap) :-
	map__keys(FollowVars, FollowKeys),
	store_alloc_remove_nonlive(FollowKeys, LiveVars, FollowVars, StoreMap0),
	store_alloc_allocate_extras(LiveVars, 1, StoreMap0, StoreMap).

:- pred store_alloc_remove_nonlive(list(var), list(var),
	map(var, lval), map(var, lval)).
:- mode store_alloc_remove_nonlive(in, in, in, out) is det.

store_alloc_remove_nonlive([], _LiveVars, StoreMap, StoreMap).
store_alloc_remove_nonlive([Var | Vars], LiveVars, StoreMap0, StoreMap) :-
	(
		list__member(Var, LiveVars)
	->
		StoreMap1 = StoreMap0
	;
		map__delete(StoreMap0, Var, StoreMap1)
	),
	store_alloc_remove_nonlive(Vars, LiveVars, StoreMap1, StoreMap).

:- pred store_alloc_allocate_extras(list(var), int,
	map(var, lval), map(var, lval)).
:- mode store_alloc_allocate_extras(in, in, in, out) is det.

store_alloc_allocate_extras([], _N, StoreMap, StoreMap).
store_alloc_allocate_extras([Var | Vars], N0, StoreMap0, StoreMap) :-
	(
		map__contains(StoreMap0, Var)
	->
		N1 = N0,
		StoreMap1 = StoreMap0
	;
		map__values(StoreMap0, Values),
		next_free_reg(N0, Values, N1),
		map__set(StoreMap0, Var, reg(r(N1)), StoreMap1)
	),
	store_alloc_allocate_extras(Vars, N1, StoreMap1, StoreMap).

%-----------------------------------------------------------------------------%

:- pred next_free_reg(int, list(lval), int).
:- mode next_free_reg(in, in, out) is det.

next_free_reg(N0, Values, N) :-
	(
		list__member(reg(r(N0)), Values)
	->
		N1 is N0 + 1,
		next_free_reg(N1, Values, N)
	;
		N = N0
	).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
