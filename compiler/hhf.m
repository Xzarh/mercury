%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 2001-2002, 2004-2007 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: hhf.m.
% Author: dmo.
%
% Convert superhomogeneous form to hyperhomogeneous form and output an
% inst graph for the predicate based on this transformation.
%
% Hyperhomogeneous form and the transformation are documented in
% David Overton's PhD thesis.
%
%-----------------------------------------------------------------------------%

:- module hlds.hhf.
:- interface.

:- import_module hlds.hlds_clauses.
:- import_module hlds.hlds_pred.
:- import_module hlds.hlds_module.
:- import_module hlds.inst_graph.

:- import_module bool.
:- import_module io.

%-----------------------------------------------------------------------------%

:- pred process_pred(bool::in, pred_id::in, module_info::in,
    module_info::out, io::di, io::uo) is det.

:- pred process_clauses_info(bool::in, module_info::in,
    clauses_info::in, clauses_info::out, inst_graph::out) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module check_hlds.type_util.
:- import_module hlds.goal_util.
:- import_module hlds.hlds_args.
:- import_module hlds.hlds_goal.
:- import_module hlds.passes_aux.
:- import_module libs.compiler_util.
:- import_module parse_tree.prog_data.
:- import_module parse_tree.prog_type.
:- import_module parse_tree.prog_util.

:- import_module list.
:- import_module map.
:- import_module maybe.
:- import_module pair.
:- import_module set.
:- import_module solutions.
:- import_module term.
:- import_module varset.

%-----------------------------------------------------------------------------%

process_pred(Simple, PredId, !ModuleInfo, !IO) :-
    module_info_pred_info(!.ModuleInfo, PredId, PredInfo0),
    ( pred_info_is_imported(PredInfo0) ->
        % AAA
        % PredInfo2 = PredInfo0
        pred_info_get_clauses_info(PredInfo0, ClausesInfo),
        clauses_info_get_headvar_list(ClausesInfo, HeadVars),
        clauses_info_get_varset(ClausesInfo, VarSet),
        some [!IG] (
            pred_info_get_inst_graph_info(PredInfo0, !:IG),
            inst_graph.init(HeadVars, InstGraph),
            !:IG = !.IG ^ implementation_inst_graph := InstGraph,
            !:IG = !.IG ^ interface_inst_graph := InstGraph,
            !:IG = !.IG ^ interface_vars := HeadVars,
            !:IG = !.IG ^ interface_varset := VarSet,
            pred_info_set_inst_graph_info(!.IG, PredInfo0, PredInfo2)
        )
    ;
        write_pred_progress_message("% Calculating HHF and inst graph for ",
            PredId, !.ModuleInfo, !IO),

        pred_info_get_clauses_info(PredInfo0, ClausesInfo0),
        process_clauses_info(Simple, !.ModuleInfo, ClausesInfo0,
            ClausesInfo, ImplementationInstGraph),
        pred_info_set_clauses_info(ClausesInfo, PredInfo0, PredInfo1),
        some [!IG] (
            pred_info_get_inst_graph_info(PredInfo1, !:IG),
            !:IG = !.IG ^ implementation_inst_graph := ImplementationInstGraph,

            % AAA only for non-imported preds with no mode decls.
            clauses_info_get_headvar_list(ClausesInfo, HeadVars),
            clauses_info_get_varset(ClausesInfo, VarSet),
            !:IG = !.IG ^ interface_inst_graph := ImplementationInstGraph,
            solutions(
                (pred(V::out) is nondet :-
                    list.member(V0, HeadVars),
                    inst_graph.reachable(ImplementationInstGraph,
                    V0, V)
                ), InterfaceVars),
            !:IG = !.IG ^ interface_vars := InterfaceVars,
            !:IG = !.IG ^ interface_varset := VarSet,

            pred_info_set_inst_graph_info(!.IG, PredInfo1, PredInfo2)
        )
    ),

%   pred_info_get_markers(PredInfo2, Markers),
%   ( check_marker(Markers, infer_modes) ->
%       % No mode declarations.  If not imported, use implementation
%       % inst_graph.
%       % ...
%   ;
%       pred_info_clauses_info(PredInfo2, ClausesInfo2),
%       clauses_info_get_headvars(ClausesInfo2, HeadVars),
%       clauses_info_get_varset(ClausesInfo2, VarSet),
%       inst_graph.init(HeadVars, InterfaceInstGraph),
%       InstGraphInfo0 = ( (PredInfo2 ^ inst_graph_info)
%           ^ interface_inst_graph := InterfaceInstGraph )
%           ^ interface_varset := VarSet,
%       map.foldl(process_proc(ModuleInfo0, HeadVars),
%           Procedures, InstGraphInfo0, InstGraphInfo1),
%
%       % Calculate interface vars.
%       solutions((pred(V::out) is nondet :-
%               list.member(V0, HeadVars),
%               inst_graph.reachable(InstGraph, V0, V)
%           ), InterfaceVars),
%       InstGraphInfo = InstGraphInfo1 ^ interface_vars :=
%           InterfaceVars,
%
%       PredInfo = PredInfo2 ^ inst_graph_info := InstGraphInfo
%   ),

    PredInfo = PredInfo2, % AAA
    module_info_set_pred_info(PredId, PredInfo, !ModuleInfo).

process_clauses_info(Simple, ModuleInfo, !ClausesInfo, InstGraph) :-
    clauses_info_get_varset(!.ClausesInfo, VarSet0),
    clauses_info_get_vartypes(!.ClausesInfo, VarTypes0),
    inst_graph.init(VarTypes0 ^ keys, InstGraph0),
    Info0 = hhf_info(InstGraph0, VarSet0, VarTypes0),

    clauses_info_get_headvar_list(!.ClausesInfo, HeadVars),
    clauses_info_clauses(Clauses0, !ClausesInfo),

    (
    %   % For simple mode checking we do not give the inst_graph any
    %   % structure.
    %   Simple = yes,
    %   Clauses = Clauses0,
    %   Info1 = Info0
    %;
    %   Simple = no,
        list.map_foldl(process_clause(HeadVars),
            Clauses0, Clauses, Info0, Info1)
    ),

    clauses_info_set_clauses(Clauses, !ClausesInfo),

    complete_inst_graph(ModuleInfo, Info1, Info),
    % XXX Comment out the above line for incomplete, quick checking.
    % Info = Info1,

    Info = hhf_info(InstGraph1, VarSet, VarTypes),
    (
        Simple = yes,
        inst_graph.init(VarTypes ^ keys, InstGraph)
    ;
        Simple = no,
        InstGraph = InstGraph1
    ),

    % XXX do we need this (it slows things down a lot (i.e. uses 50%
    % of the runtime).
    % varset.vars(VarSet1, Vars1),
    % varset.ensure_unique_names(Vars1, "_", VarSet1, VarSet),

    clauses_info_set_varset(VarSet, !ClausesInfo),
    clauses_info_set_vartypes(VarTypes, !ClausesInfo).

:- type hhf_info
    --->    hhf_info(
                inst_graph  :: inst_graph,
                varset      :: prog_varset,
                vartypes    :: vartypes
            ).

:- pred process_clause(list(prog_var)::in, clause::in, clause::out,
    hhf_info::in, hhf_info::out) is det.

process_clause(_HeadVars, clause(ProcIds, Goal0, Lang, Context),
        clause(ProcIds, Goal, Lang, Context), !HI) :-
    Goal0 = hlds_goal(_, GoalInfo0),
    goal_info_get_nonlocals(GoalInfo0, NonLocals),

    process_goal(NonLocals, Goal0, Goal, !HI).
% XXX We probably need to requantify, but it stuffs up the inst_graph to do
% that.
%   VarSet1 = !.HI ^ varset,
%   VarTypes1 = !.HI ^ vartypes,
%   implicitly_quantify_clause_body(HeadVars, Goal1, VarSet1, VarTypes1,
%       Goal, VarSet, VarTypes, _Warnings),
%   !:HI = !.HI varset := VarSet,
%   !:HI = !.HI vartypes := VarTypes.

:- pred process_goal(set(prog_var)::in, hlds_goal::in, hlds_goal::out,
    hhf_info::in, hhf_info::out) is det.

process_goal(NonLocals, Goal0, Goal, !HI) :-
    Goal0 = hlds_goal(GoalExpr0, GoalInfo),
    process_goal_expr(NonLocals, GoalInfo, GoalExpr0, GoalExpr, !HI),
    Goal = hlds_goal(GoalExpr, GoalInfo).

:- pred goal_use_own_nonlocals(hlds_goal::in, hlds_goal::out,
    hhf_info::in, hhf_info::out) is det.

goal_use_own_nonlocals(Goal0, Goal, !HI) :-
    Goal0 = hlds_goal(GoalExpr0, GoalInfo),
    goal_info_get_nonlocals(GoalInfo, NonLocals),
    process_goal_expr(NonLocals, GoalInfo, GoalExpr0, GoalExpr, !HI),
    Goal = hlds_goal(GoalExpr, GoalInfo).

:- pred process_goal_expr(set(prog_var)::in, hlds_goal_info::in,
    hlds_goal_expr::in, hlds_goal_expr::out, hhf_info::in, hhf_info::out)
    is det.

process_goal_expr(NonLocals, GoalInfo, GoalExpr0, GoalExpr, !HI) :-
    (
        GoalExpr0 = unify(Var, RHS, Mode, Unif, Context),
        process_unify(RHS, NonLocals, GoalInfo, Var, Mode, Unif, Context,
            GoalExpr, !HI)
    ;
        GoalExpr0 = plain_call(_, _, _, _, _, _),
        GoalExpr = GoalExpr0
    ;
        GoalExpr0 = generic_call(_, _, _, _),
        GoalExpr = GoalExpr0
    ;
        GoalExpr0 = call_foreign_proc(_, _, _, _, _, _, _),
        GoalExpr = GoalExpr0
    ;
        GoalExpr0 = conj(ConjType, Goals0),
        list.map_foldl(process_goal(NonLocals), Goals0, Goals1, !HI),
        (
            ConjType = plain_conj,
            flatten_conj(Goals1, Goals)
        ;
            ConjType = parallel_conj,
            Goals = Goals1
        ),
        GoalExpr = conj(ConjType, Goals)
    ;
        GoalExpr0 = disj(Goals0),
        list.map_foldl(goal_use_own_nonlocals, Goals0, Goals, !HI),
        GoalExpr = disj(Goals)
    ;
        GoalExpr0 = switch(_, _, _),
        unexpected(this_file, "hhf_goal_expr: found switch")
    ;
        GoalExpr0 = scope(Reason, SubGoal0),
        process_goal(NonLocals, SubGoal0, SubGoal, !HI),
        GoalExpr = scope(Reason, SubGoal)
    ;
        GoalExpr0 = negation(SubGoal0),
        process_goal(NonLocals, SubGoal0, SubGoal, !HI),
        GoalExpr = negation(SubGoal)
    ;
        GoalExpr0 = if_then_else(Vs, Cond0, Then0, Else0),
        process_goal(NonLocals, Cond0, Cond, !HI),
        Then0 = hlds_goal(ThenExpr0, ThenInfo),
        goal_info_get_nonlocals(ThenInfo, ThenNonLocals),
        process_goal_expr(ThenNonLocals, ThenInfo, ThenExpr0, ThenExpr, !HI),
        Then = hlds_goal(ThenExpr, ThenInfo),
        Else0 = hlds_goal(ElseExpr0, ElseInfo),
        goal_info_get_nonlocals(ElseInfo, ElseNonLocals),
        process_goal_expr(ElseNonLocals, ElseInfo, ElseExpr0, ElseExpr, !HI),
        Else = hlds_goal(ElseExpr, ElseInfo),
        GoalExpr = if_then_else(Vs, Cond, Then, Else)
    ;
        GoalExpr0 = shorthand(_),
        unexpected(this_file, "hhf_goal_expr: found shorthand")
    ).

:- pred process_unify(unify_rhs::in, set(prog_var)::in, hlds_goal_info::in,
    prog_var::in, unify_mode::in, unification::in, unify_context::in,
    hlds_goal_expr::out, hhf_info::in, hhf_info::out) is det.

process_unify(rhs_var(Y), _, _, X, Mode, Unif, Context, GoalExpr, !HI) :-
    GoalExpr = unify(X, rhs_var(Y), Mode, Unif, Context).
process_unify(rhs_lambda_goal(A,B,C,D,E,F,G,LambdaGoal0), NonLocals, _, X,
        Mode, Unif, Context, GoalExpr, !HI) :-
    process_goal(NonLocals, LambdaGoal0, LambdaGoal, !HI),
    GoalExpr = unify(X, rhs_lambda_goal(A,B,C,D,E,F,G,LambdaGoal), Mode,
        Unif, Context).
process_unify(rhs_functor(ConsId0, IsExistConstruct, ArgsA), NonLocals,
        GoalInfo0, X, Mode, Unif, Context, GoalExpr, !HI) :-
    TypeOfX = !.HI ^ vartypes ^ det_elem(X),
    qualify_cons_id(TypeOfX, ArgsA, ConsId0, _, ConsId),
    InstGraph0 = !.HI ^ inst_graph,
    map.lookup(InstGraph0, X, node(Functors0, MaybeParent)),
    ( map.search(Functors0, ConsId, ArgsB) ->
        make_unifications(ArgsA, ArgsB, GoalInfo0, Mode, Unif, Context,
            Unifications),
        Args = ArgsB
    ;
        add_unifications(ArgsA, NonLocals, GoalInfo0, Mode, Unif, Context,
            Args, Unifications, !HI),
        InstGraph1 = !.HI ^ inst_graph,
        map.det_insert(Functors0, ConsId, Args, Functors),
        map.det_update(InstGraph1, X, node(Functors, MaybeParent),
            InstGraph2),
        list.foldl(inst_graph.set_parent(X), Args, InstGraph2, InstGraph),
        !:HI = !.HI ^ inst_graph := InstGraph
    ),
    goal_info_get_nonlocals(GoalInfo0, GINonlocals0),
    GINonlocals = GINonlocals0 `set.union` list_to_set(Args),
    goal_info_set_nonlocals(GINonlocals, GoalInfo0, GoalInfo),
    UnifyGoalExpr = unify(X, rhs_functor(ConsId, IsExistConstruct, Args),
        Mode, Unif, Context),
    UnifyGoal = hlds_goal(UnifyGoalExpr, GoalInfo),
    GoalExpr = conj(plain_conj, [UnifyGoal | Unifications]).

:- pred make_unifications(list(prog_var)::in, list(prog_var)::in,
    hlds_goal_info::in, unify_mode::in, unification::in, unify_context::in,
    hlds_goals::out) is det.

make_unifications([], [], _, _, _, _, []).
make_unifications([_ | _], [], _, _, _, _, _) :-
    unexpected(this_file, "hhf_make_unifications: length mismatch (1)").
make_unifications([], [_ | _], _, _, _, _, _) :-
    unexpected(this_file, "hhf_make_unifications: length mismatch (2)").
make_unifications([A | As], [B | Bs], GI0, M, U, C,
        [hlds_goal(unify(A, rhs_var(B), M, U, C), GI) | Us]) :-
    goal_info_get_nonlocals(GI0, GINonlocals0),
    GINonlocals = GINonlocals0 `set.insert` A `set.insert` B,
    goal_info_set_nonlocals(GINonlocals, GI0, GI),
    make_unifications(As, Bs, GI0, M, U, C, Us).

:- pred add_unifications(list(prog_var)::in, set(prog_var)::in,
    hlds_goal_info::in, unify_mode::in, unification::in, unify_context::in,
    list(prog_var)::out, hlds_goals::out, hhf_info::in, hhf_info::out) is det.

add_unifications([], _, _, _, _, _, [], [], !HI).
add_unifications([A | As], NonLocals, GI0, M, U, C, [V | Vs], Goals, !HI) :-
    add_unifications(As, NonLocals, GI0, M, U, C, Vs, Goals0, !HI),
    InstGraph0 = !.HI ^ inst_graph,
    (
        (
            map.lookup(InstGraph0, A, Node),
            Node = node(_, parent(_))
        ;
            A `set.member` NonLocals
        )
    ->
        VarSet0 = !.HI ^ varset,
        VarTypes0 = !.HI ^ vartypes,
        varset.new_var(VarSet0, V, VarSet),
        map.lookup(VarTypes0, A, Type),
        map.det_insert(VarTypes0, V, Type, VarTypes),
        map.init(Empty),
        map.det_insert(InstGraph0, V, node(Empty, top_level), InstGraph),
        !:HI = !.HI ^ varset := VarSet,
        !:HI = !.HI ^ vartypes := VarTypes,
        !:HI = !.HI ^ inst_graph := InstGraph,
        goal_info_get_nonlocals(GI0, GINonlocals0),
        GINonlocals = GINonlocals0 `set.insert` V,
        goal_info_set_nonlocals(GINonlocals, GI0, GI),
        Goals = [hlds_goal(unify(A, rhs_var(V), M, U, C), GI) | Goals0]
    ;
        V = A,
        Goals = Goals0
    ).

:- pred complete_inst_graph(module_info::in, hhf_info::in, hhf_info::out)
    is det.

complete_inst_graph(ModuleInfo, !HI) :-
    InstGraph0 = !.HI ^ inst_graph,
    map.keys(InstGraph0, Vars),
    list.foldl(complete_inst_graph_node(ModuleInfo, Vars), Vars, !HI).

:- pred complete_inst_graph_node(module_info::in, list(prog_var)::in,
    prog_var::in, hhf_info::in, hhf_info::out) is det.

complete_inst_graph_node(ModuleInfo, BaseVars, Var, !HI) :-
    VarTypes0 = !.HI ^ vartypes,
    (
        map.search(VarTypes0, Var, Type),
        type_constructors(Type, ModuleInfo, Constructors),
        type_to_ctor_and_args(Type, TypeId, _)
    ->
        list.foldl(maybe_add_cons_id(Var, ModuleInfo, BaseVars, TypeId),
            Constructors, !HI)
    ;
        true
    ).

:- pred maybe_add_cons_id(prog_var::in, module_info::in, list(prog_var)::in,
    type_ctor::in, constructor::in, hhf_info::in, hhf_info::out) is det.

maybe_add_cons_id(Var, ModuleInfo, BaseVars, TypeId, Ctor, !HI) :-
    Ctor = ctor(_, _, Name, Args, _),
    ConsId = make_cons_id(Name, Args, TypeId),
    map.lookup(!.HI ^ inst_graph, Var, node(Functors0, MaybeParent)),
    ( map.contains(Functors0, ConsId) ->
        true
    ;
        list.map_foldl(add_cons_id(Var, ModuleInfo, BaseVars), Args, NewVars,
            !HI),
        map.det_insert(Functors0, ConsId, NewVars, Functors),
        !:HI = !.HI ^ inst_graph :=
            map.det_update(!.HI ^ inst_graph, Var,
                node(Functors, MaybeParent))
    ).

:- pred add_cons_id(prog_var::in, module_info::in, list(prog_var)::in,
    constructor_arg::in, prog_var::out, hhf_info::in, hhf_info::out)
    is det.

add_cons_id(Var, ModuleInfo, BaseVars, Arg, NewVar, !HI) :-
    ArgType = Arg ^ arg_type,
    !.HI = hhf_info(InstGraph0, VarSet0, VarTypes0),
    (
        find_var_with_type(Var, ArgType, InstGraph0, VarTypes0,
            BaseVars, NewVar0)
    ->
        NewVar = NewVar0
    ;
        varset.new_var(VarSet0, NewVar, VarSet),
        map.det_insert(VarTypes0, NewVar, ArgType, VarTypes),
        map.init(Empty),
        map.det_insert(InstGraph0, NewVar, node(Empty, parent(Var)),
            InstGraph),
        !:HI = hhf_info(InstGraph, VarSet, VarTypes),
        complete_inst_graph_node(ModuleInfo, BaseVars, NewVar, !HI)
    ).

:- pred find_var_with_type(prog_var::in, mer_type::in, inst_graph::in,
    vartypes::in, list(prog_var)::in, prog_var::out) is semidet.

find_var_with_type(Var0, Type, InstGraph, VarTypes, BaseVars, Var) :-
    (
        map.search(VarTypes, Var0, Type0),
        same_type(Type0, Type)
    ->
        Var = Var0
    ;
        map.lookup(InstGraph, Var0, node(_, parent(Var1))),
        \+ Var1 `list.member` BaseVars,
        find_var_with_type(Var1, Type, InstGraph, VarTypes, BaseVars, Var)
    ).

:- pred same_type(mer_type::in, mer_type::in) is semidet.

same_type(A0, B0) :-
    A = strip_kind_annotation(A0),
    B = strip_kind_annotation(B0),
    same_type_2(A, B).

:- pred same_type_2(mer_type::in, mer_type::in) is semidet.

same_type_2(type_variable(_, _), type_variable(_, _)).
same_type_2(defined_type(Name, ArgsA, _), defined_type(Name, ArgsB, _)) :-
    same_type_list(ArgsA, ArgsB).
same_type_2(builtin_type(BuiltinType), builtin_type(BuiltinType)).
same_type_2(higher_order_type(ArgsA, no, Purity, EvalMethod),
        higher_order_type(ArgsB, no, Purity, EvalMethod)) :-
    same_type_list(ArgsA, ArgsB).
same_type_2(higher_order_type(ArgsA, yes(RetA), Purity, EvalMethod),
        higher_order_type(ArgsB, yes(RetB), Purity, EvalMethod)) :-
    same_type_list(ArgsA, ArgsB),
    same_type(RetA, RetB).
same_type_2(tuple_type(ArgsA, _), tuple_type(ArgsB, _)) :-
    same_type_list(ArgsA, ArgsB).
same_type_2(apply_n_type(_, ArgsA, _), apply_n_type(_, ArgsB, _)) :-
    same_type_list(ArgsA, ArgsB).

:- pred same_type_list(list(mer_type)::in, list(mer_type)::in) is semidet.

same_type_list([], []).
same_type_list([A | As], [B | Bs]) :-
    same_type(A, B),
    same_type_list(As, Bs).

%------------------------------------------------------------------------%

%   % Add the information from the procedure's mode declaration
%   % to the inst_graph.
% :- pred process_proc(module_info::in, list(prog_var)::in, proc_id::in,
%   proc_info::in, inst_graph::out, prog_varset::out) is det.
%
% process_proc(ModuleInfo, HeadVars, _ProcId, ProcInfo, Info0, Info) :-
%   proc_info_get_argmodes(ProcInfo, ArgModes),
%
%   mode_list_get_initial_insts(ArgModes, ModuleInfo, InstsI),
%   assoc_list.from_corresponding_lists(HeadVars, InstsI, VarInstsI),
%   list.foldl(process_arg(ModuleInfo), VarInstsI, Info0, Info),
%
%   mode_list_get_final_insts(ArgModes, ModuleInfo, InstsF),
%   assoc_list.from_corresponding_lists(HeadVars, InstsF, VarInstsF),
%   list.foldl(process_arg(ModuleInfo), VarInstsF, Info0, Info).
%
% :- pred process_arg(module_info::in, pair(prog_var, inst)::in,
%       inst_graph_info::in, inst_graph_info::out) is det.
%
% process_arg(ModuleInfo, Var - Inst, Info0, Info) :-
%   map.init(Seen0),
%   process_arg_inst(ModuleInfo, Var, Seen0, Inst, Info0, Info).
%
% :- pred process_arg_inst(module_info::in, prog_var::in,
%       map(inst_name, prog_var)::in, inst::in, inst_graph_info::in,
%       inst_graph_info::out) is det.
%
% process_arg_inst(ModuleInfo, Var, Seen0, Inst0, Info0, Info) :-
%   ( Inst0 = defined_inst(InstName) ->
%       map.det_insert(Seen0, InstName, Var, Seen),
%       inst_lookup(ModuleInfo, InstName, Inst),
%       process_arg_inst(Inst, ModuleInfo, Var, Seen, Info0, Info)
%   ; Inst0 = bound(_, BoundInsts) ->
%       list.foldl(process_bound_inst(ModuleInfo, Var, Seen0),
%           BoundInts, Info0, Info)
%   ;
%       Info = Info0
%   ).
%
% :- pred process_bound_inst(module_info::in, prog_var::in,
%       map(inst_name, prog_var)::in, bound_inst::in,
%       inst_graph_info::in, inst_graph_info::out) is det.

%------------------------------------------------------------------------%

:- func this_file = string.

this_file = "hhf.m".

%------------------------------------------------------------------------%
:- end_module hhf.
%------------------------------------------------------------------------%
