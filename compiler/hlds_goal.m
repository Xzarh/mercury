%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 1996-2006 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: hlds_goal.m.
% Main authors: fjh, conway.
%
% The module defines the part of the HLDS that deals with goals.
%
%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- module hlds.hlds_goal.
:- interface.

:- import_module hlds.hlds_llds.
:- import_module hlds.hlds_pred.
:- import_module hlds.instmap.
:- import_module mdbcomp.prim_data.
:- import_module parse_tree.prog_data.

:- import_module bool.
:- import_module char.
:- import_module list.
:- import_module map.
:- import_module maybe.
:- import_module pair.
:- import_module set.
:- import_module term.

%-----------------------------------------------------------------------------%
%
% Goal representation.
%

:- type hlds_goals  == list(hlds_goal).

:- type hlds_goal   == pair(hlds_goal_expr, hlds_goal_info).

:- type hlds_goal_expr

    --->    unify(
                % A unification. Initially only the terms and the context
                % are known. Mode analysis fills in the missing information.

                unify_lhs           :: prog_var,
                                    % The variable on the left hand side
                                    % of the unification.  NOTE: for
                                    % convenience this field is duplicated
                                    % in the unification structure below.

                unify_rhs           :: unify_rhs,
                                    % Whatever is on the right hand side
                                    % of the unification.

                unify_mode          :: unify_mode,
                                    % the mode of the unification.

                unify_kind          :: unification,
                                    % This field says what category of
                                    % unification it is, and contains
                                    % information specific to each category.

                unify_context       :: unify_context
                                    % The location of the unification
                                    % in the original source code
                                    % (for use in error messages).
            )

    ;       plain_call(
                % A predicate call. Initially only the sym_name, arguments,
                % and context are filled in. Type analysis fills in the
                % pred_id. Mode analysis fills in the proc_id and
                % builtin_state fields.

                call_pred_id        :: pred_id,
                                    % Which predicate are we calling?

                call_proc_id        :: proc_id,
                                    % Which mode of the predicate?

                call_args           :: list(prog_var),
                                    % The list of argument variables.

                call_builtin        :: builtin_state,
                                    % Is the predicate builtin, and if yes,
                                    % do we generate inline code for it?

                call_unify_context  :: maybe(call_unify_context),
                                    % Was this predicate call originally
                                    % a unification? If so, we store the
                                    % context of the unification.

                call_sym_name       :: sym_name
                                    % The name of the predicate.
            )

    ;       generic_call(
                % A generic call implements operations which are too
                % polymorphic to be written as ordinary predicates in Mercury
                % and require special casing, either because their arity is
                % variable, or they take higher-order arguments of variable
                % arity. This currently includes higher-order calls and
                % class-method calls.
                %
                gcall_details       :: generic_call,

                gcall_args          :: list(prog_var),
                                    % The list of argument variables.

                gcall_modes         :: list(mer_mode),
                                    % The modes of the argument variables.
                                    % For higher_order calls, this field
                                    % is junk until after mode analysis.

                gcall_detism        :: determinism
                                    % The determinism of the call.
            )

    ;       call_foreign_proc(
                % Foreign code from a pragma foreign_proc(...) decl.

                foreign_attr        :: pragma_foreign_proc_attributes,

                foreign_pred_id     :: pred_id,
                                    % The called predicate.

                foreign_proc_id     :: proc_id,
                                    % The mode of the predicate.

                foreign_args        :: list(foreign_arg),
                foreign_extra_args  :: list(foreign_arg),
                                    % Extra arguments added when compiler
                                    % passes such as tabling stuff more
                                    % code into a foreign proc than the
                                    % declared interface of the called
                                    % Mercury procedure would allow.

                foreign_trace_cond  :: maybe(trace_expr(trace_runtime)),
                                    % If set to yes(Cond), then this goal
                                    % represents the evaluation of the runtime
                                    % condition of a trace goal. In that case,
                                    % the goal must be semidet, and the
                                    % argument lists empty; the actual code
                                    % in pragma_foreign_code_impl is ignored
                                    % and replaced by the evaluation of Cond.

                foreign_impl        :: pragma_foreign_code_impl
                                    % Extra information for model_non
                                    % pragma_foreign_codes; none for others.
            )

    ;       conj(conj_type, hlds_goals)
            % A conjunction. NOTE: plain conjunctions must be fully flattened
            % before mode analysis. As a general rule, it is a good idea to
            % keep them flattened.

    ;       disj(hlds_goals)
            % A disjunction.
            % NOTE: disjunctions should be fully flattened.

    ;       switch(
                % Deterministic disjunctions are converted into switches
                % by the switch detection pass.

                switch_var          :: prog_var,
                                    % The variable we are switching on.

                switch_canfail      :: can_fail,
                                    % Whether or not the switch test itself
                                    % can fail (i.e. whether or not it
                                    % covers all the possible cases).

                switch_cases        :: list(case)
            )

    ;       negation(hlds_goal)
            % A negation.

    ;       scope(
                % A scope which may be the scope of a quantification,
                % or may be introduced by a compiler transformation.
                % See the documentation of scope_reason for what the
                % compiler may do with the scope.

                scope_reason        :: scope_reason,
                scope_goal          :: hlds_goal
            )

    ;       if_then_else(
                % An if-then-else,
                % `if some <Vars> <Condition> then <Then> else <Else>'.
                % The scope of the locally existentially quantified variables
                % <Vars> is over the <Condition> and the <Then> part,
                % but not the <Else> part.

                ite_exist_vars      :: list(prog_var),
                                    % The locally existentially quantified
                                    % variables <Vars>.

                ite_cond            :: hlds_goal,   % The <Condition>
                ite_then            :: hlds_goal,   % The <Then> part
                ite_else            :: hlds_goal    % The <Else> part
            )

    ;       shorthand(shorthand_goal_expr).
            % Goals that stand for some other, usually bigger goal.
            % All shorthand goals are eliminated during or shortly after
            % the construction of the HLDS, so most passes of the compiler
            % will just call error/1 if they occur.

:- type conj_type
    --->    plain_conj
    ;       parallel_conj.

:- type after_semantic_analysis
    --->    before_semantic_analysis
    ;       after_semantic_analysis.

    % Instances of these `shorthand' goals are implemented by a
    % hlds --> hlds transformation that replaces them with
    % equivalent non-shorthand goals.
    %
:- type shorthand_goal_expr
            % bi-implication (A <=> B)
            %
            % Note that ordinary implications (A => B)
            % and reverse implications (A <= B) are expanded
            % out before we construct the HLDS.  But we can't
            % do that for bi-implications, because if expansion
            % of bi-implications is done before implicit quantification,
            % then the quantification would be wrong.
            %
    --->    bi_implication(hlds_goal, hlds_goal).

:- type scope_reason
    --->    exist_quant(list(prog_var))
            % The goal inside the scope construct has the listed variables
            % existentially quantified. The compiler may do whatever
            % preserves this fact.

    ;       promise_solutions(list(prog_var), promise_solutions_kind)
            % Even though the code inside the scope may have multiple
            % solutions, the creator of the scope (which may be the user
            % or a compiler pass) promises that all these solutions are
            % equivalent relative to the relevant equality theory.
            % (This need not be an equality theory known to the compiler.)
            % The scope goal will therefore act as a single solution
            % context, and the determinism of the scope() goal itself
            % will indicate that it cannot succeed more than once.
            %
            % This acts like the builtin.promise_only_solution predicate,
            % but without requiring the construction of a closure, a
            % higher order call, and the squeezing of all outputs into
            % a single variable.
            %
            % The promise is valid only if the list of outputs of the goal
            % inside the scope is a subset of the variables listed here.
            % If it is not valid, the compiler must emit an error message.

    ;       promise_purity(implicit_purity_promise, purity)
            % The goal inside the scope implements an interface of the
            % specified purity, even if its implementation uses less pure
            % components.
            %
            % Works the same way as a promise_pure or promise_semipure
            % pragma, except that it applies to arbitrary goals and not
            % just whole procedure bodies. The implicit_purity_promise
            % says whether or not the compiler requires explicit purity
            % annotations on the goals inside the scope.

    ;       commit(force_pruning)
            % This scope exists to delimit a piece of code
            % with at_most_many components but with no outputs,
            % whose overall determinism is thus at_most_one,
            % or a piece of code that cannot succeed but some of whose
            % components are at_most_many (regardless of the number of
            % outputs).
            %
            % If the argument is force_pruning, then the outer goal will
            % succeed at most once even if the inner goal is impure.

    ;       barrier(removable)
            % The scope exists to prevent other compiler passes from
            % arbitrarily moving computations in or out of the scope.
            % This kind of scope can only be introduced by program
            % transformations.
            %
            % The argument says whether other compiler passes are allowed
            % to delete the scope.
            %
            % A non-removable explicit quantification may be introduced
            % to keep related goals together where optimizations that
            % separate the goals can only result in worse behaviour.
            %
            % A barrier says nothing about the determinism of either
            % the inner or the outer goal, or about pruning.

    ;       from_ground_term(prog_var)
            % The goal inside the scope, which should be a conjunction,
            % results from the conversion of one ground term to
            % superhomogeneous form. The variable specifies what the
            % compiler calls that ground term.
            %
            % This kind of scope is not intended to be meaningful after
            % mode analysis, and should be removed after mode analysis.

    ;       trace_goal(
                trace_compiletime   :: maybe(trace_expr(trace_compiletime)),
                trace_runtime       :: maybe(trace_expr(trace_runtime)),
                trace_maybe_io      :: maybe(string),
                trace_mutable_vars  :: list(trace_mutable_var_hlds)
            ).
            % The goal inside the scope is trace code that is executed only
            % conditionally, and should have no effect on the semantics of
            % the program even if executed.
            %
            % The trace goal is removed by simplification if the compile time
            % condition isn't true. If it is true, the code generator will
            % generate code that will execute the goal inside the scope
            % only if the runtime condition is satisfied.
            %
            % The maybe_io and mutable_vars fields are advisory only in the
            % HLDS, since they are fully processed when the corresponding goal
            % in the parse tree is converted to HLDS.

:- type promise_solutions_kind
    --->    equivalent_solutions
    ;       equivalent_solution_sets
    ;       equivalent_solution_sets_arbitrary.

:- type removable
    --->    removable
    ;       not_removable.

:- type force_pruning
    --->    force_pruning
    ;       dont_force_pruning.

:- type trace_mutable_var_hlds
    --->    trace_mutable_var_hlds(
                tmvh_mutable_name       :: string,
                tmvh_state_var_name     :: string
            ).

%-----------------------------------------------------------------------------%
%
% Information for calls
%

    % There may be two sorts of "builtin" predicates - those that we open-code
    % using inline instructions (e.g. arithmetic predicates), and those which
    % are still "internal", but for which we generate a call to an out-of-line
    % procedure. At the moment there are no builtins of the second sort,
    % although we used to handle call/N that way.

:- type builtin_state
    --->    inline_builtin
    ;       out_of_line_builtin
    ;       not_builtin.

%-----------------------------------------------------------------------------%
%
% Information for call_foreign_proc
%

    % In the usual case, the arguments of a foreign_proc are the arguments
    % of the call to the predicate whose implementation is in the foreign
    % language. Each such argument is described by a foreign_arg.
    %
    % The arg_var field gives the identity of the actual parameter.
    %
    % The arg_name_mode field gives the foreign variable name and the original
    % mode declaration for the argument; a no means that the argument is not
    % used by the foreign code. (In particular, the type_info variables
    % introduced by polymorphism.m might be represented in this way).
    %
    % The arg_type field gives the original types of the arguments.
    % (With inlining, the actual type may be an instance of the original type.)
    %
:- type foreign_arg
    --->    foreign_arg(
                arg_var         :: prog_var,
                arg_name_mode   :: maybe(pair(string, mer_mode)),
                arg_type        :: mer_type,
                arg_box_policy  :: box_policy
            ).

:- func foreign_arg_var(foreign_arg) = prog_var.
:- func foreign_arg_maybe_name_mode(foreign_arg) =
    maybe(pair(string, mer_mode)).
:- func foreign_arg_type(foreign_arg) = mer_type.
:- func foreign_arg_box(foreign_arg) = box_policy.

:- pred make_foreign_args(list(prog_var)::in,
    list(pair(maybe(pair(string, mer_mode)), box_policy))::in,
    list(mer_type)::in, list(foreign_arg)::out) is det.

%-----------------------------------------------------------------------------%
%
% Information for generic_calls
%

:- type generic_call
    --->    higher_order(
                prog_var,
                purity,
                pred_or_func,   % call/N (pred) or apply/N (func)
                arity           % number of arguments (including the
                                % higher-order term)
            )

    ;       class_method(
                prog_var,       % typeclass_info for the instance
                int,            % number of the called method
                class_id,       % name and arity of the class
                simple_call_id  % name of the called method
            )

    ;       cast(cast_type).
            % cast(Input, Output): Assigns `Input' to `Output', performing
            % a type and/or inst cast.

    % The various kinds of casts that we can do.
    %
:- type cast_type
    --->    unsafe_type_cast
            % An unsafe type cast between ground values.

    ;       unsafe_type_inst_cast
            % An unsafe type and inst cast.

    ;       equiv_type_cast
            % A safe type cast between equivalent types, in either direction.

    ;       exists_cast.
            % A safe cast between an internal type_info or typeclass_info
            % variable, for which the bindings of existential type variables
            % are known statically, to an external type_info or typeclass_info
            % head variable, for which they are not. These are used instead of
            % assignments so that the simplification pass does not attempt
            % to merge the two variables, which could lead to inconsistencies
            % in the rtti_varmaps.

    % Get a description of a generic_call goal.
    %
:- pred generic_call_id(generic_call::in, call_id::out) is det.

    % Determine whether a generic_call is calling
    % a predicate or a function.
    %
:- func generic_call_pred_or_func(generic_call) = pred_or_func.

%-----------------------------------------------------------------------------%
%
% Information for unifications
%

    % Initially all unifications are represented as
    % unify(prog_var, unify_rhs, _, _, _), but mode analysis replaces
    % these with various special cases (construct/deconstruct/assign/
    % simple_test/complicated_unify).
    %
:- type unify_rhs
    --->    rhs_var(prog_var)
    ;       rhs_functor(
                rhs_functor         :: cons_id,
                rhs_is_exist_constr :: is_existential_construction,
                                    % The `is_existential_construction' field
                                    % is only used after polymorphism.m strips
                                    % off the `new ' prefix from existentially
                                    % typed constructions.
                rhs_args            :: list(prog_var)
            )
    ;       rhs_lambda_goal(
                rhs_purity          :: purity,
                rhs_p_or_f          :: pred_or_func,
                rhs_eval_method     :: lambda_eval_method,
                                    % Currently, we don't support any other
                                    % value than `normal'.
                rhs_nonlocals       :: list(prog_var),
                                    % Non-locals of the goal excluding
                                    % the lambda quantified variables.
                rhs_lambda_quant_vars :: list(prog_var),
                                    % Lambda quantified variables.
                rhs_lambda_modes    :: list(mer_mode),
                                    % Modes of the lambda quantified variables.
                rhs_detism          :: determinism,
                rhs_lambda_goal     :: hlds_goal
            ).

    % Was the constructor originally of the form 'new ctor'(...).
    %
:- type is_existential_construction == bool.

    % This type contains the fields of a construct unification that are needed
    % only rarely. If a value of this type is bound to no_construct_sub_info,
    % this means the same as construct_sub_info(no, no), but takes less space.
    % This matters because a modules have lots of construct unifications.
:- type construct_sub_info
    --->    construct_sub_info(
                take_address_fields     :: maybe(list(int)),

                term_size_slot          :: maybe(term_size_value)
                                        % The value `yes' tells the code
                                        % generator to reserve an extra slot,
                                        % at offset -1, to hold an integer
                                        % giving the size of the term.
                                        % The argument specifies the value
                                        % to be put into this slot, either
                                        % as an integer constant or as the
                                        % value of a given variable.
                                        %
                                        % The value `no' means there is no
                                        % extra slot, and is the default.
                                        %
                                        % The content of this slot is not
                                        % meaningful before the size_prof pass
                                        % has been run.
            )
    ;       no_construct_sub_info.

:- type unification

    --->    construct(
                % A construction unification is a unification with a functor
                % or lambda expression which binds the LHS variable,
                % e.g. Y = f(X) where the top node of Y is output,
                % Constructions are written using `:=', e.g. Y := f(X).

                construct_cell_var      :: prog_var,
                                        % The variable being constructed,
                                        % e.g. Y in above example.

                construct_cons_id       :: cons_id,
                                        % The cons_id of the functor
                                        % f/1 in the above example.

                construct_args          :: list(prog_var),
                                        % The list of argument variables
                                        % [X] in the above example
                                        % For a unification with a lambda
                                        % expression, this is the list of
                                        % the non-local variables of the
                                        % lambda expression.

                construct_arg_modes     :: list(uni_mode),
                                        % The list of modes of the arguments
                                        % sub-unifications.
                                        % For a unification with a lambda
                                        % expression, this is the list of
                                        % modes of the non-local variables
                                        % of the lambda expression.

                construct_how           :: how_to_construct,
                                        % Specify whether to allocate
                                        % statically, to allocate dynamically,
                                        % or to reuse an existing cell
                                        % (and if so, which cell).
                                        % Constructions for which this
                                        % field is `reuse_cell(_)' are
                                        % described as "reconstructions".

                construct_is_unique     :: cell_is_unique,
                                        % Can the cell be allocated
                                        % in shared data.

                construct_sub_info      :: construct_sub_info
            )

    ;       deconstruct(
                % A deconstruction unification is a unification with a functor
                % for which the LHS variable was already bound,
                % e.g. Y = f(X) where the top node of Y is input.
                % Deconstructions are written using `==', e.g. Y == f(X).
                % Note that deconstruction of lambda expressions is
                % a mode error.

                deconstruct_cell_var    :: prog_var,
                                        % The variable being deconstructed
                                        % e.g. Y in the above example.

                deconstruct_cons_id     :: cons_id,
                                        % The cons_id of the functor,
                                        % e.g. f/1 in the above example

                deconstruct_args        :: list(prog_var),
                                        % The list of argument variables,
                                        % e.g. [X] in the above example.

                deconstruct_arg_modes   :: list(uni_mode),
                                        % The lists of modes of the argument
                                        % sub-unifications.

                deconstruct_can_fail    :: can_fail,
                                        % Whether or not the unification
                                        % could possibly fail.

                deconstruct_can_cgc     :: can_cgc
                                        % Can compile time GC this cell,
                                        % i.e. explicitly deallocate it
                                        % after the deconstruction.
            )

    ;       assign(
                % Y = X where the top node of Y is output, written Y := X.

                assign_to_var           :: prog_var,
                assign_from_var         :: prog_var
            )

    ;       simple_test(
                % Y = X where the type of X and Y is an atomic type and
                % they are both input, written Y == X.
                %
                test_var1               :: prog_var,
                test_var2               :: prog_var
            )

    ;       complicated_unify(
                % Y = X where the type of Y and X is not an atomic type,
                % and where the top-level node of both Y and X is input.
                % May involve bi-directional data flow. Implemented using
                % out-of-line call to a compiler generated unification
                % predicate for that type & mode.

                compl_unify_mode        :: uni_mode,
                                        % The mode of the unification.

                compl_unify_can_fail    :: can_fail,
                                        % Whether or not it could possibly
                                        % fail.

                % When unifying polymorphic types such as map/2, we need to
                % pass type_info variables to the unification procedure for
                % map/2 so that it knows how to unify the polymorphically
                % typed components of the data structure. Likewise for
                % comparison predicates. This field records which type_info
                % variables we will need. This field is set by polymorphism.m.
                % It is used by quantification.m when recomputing the
                % nonlocals. It is also used by modecheck_unify.m, which
                % checks that the type_info variables needed are all ground.
                % It is also checked by simplify.m when it converts
                % complicated unifications into procedure calls.

                compl_unify_typeinfos   :: list(prog_var)
                                        % The type_info variables needed
                                        % by this unification, if it ends up
                                        % being a complicated unify.
            ).

:- type term_size_value
    --->    known_size(
                int                     % The cell being created has this size.
            )
    ;       dynamic_size(
                prog_var                % This variable contains the size of
                                        % the cell being created.
            ).

    % `can_cgc' iff the cell is available for compile time garbage collection.
    % Compile time garbage collection is when the compiler recognises that
    % a memory cell is no longer needed and can be safely deallocated
    % (by inserting an explicit call to free).
    %
:- type can_cgc
    --->    can_cgc
    ;       cannot_cgc.

    % A unify_context describes the location in the original source
    % code of a unification, for use in error messages.
    %
:- type unify_context
    --->    unify_context(
                unify_main_context,
                unify_sub_contexts
            ).

    % A unify_main_context describes overall location of the
    % unification within a clause
    %
:- type unify_main_context
    --->    umc_explicit
            % An explicit call to =/2.

    ;       umc_head(
            % A unification in an argument of a clause head.

                int         % The argument number (first argument == no. 1)
            )

    ;       umc_head_result
            % A unification in the function result term of a clause head.

    ;       umc_call(
                % A unification in an argument of a predicate call.

                call_id,    % The name and arity of the predicate.
                int         % The argument number (first arg == 1).
            )

    ;       umc_implicit(
                % A unification added by some syntactic transformation
                % (e.g. for handling state variables).

                string      % Used to explain the source of the unification.
            ).

    % A unify_sub_context describes the location of sub-unification
    % (which is unifying one argument of a term) within a particular
    % unification.
    %
:- type unify_sub_context
    ==  pair(
            cons_id,    % The functor.
            int         % The argument number (first arg == 1).
        ).

:- type unify_sub_contexts == list(unify_sub_context).

    % A call_unify_context is used for unifications that get turned into
    % calls to out-of-line unification predicates, and functions.  It records
    % which part of the original source code the unification (which may be
    % a function application) occurred in.
    %
:- type call_unify_context
    --->    call_unify_context(
                prog_var,       % The LHS of the unification.
                unify_rhs,      % The RHS of the unification.
                unify_context   % The context of the unification.
            ).

    % Information on how to construct the cell for a construction unification.
    % The `construct_statically' alternative is set by the mark_static_terms.m
    % pass, and is currently only used for the MLDS back-end (for the LLDS
    % back-end, the same optimization is handled by var_locn.m). The
    % `reuse_cell' alternative is not yet used.
    %
:- type how_to_construct
    --->    construct_statically(
                % Use a statically initialized constant.

                args :: list(static_cons)
            )
    ;       construct_dynamically
            % Allocate a new term on the heap

    ;       reuse_cell(cell_to_reuse).
            % Reuse an existing heap cell.

    % Information on how to construct an argument for a static construction
    % unification. Each such argument must itself have been constructed
    % statically; we store here a subset of the fields of the original
    % `construct' unification for the arg. This is used by the MLDS back-end.
    %
:- type static_cons
    --->    static_cons(
                cons_id,            % The cons_id of the functor.
                list(prog_var),     % The list of arg variables.
                list(static_cons)   % How to construct the args.
            ).

    % Information used to perform structure reuse on a cell.
    %
:- type cell_to_reuse
    --->    cell_to_reuse(
                prog_var,
                list(cons_id),      % The cell to be reused may be tagged
                                    % with one of these cons_ids.
                list(bool)          % A `no' entry means that the corresponding
                                    % argument already has the correct value
                                    % and does not need to be filled in.
            ).

    % Cells marked `cell_is_shared' can be allocated in read-only memory,
    % and can be shared.
    % Cells marked `cell_is_unique' must be writeable, and therefore
    % cannot be shared.
    % `cell_is_unique' is always a safe approximation.
    %
:- type cell_is_unique
    --->    cell_is_unique
    ;       cell_is_shared.

:- type unify_mode  ==  pair(mer_mode, mer_mode).

:- type uni_mode    --->    pair(mer_inst) -> pair(mer_inst).
                    % Each uni_mode maps a pair of insts to a pair of new insts
                    % Each pair represents the insts of the LHS and the RHS
                    % respectively.

%-----------------------------------------------------------------------------%
%
% Information for switches
%

:- type case
    --->    case(
                case_functor    :: cons_id,    % functor to match with,
                case_goal       :: hlds_goal   % goal to execute if match
                                               % succeeds.
            ).

%-----------------------------------------------------------------------------%
%
% Information for all kinds of goals
%

%
% Access predicates for the hlds_goal_info data structure.
% For documentation on the meaning of the fields that these
% procedures access, see the definition of the hlds_goal_info type.
%

:- type hlds_goal_info.
:- type hlds_goal_code_gen_info.
:- type hlds_goal_extra_info.

:- pred goal_info_init(hlds_goal_info::out) is det.
:- pred goal_info_init(prog_context::in, hlds_goal_info::out) is det.
:- pred goal_info_init(set(prog_var)::in, instmap_delta::in, determinism::in,
    purity::in, hlds_goal_info::out) is det.
:- pred goal_info_init(set(prog_var)::in, instmap_delta::in, determinism::in,
    purity::in, prog_context::in, hlds_goal_info::out) is det.

% Instead of recording the liveness of every variable at every
% part of the goal, we just keep track of the initial liveness
% and the changes in liveness.  Note that when traversing forwards
% through a goal, deaths must be applied before births;
% this is necessary to handle certain circumstances where a
% variable can occur in both the post-death and post-birth sets,
% or in both the pre-death and pre-birth sets.

    % see also goal_info_get_code_model in code_model.m
:- pred goal_info_get_determinism(hlds_goal_info::in, determinism::out) is det.
:- pred goal_info_get_instmap_delta(hlds_goal_info::in, instmap_delta::out)
    is det.
:- pred goal_info_get_context(hlds_goal_info::in, prog_context::out) is det.
:- pred goal_info_get_nonlocals(hlds_goal_info::in, set(prog_var)::out) is det.
:- pred goal_info_get_code_gen_nonlocals(hlds_goal_info::in,
    set(prog_var)::out) is det.
:- pred goal_info_get_purity(hlds_goal_info::in, purity::out) is det.
:- pred goal_info_get_features(hlds_goal_info::in, set(goal_feature)::out)
    is det.
:- pred goal_info_get_goal_path(hlds_goal_info::in, goal_path::out) is det.
:- pred goal_info_get_code_gen_info(hlds_goal_info::in,
    hlds_goal_code_gen_info::out) is det.
:- func goal_info_get_extra_info(hlds_goal_info) = hlds_goal_extra_info.

:- pred goal_info_set_determinism(determinism::in,
    hlds_goal_info::in, hlds_goal_info::out) is det.
:- pred goal_info_set_instmap_delta(instmap_delta::in,
    hlds_goal_info::in, hlds_goal_info::out) is det.
:- pred goal_info_set_context(prog_context::in,
    hlds_goal_info::in, hlds_goal_info::out) is det.
:- pred goal_info_set_purity(purity::in,
    hlds_goal_info::in, hlds_goal_info::out) is det.
:- pred goal_info_set_nonlocals(set(prog_var)::in,
    hlds_goal_info::in, hlds_goal_info::out) is det.
:- pred goal_info_set_code_gen_nonlocals(set(prog_var)::in,
    hlds_goal_info::in, hlds_goal_info::out) is det.
:- pred goal_info_set_features(set(goal_feature)::in,
    hlds_goal_info::in, hlds_goal_info::out) is det.
:- pred goal_info_set_goal_path(goal_path::in,
    hlds_goal_info::in, hlds_goal_info::out) is det.
:- pred goal_info_set_code_gen_info(hlds_goal_code_gen_info::in,
    hlds_goal_info::in, hlds_goal_info::out) is det.
:- pred goal_info_set_extra_info(hlds_goal_extra_info::in, hlds_goal_info::in,
    hlds_goal_info::out) is det.

:- pred goal_info_get_occurring_vars(hlds_goal_info::in, set(prog_var)::out)
    is det.
:- pred goal_info_get_producing_vars(hlds_goal_info::in, set(prog_var)::out)
    is det.
:- pred goal_info_get_consuming_vars(hlds_goal_info::in, set(prog_var)::out)
    is det.
:- pred goal_info_get_make_visible_vars(hlds_goal_info::in, set(prog_var)::out)
    is det.
:- pred goal_info_get_need_visible_vars(hlds_goal_info::in, set(prog_var)::out)
    is det.

:- pred goal_info_set_occurring_vars(set(prog_var)::in,
    hlds_goal_info::in, hlds_goal_info::out) is det.
:- pred goal_info_set_producing_vars(set(prog_var)::in,
    hlds_goal_info::in, hlds_goal_info::out) is det.
:- pred goal_info_set_consuming_vars(set(prog_var)::in,
    hlds_goal_info::in, hlds_goal_info::out) is det.
:- pred goal_info_set_make_visible_vars(set(prog_var)::in,
    hlds_goal_info::in, hlds_goal_info::out) is det.
:- pred goal_info_set_need_visible_vars(set(prog_var)::in,
    hlds_goal_info::in, hlds_goal_info::out) is det.

:- func producing_vars(hlds_goal_info) = set(prog_var).
:- func 'producing_vars :='(hlds_goal_info, set(prog_var)) = hlds_goal_info.

:- func consuming_vars(hlds_goal_info) = set(prog_var).
:- func 'consuming_vars :='(hlds_goal_info, set(prog_var)) = hlds_goal_info.

:- func make_visible_vars(hlds_goal_info) = set(prog_var).
:- func 'make_visible_vars :='(hlds_goal_info, set(prog_var)) = hlds_goal_info.

:- func need_visible_vars(hlds_goal_info) = set(prog_var).
:- func 'need_visible_vars :='(hlds_goal_info, set(prog_var)) = hlds_goal_info.

:- pred goal_get_nonlocals(hlds_goal::in, set(prog_var)::out) is det.

:- pred goal_get_purity(hlds_goal::in, purity::out) is det.

:- pred goal_set_purity(purity::in, hlds_goal::in, hlds_goal::out) is det.

:- type contains_trace_goal
    --->    contains_trace_goal
    ;       contains_no_trace_goal.

:- pred goal_get_goal_purity(hlds_goal::in,
    purity::out, contains_trace_goal::out) is det.
:- pred goal_info_get_goal_purity(hlds_goal_info::in,
    purity::out, contains_trace_goal::out) is det.

:- pred goal_info_add_feature(goal_feature::in,
    hlds_goal_info::in, hlds_goal_info::out) is det.
:- pred goal_info_remove_feature(goal_feature::in,
    hlds_goal_info::in, hlds_goal_info::out) is det.
:- pred goal_info_has_feature(hlds_goal_info::in, goal_feature::in) is semidet.

:- pred goal_set_context(term.context::in, hlds_goal::in, hlds_goal::out)
    is det.

:- pred goal_add_feature(goal_feature::in, hlds_goal::in, hlds_goal::out)
    is det.
:- pred goal_remove_feature(goal_feature::in, hlds_goal::in, hlds_goal::out)
    is det.
:- pred goal_has_feature(hlds_goal::in, goal_feature::in) is semidet.

:- type goal_feature
    --->    constraint
            % This is included if the goal is a constraint. See constraint.m
            % for the definition of this.

    ;       from_head
            % This goal was originally in the head of the clause, and was
            % put into the body by the superhomogeneous form transformation.

    ;       not_impure_for_determinism
            % This goal should not be treated as impure for the purpose of
            % computing its determinism. This is intended to be used by program
            % transformations that insert impure code into existing goals,
            % and wish to keep the old determinism of those goals.

    ;       stack_opt
            % This goal was created by stack slot optimization. Other
            % optimizations should assume that it is there for a reason, and
            % therefore should refrain from "optimizing" it away, even though
            % it is a copy of another, previous goal.

    ;       tuple_opt
            % This goal was create by the tupling optimization.
            % The comment for the stack slot optimization above
            % applies here.

    ;       call_table_gen
            % This goal generates the variable that represents the call table
            % tip. If debugging is enabled, the code generator needs to save
            % the value of this variable in its stack slot as soon as it is
            % generated; this marker tells the code generator when this
            % happens.

    ;       preserve_backtrack_into
            % Determinism analysis should preserve backtracking into goals
            % marked with this feature, even if their determinism puts an
            % at_most_zero upper bound on the number of solutions they have.

    ;       save_deep_excp_vars
            % This goal generates the deep profiling variables that the
            % exception handler needs to execute the exception port code.

    ;       hide_debug_event
            % The events associated with this goal should be hidden. This is
            % used e.g. by the tabling transformation to preserve the set
            % of events generated by a tabled procedure.

    ;       tailcall
            % This goal represents a tail call. This marker is used by
            % deep profiling.

    ;       keep_constant_binding
            % This feature should only be attached to unsafe_cast goals
            % that cast a value of an user-defined type to an integer.
            % It tells the mode checker that if the first variable is known
            % to be bound to a given constant, then the second variable
            % should be set to the corresponding local tag value.

    ;       dont_warn_singleton
            % Don't warn about singletons in this goal. Intended to be used
            % by the state variable transformation, for situations such as the
            % following:
            %
            % p(X, !.S, ...) :-
            %   (
            %       X = a,
            %       !:S = f(!.S, ...)
            %   ;
            %       X = b,
            %       <code A>
            %   ),
            %   <code B>.
            %
            % The state variable transformation creates a new variable for
            % the new value of !:S in the disjunction. If code A doesn't define
            % !:S, the state variable transformation inserts an unification
            % after it, unifying the variables representing !.S and !:S.
            % If code B doesn't refer to S, then quantification will restrict
            % the scope of the variable representing !:S to each disjunct,
            % and the unification inserted after code A will refer to a
            % singleton variable.
            %
            % Since it is not reasonable to expect the state variable
            % transformation to do the job of quantification as well,
            % we simply make it mark the unifications it creates, and get
            % the singleton warning code to respect it.

    ;       duplicated_for_switch
            % This goal was created by switch detection by duplicating
            % the source code written by the user.

    ;       mode_check_clauses_goal
            % This goal is the main disjunction of a predicate with the
            % mode_check_clauses pragma. No compiler pass should try to invoke
            % quadratic or worse algorithms on the arms of this goal, since it
            % probably has many arms (possibly several thousand). This feature
            % may be attached to switches as well as disjunctions.

    ;       will_not_modify_trail
            % This goal will not modify the trail, so it is safe for the
            % compiler to omit trailing primitives when generating code
            % for this goal.

    ;       will_not_call_mm_tabled
            % This goal will never call a procedure that is evaluted using
            % minimal model tabling. It is safe for the code generator to omit
            % the pneg context wrappers when generating code for this goal.

    ;       contains_trace.
            % This goal contains a scope goal whose scope_reason is
            % trace_goal(...).

    % We can think of the goal that defines a procedure to be a tree,
    % whose leaves are primitive goals and whose interior nodes are
    % compound goals. These two types describe the position of a goal
    % in this tree. A goal_path_step type says which branch to take at an
    % interior node; the integer counts start at one. (For switches,
    % the second int gives the total number of function symbols in the type
    % of the switched-on var; for builtin types such as integer and string,
    % for which this number is effectively infinite, we store a negative
    % number.) The goal_path type gives the sequence of steps from the root
    % to the given goal *in reverse order*, so that the step closest to
    % the root is last. (Keeping the list in reverse order makes the
    % common operations constant-time instead of linear in the length
    % of the list.)
    %
    % If any of the following three types is changed, then the
    % corresponding types in mdbcomp/program_representation.m must be
    % updated.
    %
:- type goal_path == list(goal_path_step).

:- type goal_path_step
    --->    conj(int)
    ;       disj(int)
    ;       switch(int, int)
    ;       ite_cond
    ;       ite_then
    ;       ite_else
    ;       neg
    ;       scope(maybe_cut)
    ;       first
    ;       later.

:- type maybe_cut
    --->    cut
    ;       no_cut.

    % Convert a goal path to a string, using the format documented
    % in the Mercury user's guide.
    %
:- pred goal_path_to_string(goal_path::in, string::out) is det.

%-----------------------------------------------------------------------------%
%
% Get/set predicates for the extra_goal_info structure
%

:- func goal_info_get_ho_values(hlds_goal_info) = ho_values.

:- pred goal_info_set_ho_values(ho_values::in,
    hlds_goal_info::in, hlds_goal_info::out) is det.

%-----------------------------------------------------------------------------%
%
% Types and get/set predicates for the CTGC related information stored for each
% goal.
%

    % Information describing possible kinds of reuse on a per goal basis.
    % - 'empty': before CTGC analysis, every goal is annotated with the reuse
    % description 'empty', i.e. no information about any reuse.
    % - 'potential_reuse': the value 'potential_reuse' states that in a reuse
    % version of the procedure to which the goal belongs, this goal may safely
    % be replaced by a goal implementing structure reuse.
    % - 'reuse': the value 'reuse' states that in the current procedure (either
    % the specialised reuse version of a procedure, or the original procedure
    % itself) the current goal can safely be replaced by a goal performing
    % structure reuse.
    % - 'missed_reuse': the value 'missed_reuse' gives some feedback when an
    % opportunity for reuse was missed for some reason (only used for calls).
    %
:- type reuse_description
    --->    empty
    ;       missed_reuse(list(missed_message))
    ;       potential_reuse(short_reuse_description)
    ;       reuse(short_reuse_description).

    % A short description of the kind of reuse allowed in the associated
    % goal:
    % - 'cell_died' (only relevant for deconstructions): states that the cell
    % of the deconstruction becomes dead after that deconstruction.
    % - 'cell_reused' (only relevant for constructions): states that it is
    % allowed to reuse a previously discovered dead term for constructing a
    % new term in the given construction. Details of which term is reused are
    % recorded.
    % - 'reuse_call' (only applicable to procedure calls): the called
    % procedure is an optimised procedure w.r.t. CTGC. Records whether the
    % call is conditional or not.
    %
:- type short_reuse_description
    --->    cell_died
    ;       cell_reused(
                dead_var,       % The dead variable selected
                                % for reusing.
                is_conditional, % states if the reuse is conditional.
                list(cons_id),  % What are the possible cons_ids that the
                                % variable to be reused can have.
                list(needs_update)
                                % Which of the fields of the cell to be
                                % reused already contain the correct value.
            )
    ;       reuse_call(is_conditional).

    % Used to represent the fact whether a reuse opportunity is either
    % always safe (unconditional_reuse) or involves a reuse condition to
    % be satisfied (conditional_reuse).
    %
:- type is_conditional
    --->    conditional_reuse
    ;       unconditional_reuse.

:- type needs_update
    --->    needs_update
    ;       does_not_need_update.

:- type missed_message == string.

    % The following functions produce an 'unexpected' error when the
    % requested values have not been set.
    %
:- func goal_info_get_lfu(hlds_goal_info) = set(prog_var).
:- func goal_info_get_lbu(hlds_goal_info) = set(prog_var).
:- func goal_info_get_reuse(hlds_goal_info) = reuse_description.

    % Same as above, but instead of producing an error, the predicate
    % fails.
:- pred goal_info_maybe_get_lfu(hlds_goal_info::in, set(prog_var)::out) is
    semidet.
:- pred goal_info_maybe_get_lbu(hlds_goal_info::in, set(prog_var)::out) is
    semidet.
:- pred goal_info_maybe_get_reuse(hlds_goal_info::in, reuse_description::out)
    is semidet.

:- pred goal_info_set_lfu(set(prog_var)::in, hlds_goal_info::in,
    hlds_goal_info::out) is det.
:- pred goal_info_set_lbu(set(prog_var)::in, hlds_goal_info::in,
    hlds_goal_info::out) is det.
:- pred goal_info_set_reuse(reuse_description::in, hlds_goal_info::in,
    hlds_goal_info::out) is det.

%-----------------------------------------------------------------------------%
%
% Miscellaneous utility procedures for dealing with HLDS goals.
%

    % Convert a goal to a list of conjuncts.
    % If the goal is a conjunction, then return its conjuncts,
    % otherwise return the goal as a singleton list.
    %
:- pred goal_to_conj_list(hlds_goal::in, list(hlds_goal)::out) is det.

    % Convert a goal to a list of parallel conjuncts.
    % If the goal is a parallel conjunction, then return its conjuncts,
    % otherwise return the goal as a singleton list.
    %
:- pred goal_to_par_conj_list(hlds_goal::in, list(hlds_goal)::out) is det.

    % Convert a goal to a list of disjuncts.
    % If the goal is a disjunction, then return its disjuncts,
    % otherwise return the goal as a singleton list.
    %
:- pred goal_to_disj_list(hlds_goal::in, list(hlds_goal)::out) is det.

    % Convert a list of conjuncts to a goal.
    % If the list contains only one goal, then return that goal,
    % otherwise return the conjunction of the conjuncts,
    % with the specified goal_info.
    %
:- pred conj_list_to_goal(list(hlds_goal)::in, hlds_goal_info::in,
    hlds_goal::out) is det.

    % Convert a list of parallel conjuncts to a goal.
    % If the list contains only one goal, then return that goal,
    % otherwise return the parallel conjunction of the conjuncts,
    % with the specified goal_info.
    %
:- pred par_conj_list_to_goal(list(hlds_goal)::in, hlds_goal_info::in,
    hlds_goal::out) is det.

    % Convert a list of disjuncts to a goal.
    % If the list contains only one goal, then return that goal,
    % otherwise return the disjunction of the disjuncts,
    % with the specified goal_info.
    %
:- pred disj_list_to_goal(list(hlds_goal)::in, hlds_goal_info::in,
    hlds_goal::out) is det.

    % Takes a goal and a list of goals, and conjoins them
    % (with a potentially blank goal_info).
    %
:- pred conjoin_goal_and_goal_list(hlds_goal::in, list(hlds_goal)::in,
    hlds_goal::out) is det.

    % Conjoin two goals (with a potentially blank goal_info).
    %
:- pred conjoin_goals(hlds_goal::in, hlds_goal::in, hlds_goal::out) is det.

    % Negate a goal, eliminating double negations as we go.
    %
:- pred negate_goal(hlds_goal::in, hlds_goal_info::in, hlds_goal::out) is det.

    % Return yes if goal(s) contain any foreign code
    %
:- func goal_has_foreign(hlds_goal) = bool.
:- func goal_list_has_foreign(list(hlds_goal)) = bool.

    % A goal is atomic iff it doesn't contain any sub-goals
    % (except possibly goals inside lambda expressions --
    % but lambda expressions will get transformed into separate
    % predicates by the polymorphism.m pass).
    %
:- pred goal_is_atomic(hlds_goal_expr::in) is semidet.

    % Return the HLDS equivalent of `true'.
    %
:- func true_goal = hlds_goal.
:- func true_goal_expr = hlds_goal_expr.

:- func true_goal_with_context(prog_context) = hlds_goal.

    % Return the HLDS equivalent of `fail'.
    %
:- func fail_goal = hlds_goal.
:- func fail_goal_expr = hlds_goal_expr.

:- func fail_goal_with_context(prog_context) = hlds_goal.

    % Return the union of all the nonlocals of a list of goals.
    %
:- pred goal_list_nonlocals(list(hlds_goal)::in, set(prog_var)::out) is det.

    % Compute the instmap_delta resulting from applying
    % all the instmap_deltas of the given goals.
    %
:- pred goal_list_instmap_delta(list(hlds_goal)::in, instmap_delta::out)
    is det.

    % Compute the determinism of a list of goals.
    %
:- pred goal_list_determinism(list(hlds_goal)::in, determinism::out) is det.

    % Compute the purity of a list of goals.
:- pred goal_list_purity(list(hlds_goal)::in, purity::out) is det.

    % Change the contexts of the goal_infos of all the sub-goals
    % of the given goal. This is used to ensure that error messages
    % for automatically generated unification procedures have a useful
    % context.
    %
:- pred set_goal_contexts(prog_context::in, hlds_goal::in, hlds_goal::out)
    is det.

    % Create the hlds_goal for a unification, filling in all the as yet
    % unknown slots with dummy values. The unification is constructed as a
    % complicated unification; turning it into some other kind of unification,
    % if appropriate is left to mode analysis. Therefore this predicate
    % shouldn't be used unless you know mode analysis will be run on its
    % output.
    %
:- pred create_atomic_complicated_unification(prog_var::in, unify_rhs::in,
    prog_context::in, unify_main_context::in, unify_sub_contexts::in,
    purity::in, hlds_goal::out) is det.

    % As above, but with default purity pure.
    %
:- pred create_atomic_complicated_unification(prog_var::in, unify_rhs::in,
    prog_context::in, unify_main_context::in, unify_sub_contexts::in,
    hlds_goal::out) is det.

    % Create the hlds_goal for a unification that tests the equality of two
    % values of atomic types. The resulting goal has all its fields filled in.
    %
:- pred make_simple_test(prog_var::in, prog_var::in,
    unify_main_context::in, unify_sub_contexts::in, hlds_goal::out) is det.

    % Produce a goal to construct a given constant. These predicates all
    % fill in the non-locals, instmap_delta and determinism fields of the
    % goal_info of the returned goal. With alias tracking, the instmap_delta
    % will be correct only if the variable being assigned to has no aliases.
    %
    % Ths cons_id passed to make_const_construction must be fully module
    % qualified.
    %
:- pred make_int_const_construction(prog_var::in, int::in,
    hlds_goal::out) is det.
:- pred make_string_const_construction(prog_var::in, string::in,
    hlds_goal::out) is det.
:- pred make_float_const_construction(prog_var::in, float::in,
    hlds_goal::out) is det.
:- pred make_char_const_construction(prog_var::in, char::in,
    hlds_goal::out) is det.
:- pred make_const_construction(prog_var::in, cons_id::in,
    hlds_goal::out) is det.

:- pred make_int_const_construction_alloc(int::in, maybe(string)::in,
    hlds_goal::out, prog_var::out,
    prog_varset::in, prog_varset::out, vartypes::in, vartypes::out) is det.
:- pred make_string_const_construction_alloc(string::in, maybe(string)::in,
    hlds_goal::out, prog_var::out,
    prog_varset::in, prog_varset::out, vartypes::in, vartypes::out) is det.
:- pred make_float_const_construction_alloc(float::in, maybe(string)::in,
    hlds_goal::out, prog_var::out,
    prog_varset::in, prog_varset::out, vartypes::in, vartypes::out) is det.
:- pred make_char_const_construction_alloc(char::in, maybe(string)::in,
    hlds_goal::out, prog_var::out,
    prog_varset::in, prog_varset::out, vartypes::in, vartypes::out) is det.
:- pred make_const_construction_alloc(cons_id::in, mer_type::in,
    maybe(string)::in, hlds_goal::out, prog_var::out,
    prog_varset::in, prog_varset::out, vartypes::in, vartypes::out) is det.

:- pred make_int_const_construction_alloc_in_proc(int::in,
    maybe(string)::in, hlds_goal::out, prog_var::out,
    proc_info::in, proc_info::out) is det.
:- pred make_string_const_construction_alloc_in_proc(string::in,
    maybe(string)::in, hlds_goal::out, prog_var::out,
    proc_info::in, proc_info::out) is det.
:- pred make_float_const_construction_alloc_in_proc(float::in,
    maybe(string)::in, hlds_goal::out, prog_var::out,
    proc_info::in, proc_info::out) is det.
:- pred make_char_const_construction_alloc_in_proc(char::in,
    maybe(string)::in, hlds_goal::out, prog_var::out,
    proc_info::in, proc_info::out) is det.
:- pred make_const_construction_alloc_in_proc(cons_id::in, mer_type::in,
    maybe(string)::in, hlds_goal::out, prog_var::out,
    proc_info::in, proc_info::out) is det.

    % Given the variable info field from a pragma foreign_code, get
    % all the variable names.
    %
:- pred get_pragma_foreign_var_names(list(maybe(pair(string, mer_mode)))::in,
    list(string)::out) is det.

    % Produce a goal to construct or deconstruct a unification with
    % a functor.  It fills in the non-locals, instmap_delta and
    % determinism fields of the goal_info.
    %
:- pred construct_functor(prog_var::in, cons_id::in, list(prog_var)::in,
    hlds_goal::out) is det.
:- pred deconstruct_functor(prog_var::in, cons_id::in, list(prog_var)::in,
    hlds_goal::out) is det.

    % Produce a goal to construct or deconstruct a tuple containing
    % the given list of arguments, filling in the non-locals,
    % instmap_delta and determinism fields of the goal_info.
    %
:- pred construct_tuple(prog_var::in, list(prog_var)::in, hlds_goal::out)
    is det.
:- pred deconstruct_tuple(prog_var::in, list(prog_var)::in, hlds_goal::out)
    is det.

%-----------------------------------------------------------------------------%
%
% Stuff specific to a back-end. At the moment, only the LLDS back-end
% annotates the HLDS.
%

:- type hlds_goal_code_gen_info
    --->    no_code_gen_info
    ;       llds_code_gen_info(llds_code_gen :: llds_code_gen_details).

%-----------------------------------------------------------------------------%
%
% Stuff specific to the auxiliary analysis passes of the compiler.
%
% At the moment only closure analysis annotates the HLDS at a per-goal level.

    % This type stores the possible values of a higher order variable
    % (at a particular point) as determined by the closure analysis
    % (see closure_analysis.m.)  If a variable does not have an entry
    % in the map then it may take any (valid) value.
    %
:- type ho_values == map(prog_var, set(pred_proc_id)).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module check_hlds.mode_util.
:- import_module check_hlds.type_util.
:- import_module libs.compiler_util.
:- import_module parse_tree.prog_mode.
:- import_module parse_tree.prog_type.
:- import_module parse_tree.prog_util.

:- import_module assoc_list.
:- import_module map.
:- import_module string.
:- import_module svmap.
:- import_module svvarset.
:- import_module varset.

%-----------------------------------------------------------------------------%

foreign_arg_var(Arg) = Arg ^ arg_var.
foreign_arg_maybe_name_mode(Arg) = Arg ^ arg_name_mode.
foreign_arg_type(Arg) = Arg ^ arg_type.
foreign_arg_box(Arg) = Arg ^ arg_box_policy.

make_foreign_args(Vars, NamesModesBoxes, Types, Args) :-
    (
        Vars = [Var | VarsTail],
        NamesModesBoxes = [NameModeBox | NamesModesBoxesTail],
        Types = [Type | TypesTail]
    ->
        make_foreign_args(VarsTail, NamesModesBoxesTail, TypesTail, ArgsTail),
        NameModeBox = NameMode - Box,
        Arg = foreign_arg(Var, NameMode, Type, Box),
        Args = [Arg | ArgsTail]
    ;
        Vars = [],
        NamesModesBoxes = [],
        Types = []
    ->
        Args = []
    ;
        unexpected(this_file, "make_foreign_args: unmatched lists")
    ).

%-----------------------------------------------------------------------------%
%
% Predicates dealing with generic_calls
%

generic_call_id(higher_order(_, Purity, PorF, Arity),
        generic_call_id(gcid_higher_order(Purity, PorF, Arity))).
generic_call_id(class_method(_, _, ClassId, MethodId),
        generic_call_id(gcid_class_method(ClassId, MethodId))).
generic_call_id(cast(CastType), generic_call_id(gcid_cast(CastType))).

generic_call_pred_or_func(higher_order(_, _, PredOrFunc, _)) = PredOrFunc.
generic_call_pred_or_func(class_method(_, _, _, CallId)) =
    simple_call_id_pred_or_func(CallId).
generic_call_pred_or_func(cast(_)) = predicate.

:- func simple_call_id_pred_or_func(simple_call_id) = pred_or_func.

simple_call_id_pred_or_func(simple_call_id(PredOrFunc, _, _)) = PredOrFunc.

%-----------------------------------------------------------------------------%
%
% Information stored with all kinds of goals
%

    % NB. Don't forget to check goal_util.name_apart_goalinfo
    % if this structure is modified.
:- type hlds_goal_info
    --->    goal_info(
                determinism     :: determinism,
                                % The overall determinism of the goal
                                % (computed during determinism analysis)
                                % [because true determinism is undecidable,
                                % this may be a conservative approximation].

                instmap_delta   :: instmap_delta,
                                % The change in insts over this goal
                                % (computed during mode analysis)
                                % [because true unreachability is undecidable,
                                % the instmap_delta may be reachable even
                                % when the goal really never succeeds]
                                %
                                % The following invariant is required
                                % by the code generator and is enforced
                                % by the final simplification pass:
                                % the determinism specifies at_most_zero solns
                                % iff the instmap_delta is unreachable.
                                %
                                % Before the final simplification pass,
                                % the determinism and instmap_delta
                                % might not be consistent with regard to
                                % unreachability, but both will be
                                % conservative approximations, so if either
                                % says a goal is unreachable then it is.
                                %
                                % Normally the instmap_delta will list only
                                % the nonlocal variables of the goal.

                context         :: prog_context,

                nonlocals       :: set(prog_var),
                                % The non-local vars in the goal, i.e. the
                                % variables that occur both inside and outside
                                % of the goal. (computed by quantification.m)
                                % [in some circumstances, this may be a
                                % conservative approximation: it may be
                                % a superset of the real non-locals].

                purity          :: purity,

                features        :: set(goal_feature),
                                % The set of compiler-defined "features" of
                                % this goal, which optimisers may wish
                                % to know about.

                goal_path       :: goal_path,
                                % The path to this goal from the root in
                                % reverse order.

                maybe_mode_constraint_info ::
                                maybe(mode_constraint_goal_info),

                code_gen_info   :: hlds_goal_code_gen_info,

                extra_goal_info :: hlds_goal_extra_info
                                % Extra information about that goal that may
                                % be attached by various optional analysis
                                % passes, e.g closure analysis.
            ).

:- type mode_constraint_goal_info
    --->    mode_constraint_goal_info(
                mci_occurring_vars :: set(prog_var),
                                % Inst_graph nodes that are reachable from
                                % variables that occur in the goal.

                mci_producing_vars :: set(prog_var),
                                % Inst_graph nodes produced by this goal.

                mci_consuming_vars :: set(prog_var),
                                % Inst_graph nodes consumed by this goal.

                mci_make_visible_vars :: set(prog_var),
                                % Variables that this goal makes visible.

                mci_need_visible_vars :: set(prog_var)
                                % Variables that this goal need to be visible
                                % before it is executed.
            ).

:- pragma inline(goal_info_init/1).

goal_info_init(GoalInfo) :-
    Detism = detism_erroneous,
    instmap_delta_init_unreachable(InstMapDelta),
    set.init(NonLocals),
    term.context_init(Context),
    set.init(Features),
    GoalInfo = goal_info(Detism, InstMapDelta, Context, NonLocals, purity_pure,
        Features, [], no, no_code_gen_info, hlds_goal_extra_info_init).

:- pragma inline(goal_info_init/2).

goal_info_init(Context, GoalInfo) :-
    Detism = detism_erroneous,
    instmap_delta_init_unreachable(InstMapDelta),
    set.init(NonLocals),
    set.init(Features),
    GoalInfo = goal_info(Detism, InstMapDelta, Context, NonLocals, purity_pure,
        Features, [], no, no_code_gen_info, hlds_goal_extra_info_init).

goal_info_init(NonLocals, InstMapDelta, Detism, Purity, GoalInfo) :-
    term.context_init(Context),
    set.init(Features),
    GoalInfo = goal_info(Detism, InstMapDelta, Context, NonLocals, Purity,
        Features, [], no, no_code_gen_info, hlds_goal_extra_info_init).

goal_info_init(NonLocals, InstMapDelta, Detism, Purity, Context, GoalInfo) :-
    set.init(Features),
    GoalInfo = goal_info(Detism, InstMapDelta, Context, NonLocals, Purity,
        Features, [], no, no_code_gen_info, hlds_goal_extra_info_init).

goal_info_get_determinism(GoalInfo, GoalInfo ^ determinism).
goal_info_get_instmap_delta(GoalInfo, GoalInfo ^ instmap_delta).
goal_info_get_context(GoalInfo, GoalInfo ^ context).
goal_info_get_nonlocals(GoalInfo, GoalInfo ^ nonlocals).
goal_info_get_purity(GoalInfo, GoalInfo ^ purity).
goal_info_get_features(GoalInfo, GoalInfo ^ features).
goal_info_get_goal_path(GoalInfo, GoalInfo ^ goal_path).
goal_info_get_code_gen_info(GoalInfo, GoalInfo ^ code_gen_info).
goal_info_get_extra_info(GoalInfo) = GoalInfo ^ extra_goal_info.

goal_info_get_occurring_vars(GoalInfo, OccurringVars) :-
    ( GoalInfo ^ maybe_mode_constraint_info = yes(MCI) ->
        OccurringVars = MCI ^ mci_occurring_vars
    ;
        OccurringVars = set.init
    ).

goal_info_get_producing_vars(GoalInfo, ProducingVars) :-
    ( GoalInfo ^ maybe_mode_constraint_info = yes(MCI) ->
        ProducingVars = MCI ^ mci_producing_vars
    ;
        ProducingVars = set.init
    ).

goal_info_get_consuming_vars(GoalInfo, ConsumingVars) :-
    ( GoalInfo ^ maybe_mode_constraint_info = yes(MCI) ->
        ConsumingVars = MCI ^ mci_consuming_vars
    ;
        ConsumingVars = set.init
    ).

goal_info_get_make_visible_vars(GoalInfo, MakeVisibleVars) :-
    ( GoalInfo ^ maybe_mode_constraint_info = yes(MCI) ->
        MakeVisibleVars = MCI ^ mci_make_visible_vars
    ;
        MakeVisibleVars = set.init
    ).

goal_info_get_need_visible_vars(GoalInfo, NeedVisibleVars) :-
    ( GoalInfo ^ maybe_mode_constraint_info = yes(MCI) ->
        NeedVisibleVars = MCI ^ mci_need_visible_vars
    ;
        NeedVisibleVars = set.init
    ).

goal_info_set_determinism(Determinism, GoalInfo,
        GoalInfo ^ determinism := Determinism).
goal_info_set_instmap_delta(InstMapDelta, GoalInfo,
        GoalInfo ^ instmap_delta := InstMapDelta).
goal_info_set_context(Context, GoalInfo, GoalInfo ^ context := Context).
goal_info_set_nonlocals(NonLocals, GoalInfo,
        GoalInfo ^ nonlocals := NonLocals).
goal_info_set_purity(Purity, GoalInfo,
        GoalInfo ^ purity := Purity).
goal_info_set_features(Features, GoalInfo, GoalInfo ^ features := Features).
goal_info_set_goal_path(GoalPath, GoalInfo,
        GoalInfo ^ goal_path := GoalPath).
goal_info_set_code_gen_info(CodeGenInfo, GoalInfo,
        GoalInfo ^ code_gen_info := CodeGenInfo).
goal_info_set_extra_info(ExtraInfo, GoalInfo,
    GoalInfo ^ extra_goal_info := ExtraInfo).

    % The code-gen non-locals are always the same as the
    % non-locals when structure reuse is not being performed.
goal_info_get_code_gen_nonlocals(GoalInfo, NonLocals) :-
    goal_info_get_nonlocals(GoalInfo, NonLocals).
    % The code-gen non-locals are always the same as the
    % non-locals when structure reuse is not being performed.
goal_info_set_code_gen_nonlocals(NonLocals, !GoalInfo) :-
    goal_info_set_nonlocals(NonLocals, !GoalInfo).

goal_info_set_occurring_vars(OccurringVars, !GoalInfo) :-
    MMCI0 = !.GoalInfo ^ maybe_mode_constraint_info,
    (
        MMCI0 = yes(MCI0),
        MCI = MCI0 ^ mci_occurring_vars := OccurringVars
    ;
        MMCI0 = no,
        set.init(ProducingVars),
        set.init(ConsumingVars),
        set.init(MakeVisibleVars),
        set.init(NeedVisibleVars),
        MCI = mode_constraint_goal_info(OccurringVars, ProducingVars,
            ConsumingVars, MakeVisibleVars, NeedVisibleVars)
    ),
    !:GoalInfo = !.GoalInfo ^ maybe_mode_constraint_info := yes(MCI).

goal_info_set_producing_vars(ProducingVars, !GoalInfo) :-
    MMCI0 = !.GoalInfo ^ maybe_mode_constraint_info,
    (
        MMCI0 = yes(MCI0),
        MCI = MCI0 ^ mci_producing_vars := ProducingVars
    ;
        MMCI0 = no,
        set.init(OccurringVars),
        set.init(ConsumingVars),
        set.init(MakeVisibleVars),
        set.init(NeedVisibleVars),
        MCI = mode_constraint_goal_info(OccurringVars, ProducingVars,
            ConsumingVars, MakeVisibleVars, NeedVisibleVars)
    ),
    !:GoalInfo = !.GoalInfo ^ maybe_mode_constraint_info := yes(MCI).

goal_info_set_consuming_vars(ConsumingVars, !GoalInfo) :-
    MMCI0 = !.GoalInfo ^ maybe_mode_constraint_info,
    (
        MMCI0 = yes(MCI0),
        MCI = MCI0 ^ mci_consuming_vars := ConsumingVars
    ;
        MMCI0 = no,
        set.init(OccurringVars),
        set.init(ProducingVars),
        set.init(MakeVisibleVars),
        set.init(NeedVisibleVars),
        MCI = mode_constraint_goal_info(OccurringVars, ProducingVars,
            ConsumingVars, MakeVisibleVars, NeedVisibleVars)
    ),
    !:GoalInfo = !.GoalInfo ^ maybe_mode_constraint_info := yes(MCI).

goal_info_set_make_visible_vars(MakeVisibleVars, !GoalInfo) :-
    MMCI0 = !.GoalInfo ^ maybe_mode_constraint_info,
    (
        MMCI0 = yes(MCI0),
        MCI = MCI0 ^ mci_make_visible_vars := MakeVisibleVars
    ;
        MMCI0 = no,
        set.init(OccurringVars),
        set.init(ProducingVars),
        set.init(ConsumingVars),
        set.init(NeedVisibleVars),
        MCI = mode_constraint_goal_info(OccurringVars, ProducingVars,
            ConsumingVars, MakeVisibleVars, NeedVisibleVars)
    ),
    !:GoalInfo = !.GoalInfo ^ maybe_mode_constraint_info := yes(MCI).

goal_info_set_need_visible_vars(NeedVisibleVars, !GoalInfo) :-
    MMCI0 = !.GoalInfo ^ maybe_mode_constraint_info,
    (
        MMCI0 = yes(MCI0),
        MCI = MCI0 ^ mci_need_visible_vars := NeedVisibleVars
    ;
        MMCI0 = no,
        set.init(OccurringVars),
        set.init(ProducingVars),
        set.init(ConsumingVars),
        set.init(MakeVisibleVars),
        MCI = mode_constraint_goal_info(OccurringVars, ProducingVars,
            ConsumingVars, MakeVisibleVars, NeedVisibleVars)
    ),
    !:GoalInfo = !.GoalInfo ^ maybe_mode_constraint_info := yes(MCI).

producing_vars(GoalInfo) = ProducingVars :-
    goal_info_get_producing_vars(GoalInfo, ProducingVars).

'producing_vars :='(GoalInfo0, ProducingVars) = GoalInfo :-
    goal_info_set_producing_vars(ProducingVars, GoalInfo0, GoalInfo).

consuming_vars(GoalInfo) = ConsumingVars :-
    goal_info_get_consuming_vars(GoalInfo, ConsumingVars).

'consuming_vars :='(GoalInfo0, ConsumingVars) = GoalInfo :-
    goal_info_set_consuming_vars(ConsumingVars, GoalInfo0, GoalInfo).

make_visible_vars(GoalInfo) = MakeVisibleVars :-
    goal_info_get_make_visible_vars(GoalInfo, MakeVisibleVars).

'make_visible_vars :='(GoalInfo0, MakeVisibleVars) = GoalInfo :-
    goal_info_set_make_visible_vars(MakeVisibleVars, GoalInfo0, GoalInfo).

need_visible_vars(GoalInfo) = NeedVisibleVars :-
    goal_info_get_need_visible_vars(GoalInfo, NeedVisibleVars).

'need_visible_vars :='(GoalInfo0, NeedVisibleVars) = GoalInfo :-
    goal_info_set_need_visible_vars(NeedVisibleVars, GoalInfo0, GoalInfo).

%-----------------------------------------------------------------------------%

goal_get_purity(_GoalExpr - GoalInfo, Purity) :-
    goal_info_get_purity(GoalInfo, Purity).

goal_set_purity(Purity, GoalExpr - GoalInfo0, GoalExpr - GoalInfo) :-
    goal_info_set_purity(Purity, GoalInfo0, GoalInfo).

goal_get_goal_purity(_GoalExpr - GoalInfo, Purity, ContainsTraceGoal) :-
    goal_info_get_goal_purity(GoalInfo, Purity, ContainsTraceGoal).

goal_info_get_goal_purity(GoalInfo, Purity, ContainsTraceGoal) :-
    goal_info_get_purity(GoalInfo, Purity),
    ( goal_info_has_feature(GoalInfo, contains_trace) ->
        ContainsTraceGoal = contains_trace_goal
    ;
        ContainsTraceGoal = contains_no_trace_goal
    ).

goal_info_add_feature(Feature, !GoalInfo) :-
    goal_info_get_features(!.GoalInfo, Features0),
    set.insert(Features0, Feature, Features),
    goal_info_set_features(Features, !GoalInfo).

goal_info_remove_feature(Feature, !GoalInfo) :-
    goal_info_get_features(!.GoalInfo, Features0),
    set.delete(Features0, Feature, Features),
    goal_info_set_features(Features, !GoalInfo).

goal_info_has_feature(GoalInfo, Feature) :-
    goal_info_get_features(GoalInfo, Features),
    set.member(Feature, Features).

%-----------------------------------------------------------------------------%

goal_get_nonlocals(_Goal - GoalInfo, NonLocals) :-
    goal_info_get_nonlocals(GoalInfo, NonLocals).

goal_set_context(Context, Goal - GoalInfo0, Goal - GoalInfo) :-
    goal_info_set_context(Context, GoalInfo0, GoalInfo).

goal_add_feature(Feature, Goal - GoalInfo0, Goal - GoalInfo) :-
    goal_info_add_feature(Feature, GoalInfo0, GoalInfo).

goal_remove_feature(Feature, Goal - GoalInfo0, Goal - GoalInfo) :-
    goal_info_remove_feature(Feature, GoalInfo0, GoalInfo).

goal_has_feature(_Goal - GoalInfo, Feature) :-
    goal_info_has_feature(GoalInfo, Feature).

%-----------------------------------------------------------------------------%

goal_path_to_string(Path, PathStr) :-
    goal_path_steps_to_strings(Path, StepStrs),
    list.reverse(StepStrs, RevStepStrs),
    string.append_list(RevStepStrs, PathStr).

:- pred goal_path_steps_to_strings(goal_path::in, list(string)::out) is det.

goal_path_steps_to_strings([], []).
goal_path_steps_to_strings([Step | Steps], [StepStr | StepStrs]) :-
    goal_path_step_to_string(Step, StepStr),
    goal_path_steps_to_strings(Steps, StepStrs).

    % The inverse of this procedure is implemented in
    % mdbcomp/program_representation.m, and must be updated if this
    % is changed.
    %
:- pred goal_path_step_to_string(goal_path_step::in, string::out) is det.

goal_path_step_to_string(conj(N), Str) :-
    string.int_to_string(N, NStr),
    string.append_list(["c", NStr, ";"], Str).
goal_path_step_to_string(disj(N), Str) :-
    string.int_to_string(N, NStr),
    string.append_list(["d", NStr, ";"], Str).
goal_path_step_to_string(switch(N, _), Str) :-
    string.int_to_string(N, NStr),
    string.append_list(["s", NStr, ";"], Str).
goal_path_step_to_string(ite_cond, "?;").
goal_path_step_to_string(ite_then, "t;").
goal_path_step_to_string(ite_else, "e;").
goal_path_step_to_string(neg, "~;").
goal_path_step_to_string(scope(cut), "q!;").
goal_path_step_to_string(scope(no_cut), "q;").
goal_path_step_to_string(first, "f;").
goal_path_step_to_string(later, "l;").

%-----------------------------------------------------------------------------%
%
% Miscellaneous utility procedures for dealing with HLDS goals
%

goal_to_conj_list(Goal, ConjList) :-
    ( Goal = (conj(plain_conj, List) - _) ->
        ConjList = List
    ;
        ConjList = [Goal]
    ).

goal_to_par_conj_list(Goal, ConjList) :-
    ( Goal = conj(parallel_conj, List) - _ ->
        ConjList = List
    ;
        ConjList = [Goal]
    ).

goal_to_disj_list(Goal, DisjList) :-
    ( Goal = disj(List) - _ ->
        DisjList = List
    ;
        DisjList = [Goal]
    ).

conj_list_to_goal(ConjList, GoalInfo, Goal) :-
    ( ConjList = [Goal0] ->
        Goal = Goal0
    ;
        Goal = conj(plain_conj, ConjList) - GoalInfo
    ).

par_conj_list_to_goal(ConjList, GoalInfo, Goal) :-
    ( ConjList = [Goal0] ->
        Goal = Goal0
    ;
        Goal = conj(parallel_conj, ConjList) - GoalInfo
    ).

disj_list_to_goal(DisjList, GoalInfo, Goal) :-
    ( DisjList = [Goal0] ->
        Goal = Goal0
    ;
        Goal = disj(DisjList) - GoalInfo
    ).

conjoin_goal_and_goal_list(Goal0, Goals, Goal) :-
    Goal0 = GoalExpr0 - GoalInfo0,
    ( GoalExpr0 = conj(plain_conj, GoalList0) ->
        list.append(GoalList0, Goals, GoalList),
        GoalExpr = conj(plain_conj, GoalList)
    ;
        GoalExpr = conj(plain_conj, [Goal0 | Goals])
    ),
    Goal = GoalExpr - GoalInfo0.

conjoin_goals(Goal1, Goal2, Goal) :-
    ( Goal2 = conj(plain_conj, Goals2) - _ ->
        GoalList = Goals2
    ;
        GoalList = [Goal2]
    ),
    conjoin_goal_and_goal_list(Goal1, GoalList, Goal).

negate_goal(Goal, GoalInfo, NegatedGoal) :-
    (
        % Eliminate double negations.
        Goal = negation(Goal1) - _
    ->
        NegatedGoal = Goal1
    ;
        % Convert negated conjunctions of negations into disjunctions.
        Goal = conj(plain_conj, NegatedGoals) - _,
        all_negated(NegatedGoals, UnnegatedGoals)
    ->
        NegatedGoal = disj(UnnegatedGoals) - GoalInfo
    ;
        NegatedGoal = negation(Goal) - GoalInfo
    ).

:- pred all_negated(list(hlds_goal)::in, list(hlds_goal)::out) is semidet.

all_negated([], []).
all_negated([negation(Goal) - _ | NegatedGoals], [Goal | Goals]) :-
    all_negated(NegatedGoals, Goals).
all_negated([conj(plain_conj, NegatedConj) - _GoalInfo | NegatedGoals],
        Goals) :-
    all_negated(NegatedConj, Goals1),
    all_negated(NegatedGoals, Goals2),
    list.append(Goals1, Goals2, Goals).

%-----------------------------------------------------------------------------%

    % Returns yes if a goal (or subgoal contained within) contains
    % any foreign code.
    %
goal_has_foreign(Goal) = HasForeign :-
    Goal = GoalExpr - _,
    (
        GoalExpr = conj(_, Goals),
        HasForeign = goal_list_has_foreign(Goals)
    ;
        GoalExpr = plain_call(_, _, _, _, _, _),
        HasForeign = no
    ;
        GoalExpr = generic_call(_, _, _, _),
        HasForeign = no
    ;
        GoalExpr = switch(_, _, _),
        HasForeign = no
    ;
        GoalExpr = unify(_, _, _, _, _),
        HasForeign = no
    ;
        GoalExpr = disj(Goals),
        HasForeign = goal_list_has_foreign(Goals)
    ;
        GoalExpr = negation(Goal2),
        HasForeign = goal_has_foreign(Goal2)
    ;
        GoalExpr = scope(_, Goal2),
        HasForeign = goal_has_foreign(Goal2)
    ;
        GoalExpr = if_then_else(_, Cond, Then, Else),
        (
            ( goal_has_foreign(Cond) = yes
            ; goal_has_foreign(Then) = yes
            ; goal_has_foreign(Else) = yes
            )
        ->
            HasForeign = yes
        ;
            HasForeign = no
        )
    ;
        GoalExpr = call_foreign_proc(_, _, _, _, _, _, _),
        HasForeign = yes
    ;
        GoalExpr = shorthand(ShorthandGoal),
        HasForeign = goal_has_foreign_shorthand(ShorthandGoal)
    ).

    % Return yes if the shorthand goal contains any foreign code.
    %
:- func goal_has_foreign_shorthand(shorthand_goal_expr) = bool.

goal_has_foreign_shorthand(bi_implication(GoalA, GoalB)) =
    (
        ( goal_has_foreign(GoalA) = yes
        ; goal_has_foreign(GoalB) = yes
        )
    ->
        yes
    ;
        no
    ).

goal_list_has_foreign([]) = no.
goal_list_has_foreign([X | Xs]) =
    ( goal_has_foreign(X) = yes ->
        yes
    ;
        goal_list_has_foreign(Xs)
    ).

%-----------------------------------------------------------------------------%

goal_is_atomic(Goal) :-
    goal_is_atomic(Goal) = yes.

:- func goal_is_atomic(hlds_goal_expr) = bool.

goal_is_atomic(unify(_, _, _, _, _)) = yes.
goal_is_atomic(generic_call(_, _, _, _)) = yes.
goal_is_atomic(plain_call(_, _, _, _, _, _)) = yes.
goal_is_atomic(call_foreign_proc(_, _, _, _, _, _,  _)) = yes.
goal_is_atomic(conj(_, Conj)) = ( Conj = [] -> yes ; no ).
goal_is_atomic(disj(Disj)) = ( Disj = [] -> yes ; no ).
goal_is_atomic(if_then_else(_, _, _, _)) = no.
goal_is_atomic(negation(_)) = no.
goal_is_atomic(switch(_, _, _)) = no.
goal_is_atomic(scope(_, _)) = no.
goal_is_atomic(shorthand(_)) = no.

%-----------------------------------------------------------------------------%

true_goal = true_goal_expr - GoalInfo :-
    instmap_delta_init_reachable(InstMapDelta),
    goal_info_init(set.init, InstMapDelta, detism_det, purity_pure, GoalInfo).

true_goal_expr = conj(plain_conj, []).

true_goal_with_context(Context) = Goal - GoalInfo :-
    Goal - GoalInfo0 = true_goal,
    goal_info_set_context(Context, GoalInfo0, GoalInfo).

fail_goal = fail_goal_expr - GoalInfo :-
    instmap_delta_init_unreachable(InstMapDelta),
    goal_info_init(set.init, InstMapDelta, detism_failure, purity_pure,
        GoalInfo).

fail_goal_expr = disj([]).

fail_goal_with_context(Context) = Goal - GoalInfo :-
    Goal - GoalInfo0 = fail_goal,
    goal_info_set_context(Context, GoalInfo0, GoalInfo).

%-----------------------------------------------------------------------------%

goal_list_nonlocals(Goals, NonLocals) :-
    UnionNonLocals = (pred(Goal::in, Vars0::in, Vars::out) is det :-
        Goal = _ - GoalInfo,
        goal_info_get_nonlocals(GoalInfo, Vars1),
        set.union(Vars0, Vars1, Vars)
    ),
    set.init(NonLocals0),
    list.foldl(UnionNonLocals, Goals, NonLocals0, NonLocals).

goal_list_instmap_delta(Goals, InstMapDelta) :-
    ApplyDelta = (pred(Goal::in, Delta0::in, Delta::out) is det :-
        Goal = _ - GoalInfo,
        goal_info_get_instmap_delta(GoalInfo, Delta1),
        instmap_delta_apply_instmap_delta(Delta0, Delta1, test_size, Delta)
    ),
    instmap_delta_init_reachable(InstMapDelta0),
    list.foldl(ApplyDelta, Goals, InstMapDelta0, InstMapDelta).

goal_list_determinism(Goals, Determinism) :-
    ComputeDeterminism = (pred(Goal::in, Det0::in, Det::out) is det :-
        Goal = _ - GoalInfo,
        goal_info_get_determinism(GoalInfo, Det1),
        det_conjunction_detism(Det0, Det1, Det)
    ),
    list.foldl(ComputeDeterminism, Goals, detism_det, Determinism).

goal_list_purity(Goals, Purity) :-
    ComputePurity = (func(_ - GoalInfo, Purity0) = Purity1 :-
        goal_info_get_purity(GoalInfo, GoalPurity),
        worst_purity(GoalPurity, Purity0) = Purity1
    ),
    Purity = list.foldl(ComputePurity, Goals, purity_pure).

%-----------------------------------------------------------------------------%

set_goal_contexts(Context, Goal0 - GoalInfo0, Goal - GoalInfo) :-
    goal_info_set_context(Context, GoalInfo0, GoalInfo),
    set_goal_contexts_2(Context, Goal0, Goal).

:- pred set_goal_contexts_2(prog_context::in, hlds_goal_expr::in,
    hlds_goal_expr::out) is det.

set_goal_contexts_2(Context, conj(ConjType, Goals0), conj(ConjType, Goals)) :-
    list.map(set_goal_contexts(Context), Goals0, Goals).
set_goal_contexts_2(Context, disj(Goals0), disj(Goals)) :-
    list.map(set_goal_contexts(Context), Goals0, Goals).
set_goal_contexts_2(Context, if_then_else(Vars, Cond0, Then0, Else0),
        if_then_else(Vars, Cond, Then, Else)) :-
    set_goal_contexts(Context, Cond0, Cond),
    set_goal_contexts(Context, Then0, Then),
    set_goal_contexts(Context, Else0, Else).
set_goal_contexts_2(Context, switch(Var, CanFail, Cases0),
        switch(Var, CanFail, Cases)) :-
    list.map(
        (pred(case(ConsId, Goal0)::in, case(ConsId, Goal)::out) is det :-
            set_goal_contexts(Context, Goal0, Goal)
        ), Cases0, Cases).
set_goal_contexts_2(Context, scope(Reason, Goal0), scope(Reason, Goal)) :-
    set_goal_contexts(Context, Goal0, Goal).
set_goal_contexts_2(Context, negation(Goal0), negation(Goal)) :-
    set_goal_contexts(Context, Goal0, Goal).
set_goal_contexts_2(_, Goal, Goal) :-
    Goal = plain_call(_, _, _, _, _, _).
set_goal_contexts_2(_, Goal, Goal) :-
    Goal = generic_call(_, _, _, _).
set_goal_contexts_2(_, Goal, Goal) :-
    Goal = unify(_, _, _, _, _).
set_goal_contexts_2(_, Goal, Goal) :-
    Goal = call_foreign_proc(_, _, _, _, _, _, _).
set_goal_contexts_2(Context, shorthand(ShorthandGoal0),
        shorthand(ShorthandGoal)) :-
    set_goal_contexts_2_shorthand(Context, ShorthandGoal0, ShorthandGoal).

:- pred set_goal_contexts_2_shorthand(prog_context::in,
    shorthand_goal_expr::in, shorthand_goal_expr::out) is det.

set_goal_contexts_2_shorthand(Context, bi_implication(LHS0, RHS0),
        bi_implication(LHS, RHS)) :-
    set_goal_contexts(Context, LHS0, LHS),
    set_goal_contexts(Context, RHS0, RHS).

%-----------------------------------------------------------------------------%

create_atomic_complicated_unification(LHS, RHS, Context,
        UnifyMainContext, UnifySubContext, Goal) :-
    create_atomic_complicated_unification(LHS, RHS, Context,
        UnifyMainContext, UnifySubContext, purity_pure, Goal).

create_atomic_complicated_unification(LHS, RHS, Context,
        UnifyMainContext, UnifySubContext, Purity, Goal) :-
    UMode = ((free - free) -> (free - free)),
    Mode = ((free -> free) - (free -> free)),
    Unification = complicated_unify(UMode, can_fail, []),
    UnifyContext = unify_context(UnifyMainContext, UnifySubContext),
    goal_info_init(Context, GoalInfo0),
    goal_info_set_purity(Purity, GoalInfo0, GoalInfo),
    Goal = unify(LHS, RHS, Mode, Unification, UnifyContext) - GoalInfo.

%-----------------------------------------------------------------------------%

make_simple_test(X, Y, UnifyMainContext, UnifySubContext, Goal) :-
    Ground = ground(shared, none),
    Mode = ((Ground -> Ground) - (Ground -> Ground)),
    Unification = simple_test(X, Y),
    UnifyContext = unify_context(UnifyMainContext, UnifySubContext),
    instmap_delta_init_reachable(InstMapDelta),
    goal_info_init(list_to_set([X, Y]), InstMapDelta, detism_semi, purity_pure,
        GoalInfo),
    Goal = unify(X, rhs_var(Y), Mode, Unification, UnifyContext) - GoalInfo.

%-----------------------------------------------------------------------------%

make_int_const_construction_alloc_in_proc(Int, MaybeName, Goal, Var,
        !ProcInfo) :-
    proc_info_create_var_from_type(int_type, MaybeName, Var, !ProcInfo),
    make_int_const_construction(Var, Int, Goal).

make_string_const_construction_alloc_in_proc(String, MaybeName, Goal, Var,
        !ProcInfo) :-
    proc_info_create_var_from_type(string_type, MaybeName, Var, !ProcInfo),
    make_string_const_construction(Var, String, Goal).

make_float_const_construction_alloc_in_proc(Float, MaybeName, Goal, Var,
        !ProcInfo) :-
    proc_info_create_var_from_type(float_type, MaybeName, Var, !ProcInfo),
    make_float_const_construction(Var, Float, Goal).

make_char_const_construction_alloc_in_proc(Char, MaybeName, Goal, Var,
        !ProcInfo) :-
    proc_info_create_var_from_type(char_type, MaybeName, Var, !ProcInfo),
    make_char_const_construction(Var, Char, Goal).

make_const_construction_alloc_in_proc(ConsId, Type, MaybeName, Goal, Var,
        !ProcInfo) :-
    proc_info_create_var_from_type(Type, MaybeName, Var, !ProcInfo),
    make_const_construction(Var, ConsId, Goal).

make_int_const_construction_alloc(Int, MaybeName, Goal, Var,
        !VarSet, !VarTypes) :-
    svvarset.new_maybe_named_var(MaybeName, Var, !VarSet),
    svmap.det_insert(Var, int_type, !VarTypes),
    make_int_const_construction(Var, Int, Goal).

make_string_const_construction_alloc(String, MaybeName, Goal, Var,
        !VarSet, !VarTypes) :-
    svvarset.new_maybe_named_var(MaybeName, Var, !VarSet),
    svmap.det_insert(Var, string_type, !VarTypes),
    make_string_const_construction(Var, String, Goal).

make_float_const_construction_alloc(Float, MaybeName, Goal, Var,
        !VarSet, !VarTypes) :-
    svvarset.new_maybe_named_var(MaybeName, Var, !VarSet),
    svmap.det_insert(Var, float_type, !VarTypes),
    make_float_const_construction(Var, Float, Goal).

make_char_const_construction_alloc(Char, MaybeName, Goal, Var,
        !VarSet, !VarTypes) :-
    svvarset.new_maybe_named_var(MaybeName, Var, !VarSet),
    svmap.det_insert(Var, char_type, !VarTypes),
    make_char_const_construction(Var, Char, Goal).

make_const_construction_alloc(ConsId, Type, MaybeName, Goal, Var,
        !VarSet, !VarTypes) :-
    svvarset.new_maybe_named_var(MaybeName, Var, !VarSet),
    svmap.det_insert(Var, Type, !VarTypes),
    make_const_construction(Var, ConsId, Goal).

make_int_const_construction(Var, Int, Goal) :-
    make_const_construction(Var, int_const(Int), Goal).

make_string_const_construction(Var, String, Goal) :-
    make_const_construction(Var, string_const(String), Goal).

make_float_const_construction(Var, Float, Goal) :-
    make_const_construction(Var, float_const(Float), Goal).

make_char_const_construction(Var, Char, Goal) :-
    string.char_to_string(Char, String),
    make_const_construction(Var, cons(unqualified(String), 0), Goal).

make_const_construction(Var, ConsId, Goal - GoalInfo) :-
    RHS = rhs_functor(ConsId, no, []),
    Inst = bound(unique, [bound_functor(ConsId, [])]),
    Mode = (free -> Inst) - (Inst -> Inst),
    Unification = construct(Var, ConsId, [], [],
        construct_dynamically, cell_is_unique, no_construct_sub_info),
    Context = unify_context(umc_explicit, []),
    Goal = unify(Var, RHS, Mode, Unification, Context),
    set.singleton_set(NonLocals, Var),
    instmap_delta_init_reachable(InstMapDelta0),
    instmap_delta_insert(Var, Inst, InstMapDelta0, InstMapDelta),
    goal_info_init(NonLocals, InstMapDelta, detism_det, purity_pure, GoalInfo).

construct_functor(Var, ConsId, Args, Goal) :-
    list.length(Args, Arity),
    Rhs = rhs_functor(ConsId, no, Args),
    UnifyMode = (free_inst -> ground_inst) - (ground_inst -> ground_inst),
    UniMode = ((free_inst - ground_inst) -> (ground_inst - ground_inst)),
    list.duplicate(Arity, UniMode, UniModes),
    Unification = construct(Var, ConsId, Args, UniModes,
        construct_dynamically, cell_is_unique, no_construct_sub_info),
    UnifyContext = unify_context(umc_explicit, []),
    Unify = unify(Var, Rhs, UnifyMode, Unification, UnifyContext),
    set.list_to_set([Var | Args], NonLocals),
    instmap_delta_from_assoc_list([Var - ground_inst], InstMapDelta),
    goal_info_init(NonLocals, InstMapDelta, detism_det, purity_pure, GoalInfo),
    Goal = Unify - GoalInfo.

deconstruct_functor(Var, ConsId, Args, Goal) :-
    list.length(Args, Arity),
    Rhs = rhs_functor(ConsId, no, Args),
    UnifyMode = (ground_inst -> free_inst) - (ground_inst -> ground_inst),
    UniMode = ((ground_inst - free_inst) -> (ground_inst - ground_inst)),
    list.duplicate(Arity, UniMode, UniModes),
    UnifyContext = unify_context(umc_explicit, []),
    Unification = deconstruct(Var, ConsId, Args, UniModes, cannot_fail,
        cannot_cgc),
    Unify = unify(Var, Rhs, UnifyMode, Unification, UnifyContext),
    set.list_to_set([Var | Args], NonLocals),
    list.duplicate(Arity, ground_inst, DeltaValues),
    assoc_list.from_corresponding_lists(Args, DeltaValues, DeltaAL),
    instmap_delta_from_assoc_list(DeltaAL, InstMapDelta),
    goal_info_init(NonLocals, InstMapDelta, detism_det, purity_pure, GoalInfo),
    Goal = Unify - GoalInfo.

construct_tuple(Tuple, Args, Goal) :-
    list.length(Args, Arity),
    ConsId = cons(unqualified("{}"), Arity),
    construct_functor(Tuple, ConsId, Args, Goal).

deconstruct_tuple(Tuple, Args, Goal) :-
    list.length(Args, Arity),
    ConsId = cons(unqualified("{}"), Arity),
    deconstruct_functor(Tuple, ConsId, Args, Goal).

%-----------------------------------------------------------------------------%

get_pragma_foreign_var_names(MaybeVarNames, VarNames) :-
    get_pragma_foreign_var_names_2(MaybeVarNames, [], VarNames0),
    list.reverse(VarNames0, VarNames).

:- pred get_pragma_foreign_var_names_2(list(maybe(pair(string, mer_mode)))::in,
    list(string)::in, list(string)::out) is det.

get_pragma_foreign_var_names_2([], !Names).
get_pragma_foreign_var_names_2([MaybeName | MaybeNames], !Names) :-
    (
        MaybeName = yes(Name - _),
        !:Names = [Name | !.Names]
    ;
        MaybeName = no
    ),
    get_pragma_foreign_var_names_2(MaybeNames, !Names).

%-----------------------------------------------------------------------------%
%
% Extra goal info.
%

:- type hlds_goal_extra_info
    --->    extra_info(
                extra_info_ho_vals              :: ho_values,
                extra_info_maybe_ctgc_info      :: maybe(ctgc_info)
                    % Any information related to structure reuse (CTGC).
            ).

:- func hlds_goal_extra_info_init = hlds_goal_extra_info.

hlds_goal_extra_info_init = ExtraInfo :-
    HO_Values = map.init,
    ExtraInfo = extra_info(HO_Values, no).

goal_info_get_ho_values(GoalInfo) =
    GoalInfo ^ extra_goal_info ^ extra_info_ho_vals.

goal_info_set_ho_values(Values, !GoalInfo) :-
    !:GoalInfo = !.GoalInfo ^ extra_goal_info ^ extra_info_ho_vals := Values.

%-----------------------------------------------------------------------------%
% hlds_goal_reuse_info

:- type ctgc_info
    --->    ctgc_info(
                % The local forward use set: this set contains the variables
                % that are syntactically needed during forward execution.
                % It is computed as the set of instantiated vars (input vars
                % + sum(pre_births), minus the set of dead vars
                % (sum(post_deaths and pre_deaths).
                % The information is needed for determining the direct reuses.
                lfu     :: set(prog_var),

                % The local backward use set. This set contains the
                % instantiated variables that are needed upon backtracking
                % (i.e. syntactically appearing in any nondet call preceding
                % this goal).
                lbu     :: set(prog_var),

                % Any structure reuse information related to this call.
                reuse   :: reuse_description
            ).

:- func ctgc_info_init = ctgc_info.

ctgc_info_init = ctgc_info(set.init, set.init, empty).

goal_info_get_lfu(GoalInfo) = LFU :-
    ( goal_info_maybe_get_lfu(GoalInfo, LFU0) ->
        LFU = LFU0
    ;
        unexpected(this_file,
            "Requesting LFU information while CTGC field not set.")
    ).
goal_info_get_lbu(GoalInfo) = LBU :-
    ( goal_info_maybe_get_lbu(GoalInfo, LBU0) ->
        LBU = LBU0
    ;
        unexpected(this_file,
            "Requesting LBU information while CTGC field not set.")
    ).
goal_info_get_reuse(GoalInfo) = Reuse :-
    ( goal_info_maybe_get_reuse(GoalInfo, Reuse0) ->
        Reuse = Reuse0
    ;
        unexpected(this_file,
            "Requesting reuse information while CTGC field not set.")
    ).

goal_info_maybe_get_lfu(GoalInfo, LFU) :-
    MaybeCTGC = GoalInfo ^ extra_goal_info ^ extra_info_maybe_ctgc_info,
    MaybeCTGC = yes(CTGC),
    LFU = CTGC ^ lfu.
goal_info_maybe_get_lbu(GoalInfo, LBU) :-
    MaybeCTGC = GoalInfo ^ extra_goal_info ^ extra_info_maybe_ctgc_info,
    MaybeCTGC = yes(CTGC),
    LBU = CTGC ^ lbu.
goal_info_maybe_get_reuse(GoalInfo, Reuse) :-
    MaybeCTGC = GoalInfo ^ extra_goal_info ^ extra_info_maybe_ctgc_info,
    MaybeCTGC = yes(CTGC),
    Reuse = CTGC ^ reuse.

goal_info_set_lfu(LFU, !GoalInfo) :-
    MaybeCTGC0 = !.GoalInfo ^ extra_goal_info ^ extra_info_maybe_ctgc_info,
    (
        MaybeCTGC0 = yes(CTGC0)
    ;
        MaybeCTGC0 = no,
        CTGC0 = ctgc_info_init
    ),
    CTGC = CTGC0 ^ lfu := LFU,
    MaybeCTGC = yes(CTGC),
    !:GoalInfo = !.GoalInfo ^ extra_goal_info
        ^ extra_info_maybe_ctgc_info := MaybeCTGC.

goal_info_set_lbu(LBU, !GoalInfo) :-
    MaybeCTGC0 = !.GoalInfo ^ extra_goal_info ^ extra_info_maybe_ctgc_info,
    (
        MaybeCTGC0 = yes(CTGC0)
    ;
        MaybeCTGC0 = no,
        CTGC0 = ctgc_info_init
    ),
    CTGC = CTGC0 ^ lbu := LBU,
    MaybeCTGC = yes(CTGC),
    !:GoalInfo = !.GoalInfo ^ extra_goal_info
        ^ extra_info_maybe_ctgc_info := MaybeCTGC.

goal_info_set_reuse(Reuse, !GoalInfo) :-
    MaybeCTGC0 = !.GoalInfo ^ extra_goal_info ^ extra_info_maybe_ctgc_info,
    (
        MaybeCTGC0 = yes(CTGC0)
    ;
        MaybeCTGC0 = no,
        CTGC0 = ctgc_info_init
    ),
    CTGC = CTGC0 ^ reuse := Reuse,
    MaybeCTGC = yes(CTGC),
    !:GoalInfo = !.GoalInfo ^ extra_goal_info
        ^ extra_info_maybe_ctgc_info := MaybeCTGC.

%-----------------------------------------------------------------------------%

:- func this_file = string.

this_file = "hlds_goal".

%-----------------------------------------------------------------------------%
:- end_module hlds_goal.
%-----------------------------------------------------------------------------%
