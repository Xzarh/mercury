%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 2005-2006 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: prim_data.m.
% Main authors: fjh, zs.
%
% This module contains some types and predicates that are, or are planned to
% be, shared between the compiler and the debugger.

%-----------------------------------------------------------------------------%

:- module mdbcomp.prim_data.

:- interface.

    % This enumeration must be EXACTLY the same as the MR_PredFunc enum
    % in runtime/mercury_stack_layout.h, and in the same order, since the
    % code (in browser) assumes the representation is the same.
:- type pred_or_func
    --->    predicate
    ;       function.

    % The kinds of events with which MR_trace may be called, either
    % by compiler-generated code, or by code in the standard library
    % referring to compiler-generated data structures.
    %
    % This enumeration must be EXACTLY the same as the MR_trace_port enum
    % in runtime/mercury_trace_base.h, and in the same order, since the
    % code (in browser) assumes the representation is the same.
:- type trace_port
    --->    call
    ;       exit
    ;       redo
    ;       fail
    ;       exception
    ;       ite_cond
    ;       ite_then
    ;       ite_else
    ;       neg_enter
    ;       neg_success
    ;       neg_failure
    ;       disj
    ;       switch
    ;       nondet_pragma_first
    ;       nondet_pragma_later.

% was in compiler/prog_data.m

    % The order that the sym_name function symbols appear in can be significant
    % for module dependency ordering.
:- type sym_name
    --->    unqualified(string)
    ;       qualified(sym_name, string).

:- type module_name == sym_name.

% was in compiler/proc_label.m

    % A proc_label is a data structure a backend can use to as the basis
    % of the label used as the entry point of a procedure.
    %
    % The defining module is the module that provides the code for the
    % predicate, the declaring module contains the `:- pred' declaration.
    % When these are different, as for specialised versions of predicates
    % from `.opt' files, the defining module's name may need to be added
    % as a qualifier to the label.
:- type proc_label
    --->    ordinary_proc_label(
                ord_defining_module     :: module_name,
                ord_p_or_f              :: pred_or_func,
                ord_declaring_module    :: module_name,
                ord_pred_name           :: string,
                ord_arity               :: int,
                ord_mode_number         :: int
            )
    ;       special_proc_label(
                spec_defining_module    :: module_name,
                spec_spec_id            :: special_pred_id,
                                        % The special_pred_id indirectly
                                        % defines the predicate name.
                spec_type_module        :: module_name,
                spec_type_name          :: string,
                spec_type_arity         :: int,
                spec_mode_number        :: int
            ).

:- type special_pred_id
    --->    spec_pred_unify
    ;       spec_pred_index
    ;       spec_pred_compare
    ;       spec_pred_init.

    % special_pred_name_arity(SpecialPredId, GenericPredName, TargetName,
    %   Arity):
    %
    % True iff there is a special predicate of category SpecialPredId,
    % called builtin.GenericPredName/Arity, and for which the name of the
    % predicate in the target language is TargetName.
    %
:- pred special_pred_name_arity(special_pred_id, string, string, int).
:- mode special_pred_name_arity(in, out, out, out) is det.
:- mode special_pred_name_arity(out, in, out, out) is semidet.
:- mode special_pred_name_arity(out, out, in, out) is semidet.

    % get_special_pred_id_generic_name(SpecialPredId) = GenericPredName:
    %
    % The name of the generic predicate for SpecialPredId is
    % builtin.GenericPredName.
    %
:- func get_special_pred_id_generic_name(special_pred_id) = string.

    % get_special_pred_id_target_name(SpecialPredId) = TargetName:
    %
    % The name of the predicate in the target language for SpecialPredId is
    % TargetName.
    %
:- func get_special_pred_id_target_name(special_pred_id) = string.

    % get_special_pred_id_name(SpecialPredId) = Arity:
    %
    % The arity of the SpecialPredId predicate is Arity.
    %
:- func get_special_pred_id_arity(special_pred_id) = int.

    % string_to_sym_name(String, Separator, SymName):
    %
    % Convert a string, possibly prefixed with module qualifiers (separated
    % by Separator), into a symbol name.
    %
:- pred string_to_sym_name(string::in, string::in, sym_name::out) is det.

    % sym_name_to_string(SymName, Separator, String):
    %
    % Convert a symbol name to a string, with module qualifiers separated
    % by Separator.
    %
:- pred sym_name_to_string(sym_name::in, string::in, string::out) is det.
:- func sym_name_to_string(sym_name, string) = string.

    % sym_name_to_string(SymName, String):
    %
    % Convert a symbol name to a string, with module qualifiers separated by
    % the standard Mercury module qualifier operator.
    %
:- pred sym_name_to_string(sym_name::in, string::out) is det.
:- func sym_name_to_string(sym_name) = string.

    % is_submodule(SymName1, SymName2):
    %
    % True iff SymName1 is a submodule of SymName2.
    % For example mod1.mod2.mod3 is a submodule of mod1.mod2.
    %
:- pred is_submodule(module_name::in, module_name::in) is semidet.

    % insert_module_qualifier(ModuleName, SymName0, SymName):
    %
    % Prepend the specified ModuleName onto the module qualifiers in SymName0,
    % giving SymName.
    %
:- pred insert_module_qualifier(string::in, sym_name::in, sym_name::out)
    is det.

    % Returns the name of the module containing public builtins;
    % originally this was "mercury_builtin", but it later became
    % just "builtin", and it may eventually be renamed "std.builtin".
    % This module is automatically imported, as if via `import_module'.
    %
:- pred mercury_public_builtin_module(sym_name::out) is det.
:- func mercury_public_builtin_module = sym_name.

    % Returns the name of the module containing private builtins;
    % traditionally this was "mercury_builtin", but it later became
    % "private_builtin", and it may eventually be renamed
    % "std.private_builtin". This module is automatically imported,
    % as if via `use_module'.
    %
:- pred mercury_private_builtin_module(sym_name::out) is det.
:- func mercury_private_builtin_module = sym_name.

    % Returns the name of the module containing builtins for tabling;
    % originally these were in "private_builtin", but were then moved into
    % a separate module. This module is automatically imported iff any
    % predicate is tabled.
    %
:- pred mercury_table_builtin_module(sym_name::out) is det.
:- func mercury_table_builtin_module = sym_name.

    % Returns the name of the module containing the builtins for deep
    % profiling. This module is automatically imported iff deep profiling
    % is enabled.
    %
:- pred mercury_profiling_builtin_module(sym_name::out) is det.
:- func mercury_profiling_builtin_module = sym_name.

    % Returns the name of the module containing the builtins for term size
    % profiling. This module is automatically imported iff term size profiling
    % is enabled.
    %
:- pred mercury_term_size_prof_builtin_module(sym_name::out) is det.
:- func mercury_term_size_prof_builtin_module = sym_name.

    % Returns the sym_name of the module with the given name in the
    % Mercury standard library.
    %
:- pred mercury_std_lib_module_name(string::in, sym_name::out) is det.
:- func mercury_std_lib_module_name(string) = sym_name.

    % Succeeds iff the specified module is one of the builtin modules listed
    % above which may be automatically imported.
    %
:- pred any_mercury_builtin_module(sym_name::in) is semidet.

    % Succeeds iff the specified module will never be traced.
    %
:- pred non_traced_mercury_builtin_module(sym_name::in) is semidet.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module int.
:- import_module list.
:- import_module string.

string_to_sym_name(String, ModuleSeparator, Result) :-
    % This would be simpler if we had a string.rev_sub_string_search/3 pred.
    % With that, we could search for underscores right-to-left, and construct
    % the resulting symbol directly. Instead, we search for them left-to-right,
    % and then call insert_module_qualifier to fix things up.
    (
        string.sub_string_search(String, ModuleSeparator, LeftLength),
        LeftLength > 0
    ->
        string.left(String, LeftLength, ModuleName),
        string.length(String, StringLength),
        string.length(ModuleSeparator, SeparatorLength),
        RightLength = StringLength - LeftLength - SeparatorLength,
        string.right(String, RightLength, Name),
        string_to_sym_name(Name, ModuleSeparator, NameSym),
        insert_module_qualifier(ModuleName, NameSym, Result)
    ;
        Result = unqualified(String)
    ).

insert_module_qualifier(ModuleName, unqualified(PlainName),
        qualified(unqualified(ModuleName), PlainName)).
insert_module_qualifier(ModuleName, qualified(ModuleQual0, PlainName),
        qualified(ModuleQual, PlainName)) :-
    insert_module_qualifier(ModuleName, ModuleQual0, ModuleQual).

sym_name_to_string(SymName, String) :-
    sym_name_to_string(SymName, ".", String).

sym_name_to_string(SymName) = String :-
    sym_name_to_string(SymName, String).

sym_name_to_string(SymName, Separator) = String :-
    sym_name_to_string(SymName, Separator, String).

sym_name_to_string(unqualified(Name), _Separator, Name).
sym_name_to_string(qualified(ModuleSym, Name), Separator, QualName) :-
    sym_name_to_string(ModuleSym, Separator, ModuleName),
    string.append_list([ModuleName, Separator, Name], QualName).

is_submodule(SymName, SymName).
is_submodule(qualified(SymNameA, _), SymNameB) :-
    is_submodule(SymNameA, SymNameB).

special_pred_name_arity(spec_pred_unify, "unify", "__Unify__", 2).
special_pred_name_arity(spec_pred_index, "index", "__Index__", 2).
special_pred_name_arity(spec_pred_compare, "compare", "__Compare__", 3).
special_pred_name_arity(spec_pred_init, "initialise", "__Initialise__", 1).

get_special_pred_id_generic_name(Id) = Name :-
        special_pred_name_arity(Id, Name, _, _).

get_special_pred_id_target_name(Id) = Name :-
        special_pred_name_arity(Id, _, Name, _).

get_special_pred_id_arity(Id) = Arity :-
        special_pred_name_arity(Id, _, _, Arity).

% We may eventually want to put the standard library into a package "std":
% mercury_public_builtin_module = qualified(unqualified("std"), "builtin").
% mercury_private_builtin_module(M) =
%       qualified(unqualified("std"), "private_builtin"))).
mercury_public_builtin_module = unqualified("builtin").
mercury_public_builtin_module(mercury_public_builtin_module).
mercury_private_builtin_module = unqualified("private_builtin").
mercury_private_builtin_module(mercury_private_builtin_module).
mercury_table_builtin_module = unqualified("table_builtin").
mercury_table_builtin_module(mercury_table_builtin_module).
mercury_profiling_builtin_module = unqualified("profiling_builtin").
mercury_profiling_builtin_module(mercury_profiling_builtin_module).
mercury_term_size_prof_builtin_module = unqualified("term_size_prof_builtin").
mercury_term_size_prof_builtin_module(mercury_term_size_prof_builtin_module).
mercury_std_lib_module_name(Name) = unqualified(Name).
mercury_std_lib_module_name(Name, unqualified(Name)).

any_mercury_builtin_module(Module) :-
    ( mercury_public_builtin_module(Module)
    ; mercury_private_builtin_module(Module)
    ; mercury_table_builtin_module(Module)
    ; mercury_profiling_builtin_module(Module)
    ; mercury_term_size_prof_builtin_module(Module)
    ).

non_traced_mercury_builtin_module(Module) :-
    ( mercury_table_builtin_module(Module)
    ; mercury_profiling_builtin_module(Module)
    ; mercury_term_size_prof_builtin_module(Module)
    ).
