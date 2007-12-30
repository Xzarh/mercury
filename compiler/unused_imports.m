%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 2006-2007 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: unused_imports.m.
% Main author: petdr.
%
% This module scans the current module determining all the modules which are
% used in the module and then compares that with the set of modules imported
% and reports those modules which are unused.
%
% It also determines which imports aren't used in the interface, and thus
% should only be in the implementation.
%
% XXX The analysis carried out here can break in the presence of procedures
% that have both foreign language clauses and default Mercury clauses.
% The problem is that some of module imports may only be required by
% the Mercury clauses but these are thrown away if we use the foreign clauses.
% As a result the module imports may appear to be unused.
%
%-----------------------------------------------------------------------------%

:- module check_hlds.unused_imports.
:- interface.

:- import_module hlds.
:- import_module hlds.hlds_module.
:- import_module parse_tree.
:- import_module parse_tree.error_util.

:- import_module io.
:- import_module list.

    % This predicate issues a warning for each import_module
    % which is not directly used in this module, plus those
    % which are in the interface but should be in the implementation.
    %
:- pred unused_imports(module_info::in, list(error_spec)::out,
    io::di, io::uo) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module hlds.hlds_clauses.
:- import_module hlds.hlds_data.
:- import_module hlds.hlds_goal.
:- import_module hlds.hlds_pred.
:- import_module mdbcomp.
:- import_module mdbcomp.prim_data.
:- import_module parse_tree.modules.
:- import_module parse_tree.prog_data.

:- import_module bool.
:- import_module map.
:- import_module maybe.
:- import_module pair.
:- import_module set.
:- import_module string.
:- import_module term.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

unused_imports(ModuleInfo, !:Specs, !IO) :-
    !:Specs = [],
    module_info_get_name(ModuleInfo, ModuleName),
    module_name_to_file_name(ModuleName, ".m", no, FileName, !IO),

    % Each parent module of the current module imports are inherited by
    % this module so we have to add the used modules of the parents to
    % the set of used modules, as an import in the parent may only be
    % consumed by the parent.
    %
    % We also consider the implicitly imported modules to be used as
    % the user cannot do anything about them.

    ImplicitImports = all_builtin_modules,
    module_info_get_used_modules(ModuleInfo, UsedModules0),
    list.foldl(add_all_modules(visibility_public), ImplicitImports,
        UsedModules0, UsedModules1),
    used_modules(ModuleInfo, UsedModules1, UsedModules),

    % The unused imports is simply the set of imports minus all the
    % used modules.
    module_info_get_imported_module_specifiers(ModuleInfo, ImportedModules),
    UsedInImplementation = UsedModules ^ impl_used_modules,
    UnusedImports = to_sorted_list(ImportedModules `difference`
        (UsedInInterface `union` UsedInImplementation)),

    (
        UnusedImports = [_ | _],
        ImportSpec = generate_warning(ModuleName, FileName, UnusedImports, ""),
        !:Specs = [ImportSpec | !.Specs]
    ;
        UnusedImports = []
    ),

    % Determine the modules imported in the interface but not used in
    % the interface.
    module_info_get_interface_module_specifiers(ModuleInfo, InterfaceImports),
    UsedInInterface = UsedModules ^ int_used_modules,
    UnusedInterfaceImports = to_sorted_list(InterfaceImports
        `difference` UsedInInterface `difference` set(UnusedImports)),

    (
        UnusedInterfaceImports = [_ | _],
        InterfaceImportSpec = generate_warning(ModuleName, FileName,
            UnusedInterfaceImports, " interface"),
        !:Specs = [InterfaceImportSpec | !.Specs]
    ;
        UnusedInterfaceImports = []
    ).

:- func generate_warning(module_name, string, list(module_name), string)
    = error_spec.

generate_warning(ModuleName, FileName, UnusedImports, Location) = Spec :-
    term.context_init(FileName, 1, Context),
    ModuleWord = choose_number(UnusedImports, "module", "modules"),
    IsOrAre = is_or_are(UnusedImports),

    ( Location = "" ->
        InThe = "",
        LocationOf = ""
    ;
        InThe = " in the",
        LocationOf = Location ++ " of"
    ),

    UnusedSymNames = list.map(wrap_module_name, UnusedImports),
    Pieces = [words("In " ++ LocationOf ++ " module" ), sym_name(ModuleName),
        suffix(":"), nl,
        words("warning:"), words(ModuleWord)] ++
        component_list_to_pieces(UnusedSymNames) ++
        [fixed(IsOrAre), words("imported, "),
        words("but"), fixed(IsOrAre),
        words("not used" ++ InThe ++ Location ++ ".")],
    Msg = simple_msg(Context, [always(Pieces)]),
    Spec = error_spec(severity_warning, phase_code_gen, [Msg]).

%-----------------------------------------------------------------------------%

:- func wrap_module_name(module_name) = format_component.

wrap_module_name(SymName) = sym_name(SymName).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

    % Scan each item in the module_info recording the module qualifications on
    % the item and if that module is used in the interface or implementation
    % section of the module.
    %
:- pred used_modules(module_info::in,
    used_modules::in, used_modules::out) is det.

used_modules(ModuleInfo, !UsedModules) :-
    module_info_get_type_table(ModuleInfo, TypeTable),
    map.foldl(type_used_modules, TypeTable, !UsedModules),

    module_info_get_inst_table(ModuleInfo, InstTable),
    inst_table_get_user_insts(InstTable, UserInstTable),
    user_inst_table_get_inst_defns(UserInstTable, UserInsts),
    map.foldl(user_inst_used_modules, UserInsts, !UsedModules),

    module_info_get_mode_table(ModuleInfo, ModeTable),
    mode_table_get_mode_defns(ModeTable, ModeDefns),
    map.foldl(mode_used_modules, ModeDefns, !UsedModules),

    module_info_get_class_table(ModuleInfo, ClassTable),
    map.foldl(class_used_modules, ClassTable, !UsedModules),

    module_info_get_instance_table(ModuleInfo, InstanceTable),
    map.foldl(instance_used_modules, InstanceTable, !UsedModules),

    module_info_preds(ModuleInfo, PredTable),
    map.foldl(pred_info_used_modules, PredTable, !UsedModules).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred type_used_modules(type_ctor::in, hlds_type_defn::in,
    used_modules::in, used_modules::out) is det.

type_used_modules(_TypeCtor, TypeDefn, !UsedModules) :-
    get_type_defn_status(TypeDefn, ImportStatus),
    get_type_defn_body(TypeDefn, TypeBody),

    ( status_defined_in_this_module(ImportStatus) = yes ->
        Visibility = item_visibility(ImportStatus),
        (
            TypeBody = hlds_du_type(Ctors, _, _, _, _, _, _, _),
            list.foldl(ctor_used_modules(Visibility), Ctors, !UsedModules)
        ;
            TypeBody = hlds_eqv_type(EqvType),
            mer_type_used_modules(Visibility, EqvType, !UsedModules)
        ;
            ( TypeBody = hlds_foreign_type(_)
            ; TypeBody = hlds_solver_type(_, _)
            ; TypeBody = hlds_abstract_type(_)
            )
        )
    ;
        true
    ).

:- pred ctor_used_modules(item_visibility::in, constructor::in,
    used_modules::in, used_modules::out) is det.

ctor_used_modules(Visibility,
        ctor(_, Constraints, _, Args, _), !UsedModules) :-
    list.foldl(prog_constraint_used_module(Visibility), Constraints,
        !UsedModules),
    list.foldl(
        (pred(Arg::in, !.M::in, !:M::out) is det :-
            mer_type_used_modules(Visibility, Arg ^ arg_type, !M)
        ), Args, !UsedModules).

:- pred prog_constraint_used_module(item_visibility::in, prog_constraint::in,
    used_modules::in, used_modules::out) is det.

prog_constraint_used_module(Visibility, constraint(ClassName, Args),
        !UsedModules) :-
    add_sym_name_module(Visibility, ClassName, !UsedModules),
    list.foldl(mer_type_used_modules(Visibility), Args, !UsedModules).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred user_inst_used_modules(inst_id::in, hlds_inst_defn::in,
    used_modules::in, used_modules::out) is det.

user_inst_used_modules(_InstId, InstDefn, !UsedModules) :-
    ImportStatus = InstDefn ^ inst_status,
    ( status_defined_in_this_module(ImportStatus) = yes ->
        Visibility = item_visibility(ImportStatus),
        InstBody = InstDefn ^ inst_body,
        (
            InstBody = eqv_inst(Inst),
            mer_inst_used_modules(Visibility, Inst, !UsedModules)
        ;
            InstBody = abstract_inst
        )
    ;
        true
    ).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred mode_used_modules(mode_id::in, hlds_mode_defn::in,
    used_modules::in, used_modules::out) is det.

mode_used_modules(mode_id(Name, _Arity), ModeDefn, !UsedModules) :-
    ImportStatus = ModeDefn ^ mode_status,
    ( status_defined_in_this_module(ImportStatus) = yes ->
        Visibility = item_visibility(ImportStatus),
        add_sym_name_module(Visibility, Name, !UsedModules),
        ModeBody = ModeDefn ^ mody_body,
        ModeBody = eqv_mode(Mode),
        mer_mode_used_modules(Visibility, Mode, !UsedModules)
    ;
        true
    ).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred class_used_modules(class_id::in, hlds_class_defn::in,
    used_modules::in, used_modules::out) is det.

class_used_modules(class_id(Name, _Arity), ClassDefn, !UsedModules) :-
    ImportStatus = ClassDefn ^ class_status,
    ( status_defined_in_this_module(ImportStatus) = yes ->
        Visibility = item_visibility(ImportStatus),
        add_sym_name_module(Visibility, Name, !UsedModules),
        list.foldl(prog_constraint_used_module(Visibility),
            ClassDefn ^ class_supers, !UsedModules)
    ;
        true
    ).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred instance_used_modules(class_id::in, list(hlds_instance_defn)::in,
    used_modules::in, used_modules::out) is det.

instance_used_modules(ClassId, InstanceDefns, !UsedModules) :-
    list.foldl(instance_used_modules_2(ClassId), InstanceDefns, !UsedModules).

:- pred instance_used_modules_2(class_id::in, hlds_instance_defn::in,
    used_modules::in, used_modules::out) is det.

instance_used_modules_2(class_id(Name, _Arity), InstanceDefn, !UsedModules) :-
    ImportStatus = InstanceDefn ^ instance_status,
    ( status_defined_in_this_module(ImportStatus) = yes ->
        % The methods of the class are stored in the pred_table and hence
        % will be processed by pred_info_used_modules.
        % XXX is this true?
        Visibility = item_visibility(ImportStatus),
        add_sym_name_module(Visibility, Name, !UsedModules),
        list.foldl(prog_constraint_used_module(Visibility),
            InstanceDefn ^ instance_constraints, !UsedModules),
        list.foldl(mer_type_used_modules(Visibility),
            InstanceDefn ^ instance_types, !UsedModules)
    ;
        true
    ).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred pred_info_used_modules(pred_id::in, pred_info::in,
    used_modules::in, used_modules::out) is det.

pred_info_used_modules(_PredId, PredInfo, !UsedModules) :-
    pred_info_get_import_status(PredInfo, ImportStatus),
    ( status_defined_in_this_module(ImportStatus) = yes ->
        Visibility = item_visibility(ImportStatus),

        pred_info_get_arg_types(PredInfo, Args),
        list.foldl(mer_type_used_modules(Visibility), Args, !UsedModules),

        pred_info_get_class_context(PredInfo, Constraints),
        Constraints = constraints(UnivConstraints, ExistConstraints),
        list.foldl(prog_constraint_used_module(Visibility),
            UnivConstraints, !UsedModules),
        list.foldl(prog_constraint_used_module(Visibility),
            ExistConstraints, !UsedModules),

        pred_info_get_procedures(PredInfo, ProcTable),
        map.foldl(proc_info_used_modules(Visibility), ProcTable, !UsedModules),

        pred_info_get_clauses_info(PredInfo, ClausesInfo),
        clauses_info_used_modules(ClausesInfo, !UsedModules)
    ;
        true
    ).

:- pred proc_info_used_modules(item_visibility::in, proc_id::in, proc_info::in,
    used_modules::in, used_modules::out) is det.

proc_info_used_modules(Visibility, _ProcId, ProcInfo, !UsedModules) :-
    proc_info_get_maybe_declared_argmodes(ProcInfo, MaybeArgModes),
    (
        MaybeArgModes = yes(Modes),
        list.foldl(mer_mode_used_modules(Visibility), Modes, !UsedModules)
    ;
        MaybeArgModes = no
    ).

:- pred clauses_info_used_modules(clauses_info::in,
    used_modules::in, used_modules::out) is det.

clauses_info_used_modules(ClausesInfo, !UsedModules) :-
    clauses_info_get_clauses_rep(ClausesInfo, ClausesRep),
    get_clause_list(ClausesRep, Clauses),
    list.foldl(clause_used_modules, Clauses, !UsedModules).

:- pred clause_used_modules(clause::in,
    used_modules::in, used_modules::out) is det.

clause_used_modules(clause(_, Goal, _, _), !UsedModules) :-
    hlds_goal_used_modules(Goal, !UsedModules).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred hlds_goal_used_modules(hlds_goal::in,
    used_modules::in, used_modules::out) is det.

hlds_goal_used_modules(hlds_goal(GoalExpr, _), !UsedModules) :-
    hlds_goal_expr_used_modules(GoalExpr, !UsedModules).

:- pred hlds_goal_expr_used_modules(hlds_goal_expr::in,
    used_modules::in, used_modules::out) is det.

hlds_goal_expr_used_modules(unify(_, Rhs, _, _, _), !UsedModules) :-
    unify_rhs_used_modules(Rhs, !UsedModules).
hlds_goal_expr_used_modules(plain_call(_, _, _, _, _, Name), !UsedModules) :-
    add_sym_name_module(visibility_private, Name, !UsedModules).
hlds_goal_expr_used_modules(generic_call(Call, _, _, _), !UsedModules) :-
    (
        Call = class_method(_, _, ClassId, CallId),
        ClassId = class_id(ClassName, _),
        add_sym_name_module(visibility_private, ClassName, !UsedModules),

        CallId = simple_call_id(_, MethodName, _),
        add_sym_name_module(visibility_private, MethodName, !UsedModules)
    ;
        ( Call = higher_order(_, _, _, _)
        ; Call = event_call(_)
        ; Call = cast(_)
        )
    ).
hlds_goal_expr_used_modules(call_foreign_proc(_, _, _, _, _, _, _),
        !UsedModules).
hlds_goal_expr_used_modules(conj(_, Goals), !UsedModules) :-
    list.foldl(hlds_goal_used_modules, Goals, !UsedModules).
hlds_goal_expr_used_modules(disj(Goals), !UsedModules) :-
    list.foldl(hlds_goal_used_modules, Goals, !UsedModules).
hlds_goal_expr_used_modules(switch(_, _, Cases), !UsedModules) :-
    list.foldl(case_used_modules, Cases, !UsedModules).
hlds_goal_expr_used_modules(negation(Goal), !UsedModules) :-
    hlds_goal_used_modules(Goal, !UsedModules).
hlds_goal_expr_used_modules(scope(_, Goal), !UsedModules) :-
    hlds_goal_used_modules(Goal, !UsedModules).
hlds_goal_expr_used_modules(if_then_else(_, If, Then, Else), !UsedModules) :-
    hlds_goal_used_modules(If, !UsedModules),
    hlds_goal_used_modules(Then, !UsedModules),
    hlds_goal_used_modules(Else, !UsedModules).
hlds_goal_expr_used_modules(shorthand(bi_implication(GoalA, GoalB)),
        !UsedModules) :-
    hlds_goal_used_modules(GoalA, !UsedModules),
    hlds_goal_used_modules(GoalB, !UsedModules).

:- pred case_used_modules(case::in, used_modules::in, used_modules::out)
    is det.

case_used_modules(Case, !UsedModules) :-
    Case = case(MainConsId, OtherConsIds, Goal),
    cons_id_used_modules(visibility_private, MainConsId, !UsedModules),
    list.foldl(cons_id_used_modules(visibility_private), OtherConsIds,
        !UsedModules),
    hlds_goal_used_modules(Goal, !UsedModules).

:- pred unify_rhs_used_modules(unify_rhs::in,
    used_modules::in, used_modules::out) is det.

unify_rhs_used_modules(rhs_var(_), !UsedModules).
unify_rhs_used_modules(rhs_functor(ConsId, _, _), !UsedModules) :-
    cons_id_used_modules(visibility_private, ConsId, !UsedModules).
unify_rhs_used_modules(rhs_lambda_goal(_, _, _, _, _, _, _, Goal),
        !UsedModules) :-
    hlds_goal_used_modules(Goal, !UsedModules).

:- pred cons_id_used_modules(item_visibility::in, cons_id::in,
    used_modules::in, used_modules::out) is det.

cons_id_used_modules(Visibility, cons(Name, _), !UsedModules) :-
    add_sym_name_module(Visibility, Name, !UsedModules).
cons_id_used_modules(_, int_const(_), !UsedModules).
cons_id_used_modules(_, string_const(_), !UsedModules).
cons_id_used_modules(_, float_const(_), !UsedModules).
cons_id_used_modules(_, pred_const(_, _), !UsedModules).
cons_id_used_modules(Visibility,
        type_ctor_info_const(ModuleName, _, _), !UsedModules) :-
    add_all_modules(Visibility, ModuleName, !UsedModules).
cons_id_used_modules(Visibility,
        base_typeclass_info_const(ModuleName, _, _, _), !UsedModules) :-
    add_all_modules(Visibility, ModuleName, !UsedModules).
cons_id_used_modules(Visibility,
        type_info_cell_constructor(type_ctor(SymName, _Arity)),
        !UsedModules) :-
    add_sym_name_module(Visibility, SymName, !UsedModules).
cons_id_used_modules(_, typeclass_info_cell_constructor, !UsedModules).
cons_id_used_modules(_, tabling_info_const(_), !UsedModules).
cons_id_used_modules(_, deep_profiling_proc_layout(_), !UsedModules).
cons_id_used_modules(_, table_io_decl(_), !UsedModules).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred mer_type_used_modules(item_visibility::in, mer_type::in,
    used_modules::in, used_modules::out) is det.

mer_type_used_modules(Visibility, Type, !UsedModules) :-
    mer_type_used_modules_2(Visibility, Type, !UsedModules).

:- pred mer_type_used_modules_2(item_visibility::in, mer_type::in,
    used_modules::in, used_modules::out) is det.

mer_type_used_modules_2(_Status, type_variable(_, _), !UsedModules).
mer_type_used_modules_2(Visibility, defined_type(Name, Args, _),
        !UsedModules) :-
    add_sym_name_module(Visibility, Name, !UsedModules),
    list.foldl(mer_type_used_modules(Visibility), Args, !UsedModules).
mer_type_used_modules_2(_Status, builtin_type(_), !UsedModules).
mer_type_used_modules_2(Visibility,
        higher_order_type(Args, MaybeReturn, _, _), !UsedModules) :-
    list.foldl(mer_type_used_modules(Visibility), Args, !UsedModules),
    (
        MaybeReturn = yes(Return),
        mer_type_used_modules(Visibility, Return, !UsedModules)
    ;
        MaybeReturn = no
    ).
mer_type_used_modules_2(Visibility, tuple_type(Args, _), !UsedModules) :-
    list.foldl(mer_type_used_modules(Visibility), Args, !UsedModules).
mer_type_used_modules_2(Visibility, apply_n_type(_, Args, _), !UsedModules) :-
    list.foldl(mer_type_used_modules(Visibility), Args, !UsedModules).
mer_type_used_modules_2(Visibility, kinded_type(Arg, _), !UsedModules) :-
    mer_type_used_modules(Visibility, Arg, !UsedModules).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred mer_mode_used_modules(item_visibility::in, mer_mode::in,
    used_modules::in, used_modules::out) is det.

mer_mode_used_modules(Visibility, Inst0 -> Inst, !UsedModules) :-
    mer_inst_used_modules(Visibility, Inst0, !UsedModules),
    mer_inst_used_modules(Visibility, Inst, !UsedModules).
mer_mode_used_modules(Visibility, user_defined_mode(Name, Insts),
        !UsedModules) :-
    add_sym_name_module(Visibility, Name, !UsedModules),
    list.foldl(mer_inst_used_modules(Visibility), Insts, !UsedModules).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred mer_inst_used_modules(item_visibility::in, mer_inst::in,
    used_modules::in, used_modules::out) is det.

mer_inst_used_modules(_, any(_), !UsedModules).
mer_inst_used_modules(_, free, !UsedModules).
mer_inst_used_modules(Visibility, free(Type), !UsedModules) :-
    mer_type_used_modules(Visibility, Type, !UsedModules).
mer_inst_used_modules(Visibility, bound(_, BoundInsts), !UsedModules) :-
    list.foldl(bound_inst_info_used_modules(Visibility), BoundInsts,
        !UsedModules).
mer_inst_used_modules(Visibility, ground(_, GroundInstInfo), !UsedModules) :-
    ground_inst_info_used_modules(Visibility, GroundInstInfo, !UsedModules).
mer_inst_used_modules(_, not_reached, !UsedModules).
mer_inst_used_modules(_, inst_var(_), !UsedModules).
mer_inst_used_modules(Visibility, constrained_inst_vars(_InstVars, Inst),
        !UsedModules) :-
    mer_inst_used_modules(Visibility, Inst, !UsedModules).
mer_inst_used_modules(Visibility, defined_inst(InstName), !UsedModules) :-
    inst_name_used_modules(Visibility, InstName, !UsedModules).
mer_inst_used_modules(Visibility, abstract_inst(Name, Insts), !UsedModules) :-
    add_sym_name_module(Visibility, Name, !UsedModules),
    list.foldl(mer_inst_used_modules(Visibility), Insts, !UsedModules).

%-----------------------------------------------------------------------------%

:- pred bound_inst_info_used_modules(item_visibility::in, bound_inst::in,
    used_modules::in, used_modules::out) is det.

bound_inst_info_used_modules(Visibility, bound_functor(ConsId, Insts),
        !UsedModules) :-
    cons_id_used_modules(Visibility, ConsId, !UsedModules),
    list.foldl(mer_inst_used_modules(Visibility), Insts, !UsedModules).

:- pred ground_inst_info_used_modules(item_visibility::in,
    ground_inst_info::in, used_modules::in, used_modules::out) is det.

ground_inst_info_used_modules(Visibility,
        higher_order(pred_inst_info(_, Modes, _)), !UsedModules) :-
    list.foldl(mer_mode_used_modules(Visibility), Modes, !UsedModules).
ground_inst_info_used_modules(_, none, !UsedModules).

%-----------------------------------------------------------------------------%

:- pred inst_name_used_modules(item_visibility::in, inst_name::in,
    used_modules::in, used_modules::out) is det.

inst_name_used_modules(Visibility, user_inst(Name, Insts), !UsedModules) :-
    add_sym_name_module(Visibility, Name, !UsedModules),
    list.foldl(mer_inst_used_modules(Visibility), Insts, !UsedModules).
inst_name_used_modules(Visibility, merge_inst(Inst0, Inst), !UsedModules) :-
    mer_inst_used_modules(Visibility, Inst0, !UsedModules),
    mer_inst_used_modules(Visibility, Inst, !UsedModules).
inst_name_used_modules(Visibility, unify_inst(_, Inst0, Inst, _),
        !UsedModules) :-
    mer_inst_used_modules(Visibility, Inst0, !UsedModules),
    mer_inst_used_modules(Visibility, Inst, !UsedModules).
inst_name_used_modules(Visibility, ground_inst(InstName, _, _, _),
        !UsedModules) :-
    inst_name_used_modules(Visibility, InstName, !UsedModules).
inst_name_used_modules(Visibility, any_inst(InstName, _, _, _),
        !UsedModules) :-
    inst_name_used_modules(Visibility, InstName, !UsedModules).
inst_name_used_modules(Visibility, shared_inst(InstName), !UsedModules) :-
    inst_name_used_modules(Visibility, InstName, !UsedModules).
inst_name_used_modules(Visibility, mostly_uniq_inst(InstName), !UsedModules) :-
    inst_name_used_modules(Visibility, InstName, !UsedModules).
inst_name_used_modules(Visibility, typed_ground(_, Type), !UsedModules) :-
    mer_type_used_modules(Visibility, Type, !UsedModules).
inst_name_used_modules(Visibility, typed_inst(Type, InstName), !UsedModules) :-
    mer_type_used_modules(Visibility, Type, !UsedModules),
    inst_name_used_modules(Visibility, InstName, !UsedModules).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

    % Determine if the given import_status implies item is visibility_public
    % (in the interface) or visibility_private (in the implementation).
    %
:- func item_visibility(import_status) = item_visibility.

item_visibility(ImportStatus) =
    ( status_is_exported_to_non_submodules(ImportStatus) = yes ->
        visibility_public
    ;
        visibility_private
    ).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
