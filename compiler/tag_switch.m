%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 1994-2000,2002-2007 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: tag_switch.m.
% Author: zs.
%
% Generate switches based on primary and secondary tags.
%
%-----------------------------------------------------------------------------%

:- module ll_backend.tag_switch.
:- interface.

:- import_module hlds.code_model.
:- import_module hlds.hlds_goal.
:- import_module ll_backend.code_info.
:- import_module ll_backend.llds.
:- import_module parse_tree.prog_data.

:- import_module list.

%-----------------------------------------------------------------------------%

    % Generate intelligent indexing code for tag based switches.
    %
:- pred generate_tag_switch(list(tagged_case)::in, rval::in, mer_type::in,
    string::in, code_model::in, can_fail::in, hlds_goal_info::in, label::in,
    branch_end::in, branch_end::out, code_tree::out,
    code_info::in, code_info::out) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module backend_libs.builtin_ops.
:- import_module backend_libs.rtti.
:- import_module backend_libs.switch_util.
:- import_module hlds.hlds_data.
:- import_module hlds.hlds_llds.
:- import_module hlds.hlds_out.
:- import_module hlds.hlds_pred.
:- import_module libs.compiler_util.
:- import_module libs.globals.
:- import_module libs.options.
:- import_module libs.tree.
:- import_module ll_backend.code_gen.
:- import_module ll_backend.switch_case.
:- import_module ll_backend.trace_gen.
:- import_module parse_tree.prog_data.

:- import_module assoc_list.
:- import_module int.
:- import_module map.
:- import_module maybe.
:- import_module pair.
:- import_module string.
:- import_module svmap.

%-----------------------------------------------------------------------------%

    % The idea is to generate two-level switches, first on the primary
    % tag and then on the secondary tag. Since more than one function
    % symbol can be eliminated by a failed primary tag test, this reduces
    % the expected the number of comparisons required before finding the
    % code corresponding to the actual value of the switch variable.
    % We also get a speedup compared to non-tag switches by extracting
    % the primary and secondary tags once instead of repeatedly for
    % each functor test.
    %
    % We have four methods we can use for generating the code for the
    % switches on both primary and secondary tags.
    %
    % 1. try-me-else chains have the form
    %
    %       if (tag(var) != tag1) goto L1
    %       code for tag1
    %       goto end
    %   L1: if (tag(var) != tag2) goto L2
    %       code for tag2
    %       goto end
    %   L2: ...
    %   Ln: code for last possible tag value (or failure)
    %       goto end
    %
    % 2. try chains have the form
    %
    %       if (tag(var) == tag1) goto L1
    %       if (tag(var) == tag2) goto L2
    %       ...
    %       code for last possible tag value (or failure)
    %       goto end
    %   L1: code for tag1
    %       goto end
    %   L2: code for tag2
    %       goto end
    %       ...
    %
    % 3. jump tables have the form
    %
    %       goto tag(var) of L1, L2, ...
    %   L1: code for tag1
    %       goto end
    %   L2: code for tag2
    %       goto end
    %       ...
    %
    % 4. binary search switches have the form
    %
    %       if (tag(var)) > 1) goto L23
    %       if (tag(var)) != 0) goto L1
    %       code for tag 0
    %       goto end
    %   L1: code for tag 1
    %       goto end
    %   L23:    if (tag(var)) != 2) goto L3
    %       code for tag 2
    %       goto end
    %   L3: code for tag 3
    %       goto end
    %
    % Note that for a det switch with two tag values, try-me-else chains
    % and try chains are equivalent.
    %
    % Which method is best depends
    % - on the number of possible tag values,
    % - on the costs of taken/untaken branches and table lookups on the given
    %   architecture, and
    % - on the frequency with which the various alternatives are taken.
    %
    % While the first two are in principle known at compile time, the third
    % is not (at least not without feedback from a profiler). Nevertheless,
    % for switches on primary tags we can use the heuristic that the more
    % secondary tags assigned to a primary tag, the more likely that the
    % switch variable will have that primary tag at runtime.
    %
    % Try chains are good for switches with small numbers of alternatives
    % on architectures where untaken branches are cheaper than taken
    % branches.
    %
    % Try-me-else chains are good for switches with very small numbers of
    % alternatives on architectures where taken branches are cheaper than
    % untaken branches (which are rare these days).
    %
    % Jump tables are good for switches with large numbers of alternatives.
    % The cost of jumping through a jump table is relatively high, since
    % it involves a memory access and an indirect branch (which most
    % current architectures do not handle well), but this cost is
    % independent of the number of alternatives.
    %
    % Binary search switches are good for switches where the number of
    % alternatives is large enough for the reduced expected number of
    % branches executed to overcome the extra overhead of the subtraction
    % required for some conditional branches (compared to try chains
    % and try-me-else chains), but not large enough to make the
    % expected cost of the expected number of comparisons exceed the
    % expected cost of a jump table lookup and dispatch.

    % For try-me-else chains, we want tag1 to be the most frequent case,
    % tag2 the next most frequent case, etc.
    %
    % For det try chains, we want the last tag value to be the most
    % frequent case, since it can be reached without taken jumps.
    % We want tag1 to be the next most frequent, tag2 the next most
    % frequent after that, etc.
    %
    % For semidet try chains, there is no last possible tag value (the
    % code for failure occupies its position), so we want tag1 to be
    % the most frequent case, tag 2 the next most frequent case, etc.
    %
    % For jump tables, the position of the labels in the computed goto
    % must conform to their numerical value. The order of the code
    % fragments does not really matter, although the last has a slight
    % edge in that no goto is needed to reach the code following the
    % switch. If there is no code following the switch (which happens
    % very frequently), then even this advantage is nullified.
    %
    % For binary search switches, we want the case of the most frequently
    % occurring tag to be the first, since this code is reached with no
    % taken branches and ends with an unconditional branch, whereas
    % reaching the code of the other cases requires at least one taken
    % *conditional* branch. In general, at each binary decision we
    % want the more frequently reached cases to be in the half that
    % immediately follows the if statement implementing the decision.

:- type switch_method
    --->    try_me_else_chain
    ;       try_chain
    ;       jump_table
    ;       binary_search.

%-----------------------------------------------------------------------------%

generate_tag_switch(TaggedCases, VarRval, VarType, VarName, CodeModel, CanFail,
        SwitchGoalInfo, EndLabel, !MaybeEnd, Code, !CI) :-

    % We get registers for holding the primary and (if needed) the secondary
    % tag. The tags needed only by the switch, and no other code gets control
    % between producing the tag values and all their uses, so we can release
    % the registers for use by the code of the various cases.
    %
    % We forgo using the primary tag register if the primary tag is needed
    % only once, or if the "register" we get is likely to be slower than
    % recomputing the tag from scratch.
    %
    % We need to get and release the registers before we generate the code
    % of the switch arms, since the set of free registers will in general be
    % different before and after that action.
    acquire_reg(reg_r, PtagReg, !CI),
    acquire_reg(reg_r, StagReg, !CI),
    release_reg(PtagReg, !CI),
    release_reg(StagReg, !CI),

    % Group the cases based on primary tag value and find out how many
    % constructors share each primary tag value.
    get_module_info(!.CI, ModuleInfo),
    get_ptag_counts(VarType, ModuleInfo, MaxPrimary, PtagCountMap),
    map.to_assoc_list(PtagCountMap, PtagCountList),
    remember_position(!.CI, BranchStart),
    Params = represent_params(VarName, SwitchGoalInfo, CodeModel, BranchStart,
        EndLabel),
    map.init(CaseLabelMap0),
    map.init(PtagCaseMap0),
    group_cases_by_ptag(TaggedCases,
        represent_tagged_case_for_llds(Params),
        CaseLabelMap0, CaseLabelMap1, !MaybeEnd, !CI,
        PtagCaseMap0, PtagCaseMap),

    map.count(PtagCaseMap, PtagsUsed),
    get_globals(!.CI, Globals),
    globals.lookup_int_option(Globals, dense_switch_size, DenseSwitchSize),
    globals.lookup_int_option(Globals, try_switch_size, TrySwitchSize),
    globals.lookup_int_option(Globals, binary_switch_size, BinarySwitchSize),
    ( PtagsUsed >= DenseSwitchSize ->
        PrimaryMethod = jump_table
    ; PtagsUsed >= BinarySwitchSize ->
        PrimaryMethod = binary_search
    ; PtagsUsed >= TrySwitchSize ->
        PrimaryMethod = try_chain
    ;
        PrimaryMethod = try_me_else_chain
    ),

    (
        PrimaryMethod \= jump_table,
        PtagsUsed >= 2,
        globals.lookup_int_option(Globals, num_real_r_regs, NumRealRegs),
        (
            NumRealRegs = 0
        ;
            ( PtagReg = reg(reg_r, PtagRegNo) ->
                PtagRegNo =< NumRealRegs
            ;
                unexpected(this_file, "improper reg in tag switch")
            )
        )
    ->
        PtagCode = node([
            llds_instr(assign(PtagReg, unop(tag, VarRval)),
                "compute tag to switch on")
        ]),
        PtagRval = lval(PtagReg)
    ;
        PtagCode = empty,
        PtagRval = unop(tag, VarRval)
    ),

    % We generate EndCode (and if needed, FailCode) here because the last
    % case within a primary tag may not be the last case overall.
    EndCode = node([llds_instr(label(EndLabel), "end of tag switch")]),
    (
        CanFail = cannot_fail,
        MaybeFailLabel = no,
        FailCode = empty
    ;
        CanFail = can_fail,
        get_next_label(FailLabel, !CI),
        MaybeFailLabel = yes(FailLabel),
        FailLabelCode = node([
            llds_instr(label(FailLabel), "switch has failed")
        ]),
        % We must generate the failure code in the context in which none of the
        % switch arms have been executed yet.
        reset_to_position(BranchStart, !CI),
        generate_failure(FailureCode, !CI),
        FailCode = tree(FailLabelCode, FailureCode)
    ),

    (
        PrimaryMethod = binary_search,
        order_ptags_by_value(0, MaxPrimary, PtagCaseMap, PtagCaseList),
        generate_primary_binary_search(PtagCaseList, 0, MaxPrimary, PtagRval,
            StagReg, VarRval, MaybeFailLabel, PtagCountMap, CasesCode,
            CaseLabelMap1, CaseLabelMap, !CI)
    ;
        PrimaryMethod = jump_table,
        order_ptags_by_value(0, MaxPrimary, PtagCaseMap, PtagCaseList),
        generate_primary_jump_table(PtagCaseList, 0, MaxPrimary, StagReg,
            VarRval, MaybeFailLabel, PtagCountMap, Targets, TableCode,
            CaseLabelMap1, CaseLabelMap, !CI),
        SwitchCode = node([
            llds_instr(computed_goto(PtagRval, Targets),
                "switch on primary tag")
        ]),
        CasesCode = tree(SwitchCode, TableCode)
    ;
        PrimaryMethod = try_chain,
        order_ptags_by_count(PtagCountList, PtagCaseMap, PtagCaseList0),
        (
            CanFail = cannot_fail,
            PtagCaseList0 = [MostFreqCase | OtherCases]
        ->
            PtagCaseList = OtherCases ++ [MostFreqCase]
        ;
            PtagCaseList = PtagCaseList0
        ),
        generate_primary_try_chain(PtagCaseList, PtagRval, StagReg, VarRval,
            MaybeFailLabel, PtagCountMap, empty, empty, CasesCode,
            CaseLabelMap1, CaseLabelMap, !CI)
    ;
        PrimaryMethod = try_me_else_chain,
        order_ptags_by_count(PtagCountList, PtagCaseMap, PtagCaseList),
        generate_primary_try_me_else_chain(PtagCaseList, PtagRval, StagReg,
            VarRval, MaybeFailLabel, PtagCountMap, CasesCode,
            CaseLabelMap1, CaseLabelMap, !CI)
    ),
    map.foldl(add_remaining_case, CaseLabelMap, empty, RemainingCasesCode),
    Code = tree_list([PtagCode, CasesCode, RemainingCasesCode, FailCode,
        EndCode]).

%-----------------------------------------------------------------------------%

    % Generate a switch on a primary tag value using a try-me-else chain.
    %
:- pred generate_primary_try_me_else_chain(ptag_case_list(label)::in,
    rval::in, lval::in, rval::in, maybe(label)::in,
    ptag_count_map::in, code_tree::out,
    case_label_map::in, case_label_map::out,
    code_info::in, code_info::out) is det.

generate_primary_try_me_else_chain([], _, _, _, _, _, _,
        !CaseLabelMap, !CI) :-
    unexpected(this_file, "generate_primary_try_me_else_chain: empty switch").
generate_primary_try_me_else_chain([PtagGroup | PtagGroups], PtagRval, StagReg,
        VarRval, MaybeFailLabel, PtagCountMap, Code, !CaseLabelMap, !CI) :-
    PtagGroup = Primary - PtagCase,
    PtagCase = ptag_case(StagLoc, StagGoalMap),
    map.lookup(PtagCountMap, Primary, CountInfo),
    CountInfo = StagLocPrime - MaxSecondary,
    expect(unify(StagLoc, StagLocPrime), this_file,
        "generate_primary_try_me_else_chain: secondary tag locations differ"),
    (
        PtagGroups = [_ | _],
        generate_primary_try_me_else_chain_case(PtagRval, StagReg, Primary,
            PtagCase, MaxSecondary, VarRval, MaybeFailLabel, ThisTagCode,
            !CaseLabelMap, !CI),
        generate_primary_try_me_else_chain(PtagGroups, PtagRval, StagReg,
            VarRval, MaybeFailLabel, PtagCountMap, OtherTagsCode,
            !CaseLabelMap, !CI),
        Code = tree(ThisTagCode, OtherTagsCode)
    ;
        PtagGroups = [],
        (
            MaybeFailLabel = yes(FailLabel),
            generate_primary_try_me_else_chain_case(PtagRval, StagReg, Primary,
                PtagCase, MaxSecondary, VarRval, MaybeFailLabel, ThisTagCode,
                !CaseLabelMap, !CI),
            % FailLabel ought to be the next label anyway, so this goto
            % will be optimized away (unless the layout of the failcode
            % in the caller changes).
            FailCode = node([
                llds_instr(goto(code_label(FailLabel)),
                    "primary tag with no code to handle it")
            ]),
            Code = tree(ThisTagCode, FailCode)
        ;
            MaybeFailLabel = no,
            generate_primary_tag_code(StagGoalMap, Primary, MaxSecondary,
                StagReg, StagLoc, VarRval, MaybeFailLabel, Code,
                !CaseLabelMap, !CI)
        )
    ).

:- pred generate_primary_try_me_else_chain_case(rval::in, lval::in, int::in,
    ptag_case(label)::in, int::in, rval::in, maybe(label)::in,
    code_tree::out,
    case_label_map::in, case_label_map::out,
    code_info::in, code_info::out) is det.

generate_primary_try_me_else_chain_case(PtagRval, StagReg, Primary, PtagCase,
        MaxSecondary, VarRval, MaybeFailLabel, Code, !CaseLabelMap, !CI) :-
    get_next_label(ElseLabel, !CI),
    TestRval = binop(ne, PtagRval,
        unop(mktag, const(llconst_int(Primary)))),
    TestCode = node([
        llds_instr(if_val(TestRval, code_label(ElseLabel)),
            "test primary tag only")
    ]),
    PtagCase = ptag_case(StagLoc, StagGoalMap),
    generate_primary_tag_code(StagGoalMap, Primary, MaxSecondary,
        StagReg, StagLoc, VarRval, MaybeFailLabel, TagCode,
        !CaseLabelMap, !CI),
    ElseCode = node([
        llds_instr(label(ElseLabel), "handle next primary tag")
    ]),
    Code = tree_list([TestCode, TagCode, ElseCode]).

%-----------------------------------------------------------------------------%

    % Generate a switch on a primary tag value using a try chain.
    %
:- pred generate_primary_try_chain(ptag_case_list(label)::in,
    rval::in, lval::in, rval::in, maybe(label)::in,
    ptag_count_map::in, code_tree::in, code_tree::in, code_tree::out,
    case_label_map::in, case_label_map::out,
    code_info::in, code_info::out) is det.

generate_primary_try_chain([], _, _, _, _, _, _, _, _, !CaseLabelMap, !CI) :-
     unexpected(this_file, "empty list in generate_primary_try_chain").
generate_primary_try_chain([PtagGroup | PtagGroups], PtagRval, StagReg,
        VarRval, MaybeFailLabel, PtagCountMap, PrevTestsCode0, PrevCasesCode0,
        Code, !CaseLabelMap, !CI) :-
    PtagGroup = Primary - PtagCase,
    PtagCase = ptag_case(StagLoc, StagGoalMap),
    map.lookup(PtagCountMap, Primary, CountInfo),
    CountInfo = StagLocPrime - MaxSecondary,
    expect(unify(StagLoc, StagLocPrime), this_file,
        "secondary tag locations differ in generate_primary_try_chain"),
    (
        PtagGroups = [_ | _],
        generate_primary_try_chain_case(PtagRval, StagReg, Primary,
            PtagCase, MaxSecondary, VarRval, MaybeFailLabel,
            PrevTestsCode0, PrevTestsCode1, PrevCasesCode0, PrevCasesCode1,
            !CaseLabelMap, !CI),
        generate_primary_try_chain(PtagGroups, PtagRval, StagReg, VarRval,
            MaybeFailLabel, PtagCountMap, PrevTestsCode1, PrevCasesCode1,
            Code, !CaseLabelMap, !CI)
    ;
        PtagGroups = [],
        (
            MaybeFailLabel = yes(FailLabel),
            generate_primary_try_chain_case(PtagRval, StagReg, Primary,
                PtagCase, MaxSecondary, VarRval, MaybeFailLabel,
                PrevTestsCode0, PrevTestsCode1, PrevCasesCode0, PrevCasesCode1,
                !CaseLabelMap, !CI),
            FailCode = node([
                llds_instr(goto(code_label(FailLabel)),
                    "primary tag with no code to handle it")
            ]),
            Code = tree_list([PrevTestsCode1, FailCode, PrevCasesCode1])
        ;
            MaybeFailLabel = no,
            Comment = "fallthrough to last primary tag value: " ++
                string.int_to_string(Primary),
            CommentCode = node([
                llds_instr(comment(Comment), "")
            ]),
            generate_primary_tag_code(StagGoalMap, Primary, MaxSecondary,
                StagReg, StagLoc, VarRval, MaybeFailLabel, TagCode,
                !CaseLabelMap, !CI),
            Code = tree_list([PrevTestsCode0, CommentCode,
                TagCode, PrevCasesCode0])
        )
    ).

:- pred generate_primary_try_chain_case(rval::in, lval::in, int::in,
    ptag_case(label)::in, int::in, rval::in, maybe(label)::in,
    code_tree::in, code_tree::out, code_tree::in, code_tree::out,
    case_label_map::in, case_label_map::out,
    code_info::in, code_info::out) is det.

generate_primary_try_chain_case(PtagRval, StagReg, Primary, PtagCase,
        MaxSecondary, VarRval, MaybeFailLabel,
        PrevTestsCode0, PrevTestsCode, PrevCasesCode0, PrevCasesCode,
        !CaseLabelMap, !CI) :-
    get_next_label(ThisPtagLabel, !CI),
    TestRval = binop(eq, PtagRval,
        unop(mktag, const(llconst_int(Primary)))),
    TestCode = node([
        llds_instr(if_val(TestRval, code_label(ThisPtagLabel)),
            "test primary tag only")
    ]),
    Comment = "primary tag value: " ++ string.int_to_string(Primary),
    LabelCode = node([
        llds_instr(label(ThisPtagLabel), Comment)
    ]),
    PtagCase = ptag_case(StagLoc, StagGoalMap),
    generate_primary_tag_code(StagGoalMap, Primary, MaxSecondary,
        StagReg, StagLoc, VarRval, MaybeFailLabel, TagCode,
        !CaseLabelMap, !CI),
    PrevTestsCode = tree(PrevTestsCode0, TestCode),
    PrevCasesCode = tree_list([LabelCode, TagCode, PrevCasesCode0]).

%-----------------------------------------------------------------------------%

    % Generate the cases for a primary tag using a dense jump table
    % that has an entry for all possible primary tag values.
    %
:- pred generate_primary_jump_table(ptag_case_list(label)::in, int::in,
    int::in, lval::in, rval::in, maybe(label)::in, ptag_count_map::in,
    list(maybe(label))::out, code_tree::out,
    case_label_map::in, case_label_map::out,
    code_info::in, code_info::out) is det.

generate_primary_jump_table(PtagGroups, CurPrimary, MaxPrimary, StagReg,
        VarRval, MaybeFailLabel, PtagCountMap, Targets, Code,
        !CaseLabelMap, !CI) :-
    ( CurPrimary > MaxPrimary ->
        expect(unify(PtagGroups, []), this_file,
            "generate_primary_jump_table: PtagGroups != [] when Cur > Max"),
        Targets = [],
        Code = empty
    ;
        NextPrimary = CurPrimary + 1,
        ( PtagGroups = [CurPrimary - PrimaryInfo | PtagGroupsTail] ->
            PrimaryInfo = ptag_case(StagLoc, StagGoalMap),
            map.lookup(PtagCountMap, CurPrimary, CountInfo),
            CountInfo = StagLocPrime - MaxSecondary,
            expect(unify(StagLoc, StagLocPrime), this_file,
                "secondary tag locations differ " ++
                "in generate_primary_jump_table"),
            get_next_label(NewLabel, !CI),
            LabelCode = node([
                llds_instr(label(NewLabel),
                    "start of a case in primary tag switch")
            ]),
            generate_primary_tag_code(StagGoalMap, CurPrimary, MaxSecondary,
                StagReg, StagLoc, VarRval, MaybeFailLabel, ThisTagCode,
                !CaseLabelMap, !CI),
            generate_primary_jump_table(PtagGroupsTail, NextPrimary,
                MaxPrimary, StagReg, VarRval, MaybeFailLabel, PtagCountMap,
                TailTargets, TailCode, !CaseLabelMap, !CI),
            Targets = [yes(NewLabel) | TailTargets],
            Code = tree_list([LabelCode, ThisTagCode, TailCode])
        ;
            generate_primary_jump_table(PtagGroups, NextPrimary, MaxPrimary,
                StagReg, VarRval, MaybeFailLabel, PtagCountMap,
                TailTargets, TailCode, !CaseLabelMap, !CI),
            Targets = [MaybeFailLabel | TailTargets],
            Code = TailCode
        )
    ).

%-----------------------------------------------------------------------------%

    % Generate the cases for a primary tag using a binary search.
    % This invocation looks after primary tag values in the range
    % MinPtag to MaxPtag (including both boundary values).
    %
:- pred generate_primary_binary_search(ptag_case_list(label)::in, int::in,
    int::in, rval::in, lval::in, rval::in, maybe(label)::in,
    ptag_count_map::in, code_tree::out,
    case_label_map::in, case_label_map::out,
    code_info::in, code_info::out) is det.

generate_primary_binary_search(PtagGroups, MinPtag, MaxPtag, PtagRval, StagReg,
        VarRval, MaybeFailLabel, PtagCountMap, Code, !CaseLabelMap, !CI) :-
    ( MinPtag = MaxPtag ->
        CurPrimary = MinPtag,
        (
            PtagGroups = [],
            % There is no code for this tag.
            (
                MaybeFailLabel = yes(FailLabel),
                string.int_to_string(CurPrimary, PtagStr),
                Comment = "no code for ptag " ++ PtagStr,
                Code = node([llds_instr(goto(code_label(FailLabel)), Comment)])
            ;
                MaybeFailLabel = no,
                % The switch is cannot_fail, which means this case cannot
                % happen.
                Code = empty
            )
        ;
            PtagGroups = [CurPrimaryPrime - PrimaryInfo],
            expect(unify(CurPrimary, CurPrimaryPrime), this_file,
                "generate_primary_binary_search: cur_primary mismatch"),
            PrimaryInfo = ptag_case(StagLoc, StagGoalMap),
            map.lookup(PtagCountMap, CurPrimary, CountInfo),
            CountInfo = StagLocPrime - MaxSecondary,
            expect(unify(StagLoc, StagLocPrime), this_file,
                "generate_primary_jump_table: secondary tag locations differ"),
            generate_primary_tag_code(StagGoalMap, CurPrimary, MaxSecondary,
                StagReg, StagLoc, VarRval, MaybeFailLabel, Code,
                !CaseLabelMap, !CI)
        ;
            PtagGroups = [_, _ | _],
            unexpected(this_file,
                "caselist not singleton or empty when binary search ends")
        )
    ;
        LowRangeEnd = (MinPtag + MaxPtag) // 2,
        HighRangeStart = LowRangeEnd + 1,
        InLowGroup = (pred(PtagGroup::in) is semidet :-
            PtagGroup = Ptag - _,
            Ptag =< LowRangeEnd
        ),
        list.filter(InLowGroup, PtagGroups, LowGroups, HighGroups),
        get_next_label(NewLabel, !CI),
        string.int_to_string(MinPtag, LowStartStr),
        string.int_to_string(LowRangeEnd, LowEndStr),
        string.int_to_string(HighRangeStart, HighStartStr),
        string.int_to_string(MaxPtag, HighEndStr),
        IfComment = "fallthrough for ptags " ++
            LowStartStr ++ " to " ++ LowEndStr,
        LabelComment = "code for ptags " ++
            HighStartStr ++ " to " ++ HighEndStr,
        LowRangeEndConst = const(llconst_int(LowRangeEnd)),
        TestRval = binop(int_gt, PtagRval, LowRangeEndConst),
        IfCode = node([
            llds_instr(if_val(TestRval, code_label(NewLabel)), IfComment)
        ]),
        LabelCode = node([llds_instr(label(NewLabel), LabelComment)]),

        generate_primary_binary_search(LowGroups, MinPtag, LowRangeEnd,
            PtagRval, StagReg, VarRval, MaybeFailLabel, PtagCountMap,
            LowRangeCode, !CaseLabelMap, !CI),
        generate_primary_binary_search(HighGroups, HighRangeStart, MaxPtag,
            PtagRval, StagReg, VarRval, MaybeFailLabel, PtagCountMap,
            HighRangeCode, !CaseLabelMap, !CI),
        Code = tree_list([IfCode, LowRangeCode, LabelCode, HighRangeCode])
    ).

%-----------------------------------------------------------------------------%

    % Generate the code corresponding to a primary tag.
    % If this primary tag has secondary tags, decide whether we should
    % use a jump table to implement the secondary switch.
    %
:- pred generate_primary_tag_code(stag_goal_map(label)::in, tag_bits::in,
    int::in, lval::in, sectag_locn::in, rval::in, maybe(label)::in,
    code_tree::out, case_label_map::in, case_label_map::out,
    code_info::in, code_info::out) is det.

generate_primary_tag_code(StagGoalMap, Primary, MaxSecondary, StagReg, StagLoc,
        Rval, MaybeFailLabel, Code, !CaseLabelMap, !CI) :-
    map.to_assoc_list(StagGoalMap, StagGoalList),
    (
        StagLoc = sectag_none,
        % There is no secondary tag, so there is no switch on it.
        (
            StagGoalList = [],
            unexpected(this_file, "no goal for non-shared tag")
        ;
            StagGoalList = [StagGoal],
            ( StagGoal = -1 - CaseLabel ->
                generate_case_code_or_jump(CaseLabel, Code, !CaseLabelMap)
            ;
                unexpected(this_file, "badly formed goal for non-shared tag")
            )
        ;
            StagGoalList = [_, _ | _],
            unexpected(this_file, "more than one goal for non-shared tag")
        )
    ;
        ( StagLoc = sectag_local
        ; StagLoc = sectag_remote
        ),

        % There is a secondary tag, so figure out how to switch on it.
        get_globals(!.CI, Globals),
        globals.lookup_int_option(Globals, dense_switch_size,
            DenseSwitchSize),
        globals.lookup_int_option(Globals, binary_switch_size,
            BinarySwitchSize),
        globals.lookup_int_option(Globals, try_switch_size, TrySwitchSize),
        ( MaxSecondary >= DenseSwitchSize ->
            SecondaryMethod = jump_table
        ; MaxSecondary >= BinarySwitchSize ->
            SecondaryMethod = binary_search
        ; MaxSecondary >= TrySwitchSize ->
            SecondaryMethod = try_chain
        ;
            SecondaryMethod = try_me_else_chain
        ),

        (
            StagLoc = sectag_remote,
            OrigStagRval = lval(field(yes(Primary), Rval,
                const(llconst_int(0)))),
            Comment = "compute remote sec tag to switch on"
        ;
            StagLoc = sectag_local,
            OrigStagRval = unop(unmkbody, Rval),
            Comment = "compute local sec tag to switch on"
        ),

        (
            SecondaryMethod \= jump_table,
            MaxSecondary >= 2,
            globals.lookup_int_option(Globals, num_real_r_regs, NumRealRegs),
            (
                NumRealRegs = 0
            ;
                ( StagReg = reg(reg_r, StagRegNo) ->
                    StagRegNo =< NumRealRegs
                ;
                    unexpected(this_file, "improper reg in tag switch")
                )
            )
        ->
            StagCode = node([
                llds_instr(assign(StagReg, OrigStagRval), Comment)
            ]),
            StagRval = lval(StagReg)
        ;
            StagCode = empty,
            StagRval = OrigStagRval
        ),
        (
            MaybeFailLabel = yes(FailLabel),
            (
                list.length(StagGoalList, StagGoalCount),
                FullGoalCount = MaxSecondary + 1,
                FullGoalCount = StagGoalCount
            ->
                MaybeSecFailLabel = no
            ;
                MaybeSecFailLabel = yes(FailLabel)
            )
        ;
            MaybeFailLabel = no,
            MaybeSecFailLabel = no
        ),

        (
            SecondaryMethod = jump_table,
            generate_secondary_jump_table(StagGoalList, 0, MaxSecondary,
                MaybeSecFailLabel, Targets),
            Code = node([
                llds_instr(computed_goto(StagRval, Targets),
                    "switch on secondary tag")
            ])
        ;
            SecondaryMethod = binary_search,
            generate_secondary_binary_search(StagGoalList, 0, MaxSecondary,
                StagRval, MaybeSecFailLabel, Code, !CaseLabelMap, !CI)
        ;
            SecondaryMethod = try_chain,
            generate_secondary_try_chain(StagGoalList, StagRval,
                MaybeSecFailLabel, empty, Codes, !CaseLabelMap),
            Code = tree(StagCode, Codes)
        ;
            SecondaryMethod = try_me_else_chain,
            generate_secondary_try_me_else_chain(StagGoalList, StagRval,
                MaybeSecFailLabel, Codes, !CaseLabelMap, !CI),
            Code = tree(StagCode, Codes)
        )
    ).

%-----------------------------------------------------------------------------%

    % Generate a switch on a secondary tag value using a try-me-else chain.
    %
:- pred generate_secondary_try_me_else_chain(stag_goal_list(label)::in,
    rval::in, maybe(label)::in, code_tree::out,
    case_label_map::in, case_label_map::out,
    code_info::in, code_info::out) is det.

generate_secondary_try_me_else_chain([], _, _, _, !CaseLabelMap, !CI) :-
    unexpected(this_file,
        "generate_secondary_try_me_else_chain: empty switch").
generate_secondary_try_me_else_chain([Case | Cases], StagRval,
        MaybeFailLabel, Code, !CaseLabelMap, !CI) :-
    Case = Secondary - CaseLabel,
    (
        Cases = [_ | _],
        generate_secondary_try_me_else_chain_case(CaseLabel, StagRval,
            Secondary, ThisCode, !CaseLabelMap, !CI),
        generate_secondary_try_me_else_chain(Cases, StagRval,
            MaybeFailLabel, OtherCode, !CaseLabelMap, !CI),
        Code = tree(ThisCode, OtherCode)
    ;
        Cases = [],
        (
            MaybeFailLabel = yes(FailLabel),
            generate_secondary_try_me_else_chain_case(CaseLabel, StagRval,
                Secondary, ThisCode, !CaseLabelMap, !CI),
            FailCode = node([
                llds_instr(goto(code_label(FailLabel)),
                    "secondary tag does not match")
            ]),
            Code = tree(ThisCode, FailCode)
        ;
            MaybeFailLabel = no,
            generate_case_code_or_jump(CaseLabel, Code, !CaseLabelMap)
        )
    ).

:- pred generate_secondary_try_me_else_chain_case(label::in, rval::in, int::in,
    code_tree::out, case_label_map::in, case_label_map::out,
    code_info::in, code_info::out) is det.

generate_secondary_try_me_else_chain_case(CaseLabel, StagRval, Secondary,
        Code, !CaseLabelMap, !CI) :-
    generate_case_code_or_jump(CaseLabel, CaseCode, !CaseLabelMap),
    % XXX Optimize what we generate when CaseCode = goto(CaseLabel).
    get_next_label(ElseLabel, !CI),
    TestCode = node([
        llds_instr(
            if_val(binop(ne, StagRval, const(llconst_int(Secondary))),
                code_label(ElseLabel)),
            "test remote sec tag only")
    ]),
    ElseLabelCode = node([
        llds_instr(label(ElseLabel), "handle next secondary tag")
    ]),
    Code = tree_list([TestCode, CaseCode, ElseLabelCode]).

%-----------------------------------------------------------------------------%

    % Generate a switch on a secondary tag value using a try chain.
    %
:- pred generate_secondary_try_chain(stag_goal_list(label)::in, rval::in,
    maybe(label)::in, code_tree::in, code_tree::out,
    case_label_map::in, case_label_map::out) is det.

generate_secondary_try_chain([], _, _, _, _, !CaseLabelMap) :-
    unexpected(this_file, "generate_secondary_try_chain: empty switch").
generate_secondary_try_chain([Case | Cases], StagRval, MaybeFailLabel,
        PrevTestsCode0, Code, !CaseLabelMap) :-
    Case = Secondary - CaseLabel,
    (
        Cases = [_ | _],
        generate_secondary_try_chain_case(CaseLabel, StagRval, Secondary,
            PrevTestsCode0, PrevTestsCode1, !.CaseLabelMap),
        generate_secondary_try_chain(Cases, StagRval,
            MaybeFailLabel, PrevTestsCode1, Code, !CaseLabelMap)
    ;
        Cases = [],
        (
            MaybeFailLabel = yes(FailLabel),
            generate_secondary_try_chain_case(CaseLabel, StagRval, Secondary,
                PrevTestsCode0, PrevTestsCode1, !.CaseLabelMap),
            FailCode = node([
                llds_instr(goto(code_label(FailLabel)),
                    "secondary tag with no code to handle it")
            ]),
            Code = tree(PrevTestsCode1, FailCode)
        ;
            MaybeFailLabel = no,
            generate_case_code_or_jump(CaseLabel, ThisCode, !CaseLabelMap),
            Code = tree(PrevTestsCode0, ThisCode)
        )
    ).

:- pred generate_secondary_try_chain_case(label::in, rval::in, int::in,
    code_tree::in, code_tree::out, case_label_map::in) is det.

generate_secondary_try_chain_case(CaseLabel, StagRval, Secondary,
        PrevTestsCode0, PrevTestsCode, CaseLabelMap) :-
    map.lookup(CaseLabelMap, CaseLabel, CaseInfo0),
    CaseInfo0 = case_label_info(Comment, _CaseCode, _CaseGenerated),
    TestCode = node([
        llds_instr(
            if_val(binop(eq, StagRval, const(llconst_int(Secondary))),
                code_label(CaseLabel)),
            "test remote sec tag only for " ++ Comment)
    ]),
    PrevTestsCode = tree(PrevTestsCode0, TestCode).

%-----------------------------------------------------------------------------%

    % Generate the cases for a primary tag using a dense jump table
    % that has an entry for all possible secondary tag values.
    %
:- pred generate_secondary_jump_table(stag_goal_list(label)::in, int::in,
    int::in, maybe(label)::in, list(maybe(label))::out) is det.

generate_secondary_jump_table(CaseList, CurSecondary, MaxSecondary,
        MaybeFailLabel, Targets) :-
    ( CurSecondary > MaxSecondary ->
        expect(unify(CaseList, []), this_file,
            "caselist not empty when reaching limiting secondary tag"),
        Targets = []
    ;
        NextSecondary = CurSecondary + 1,
        ( CaseList = [CurSecondary - CaseLabel | CaseListTail] ->
            generate_secondary_jump_table(CaseListTail, NextSecondary,
                MaxSecondary, MaybeFailLabel, OtherTargets),
            Targets = [yes(CaseLabel) | OtherTargets]
        ;
            generate_secondary_jump_table(CaseList, NextSecondary,
                MaxSecondary, MaybeFailLabel, OtherTargets),
            Targets = [MaybeFailLabel | OtherTargets]
        )
    ).

%-----------------------------------------------------------------------------%

    % Generate the cases for a secondary tag using a binary search.
    % This invocation looks after secondary tag values in the range
    % MinPtag to MaxPtag (including both boundary values).
    %
:- pred generate_secondary_binary_search(stag_goal_list(label)::in,
    int::in, int::in, rval::in, maybe(label)::in, code_tree::out,
    case_label_map::in, case_label_map::out,
    code_info::in, code_info::out) is det.

generate_secondary_binary_search(StagGoals, MinStag, MaxStag, StagRval,
        MaybeFailLabel, Code, !CaseLabelMap, !CI) :-
    ( MinStag = MaxStag ->
        CurSec = MinStag,
        (
            StagGoals = [],
            % There is no code for this tag.
            (
                MaybeFailLabel = yes(FailLabel),
                string.int_to_string(CurSec, StagStr),
                Comment = "no code for ptag " ++ StagStr,
                Code = node([llds_instr(goto(code_label(FailLabel)), Comment)])
            ;
                MaybeFailLabel = no,
                Code = empty
            )
        ;
            StagGoals = [CurSecPrime - CaseLabel],
            expect(unify(CurSec, CurSecPrime), this_file,
                "generate_secondary_binary_search: cur_secondary mismatch"),
            generate_case_code_or_jump(CaseLabel, Code, !CaseLabelMap)
        ;
            StagGoals = [_, _ | _],
            unexpected(this_file,
                "generate_secondary_binary_search: " ++
                "goallist not singleton or empty when binary search ends")
        )
    ;
        LowRangeEnd = (MinStag + MaxStag) // 2,
        HighRangeStart = LowRangeEnd + 1,
        InLowGroup = (pred(StagGoal::in) is semidet :-
            StagGoal = Stag - _,
            Stag =< LowRangeEnd
        ),
        list.filter(InLowGroup, StagGoals, LowGoals, HighGoals),
        get_next_label(NewLabel, !CI),
        string.int_to_string(MinStag, LowStartStr),
        string.int_to_string(LowRangeEnd, LowEndStr),
        string.int_to_string(HighRangeStart, HighStartStr),
        string.int_to_string(MaxStag, HighEndStr),
        IfComment = "fallthrough for stags " ++
            LowStartStr ++ " to " ++ LowEndStr,
        LabelComment = "code for stags " ++
            HighStartStr ++ " to " ++ HighEndStr,
        LowRangeEndConst = const(llconst_int(LowRangeEnd)),
        TestRval = binop(int_gt, StagRval, LowRangeEndConst),
        IfCode = node([
            llds_instr(if_val(TestRval, code_label(NewLabel)), IfComment)
        ]),
        LabelCode = node([llds_instr(label(NewLabel), LabelComment)]),

        generate_secondary_binary_search(LowGoals, MinStag, LowRangeEnd,
            StagRval, MaybeFailLabel, LowRangeCode, !CaseLabelMap, !CI),
        generate_secondary_binary_search(HighGoals, HighRangeStart, MaxStag,
            StagRval, MaybeFailLabel, HighRangeCode, !CaseLabelMap, !CI),

        Code = tree_list([IfCode, LowRangeCode, LabelCode, HighRangeCode])
    ).

%-----------------------------------------------------------------------------%

:- func this_file = string.

this_file = "tag_switch.m".

%-----------------------------------------------------------------------------%
