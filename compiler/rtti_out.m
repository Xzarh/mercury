%-----------------------------------------------------------------------------%
% Copyright (C) 2000-2003 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% This module contains code to output the RTTI data structures
% defined in rtti.m as C code.
%
% This module is part of the LLDS back-end.  The decl_set data type
% that it uses, which is defined in llds_out.m, represents a set of LLDS
% declarations, and thus depends on the LLDS.  Also the code to output
% code_addrs depends on the LLDS.
%
% The MLDS back-end does not use this module; instead it converts the RTTI
% data structures to MLDS (and then to C or Java, etc.).
%
% Main author: zs.
%
%-----------------------------------------------------------------------------%

:- module ll_backend__rtti_out.

:- interface.

:- import_module backend_libs__rtti.
:- import_module ll_backend__llds_out.

:- import_module bool, io.

	% Output a C expression holding the address of the C name of
	% the specified rtti_data, preceded by the string in the first
	% argument (that string will usually be a C cast).
:- pred output_cast_addr_of_rtti_data(string::in, rtti_data::in,
	io__state::di, io__state::uo) is det.

	% Output a C expression holding the address of the C name of
	% the specified rtti_data.
:- pred output_addr_of_rtti_data(rtti_data::in, io__state::di, io__state::uo)
	is det.

	% Output a C declaration for the rtti_data.
:- pred output_rtti_data_decl(rtti_data::in, decl_set::in, decl_set::out,
	io__state::di, io__state::uo) is det.

	% Output a C definition for the rtti_data.
:- pred output_rtti_data_defn(rtti_data::in, decl_set::in, decl_set::out,
	io__state::di, io__state::uo) is det.

	% Output C code (e.g. a call to the MR_INIT_TYPE_CTOR_INFO() macro)
	% to initialize the rtti_data if necessary.
:- pred rtti_out__init_rtti_data_if_nec(rtti_data::in,
	io__state::di, io__state::uo) is det.

	% Output C code (e.g. a call to MR_register_type_ctor_info())
	% to register the rtti_data in the type tables, if it represents a data
	% structure that should be so registered. The bool should be the value
	% of the --split-c-files option; it governs whether the rtti_data is
	% declared in the generated code or not.
:- pred rtti_out__register_rtti_data_if_nec(rtti_data::in,
	bool::in, io__state::di, io__state::uo) is det.

	% Output the C name of the rtti_data specified by the given rtti_id.
:- pred output_rtti_id(rtti_id::in, io__state::di, io__state::uo) is det.

	% Output the C storage class, C type, and C name of the rtti_data
	% specified by the given rtti_id for use in a declaration or
	% definition. The bool should be `yes' iff it is for a definition.
:- pred output_rtti_id_storage_type_name(rtti_id::in, bool::in,
	io__state::di, io__state::uo) is det.

:- implementation.

:- import_module backend_libs__c_util.
:- import_module backend_libs__name_mangle.
:- import_module backend_libs__pseudo_type_info.
:- import_module backend_libs__type_ctor_info.
:- import_module hlds__hlds_data.
:- import_module hlds__error_util.
:- import_module libs__globals.
:- import_module libs__options.
:- import_module ll_backend__code_util.
:- import_module ll_backend__llds.
:- import_module parse_tree__prog_data.
:- import_module parse_tree__prog_out.

:- import_module int, string, list, assoc_list, map, require, std_util.

%-----------------------------------------------------------------------------%

output_rtti_data_defn(type_info(TypeInfo), !DeclSet, !IO) :-
	output_type_info_defn(TypeInfo, !DeclSet, !IO).
output_rtti_data_defn(pseudo_type_info(PseudoTypeInfo), !DeclSet, !IO) :-
	output_pseudo_type_info_defn(PseudoTypeInfo, !DeclSet, !IO).
output_rtti_data_defn(type_ctor_info(TypeCtorData), !DeclSet, !IO) :-
	output_type_ctor_data_defn(TypeCtorData, !DeclSet, !IO).
output_rtti_data_defn(base_typeclass_info(InstanceModuleName, ClassId,
		InstanceString, BaseTypeClassInfo), !DeclSet, !IO) :-
	output_base_typeclass_info_defn(InstanceModuleName, ClassId,
		InstanceString, BaseTypeClassInfo, !DeclSet, !IO).

%-----------------------------------------------------------------------------%

:- pred output_base_typeclass_info_defn(module_name::in, class_id::in,
	string::in, base_typeclass_info::in, decl_set::in, decl_set::out,
	io__state::di, io__state::uo) is det.

output_base_typeclass_info_defn(InstanceModuleName, ClassId, InstanceString,
		base_typeclass_info(N1, N2, N3, N4, N5, Methods),
		!DeclSet, !IO) :-
	CodeAddrs = list__map(make_code_addr, Methods),
	output_code_addrs_decls(CodeAddrs, "", "", 0, _, !DeclSet, !IO),
	io__write_string("\n", !IO),
	RttiId = tc_rtti_id(base_typeclass_info(InstanceModuleName,
		ClassId, InstanceString)),
	output_rtti_id_storage_type_name(RttiId, yes, !IO),
	% XXX It would be nice to avoid generating redundant declarations
	% of base_typeclass_infos, but currently we don't.
	io__write_string(" = {\n\t(MR_Code *) ", !IO),
	io__write_list([N1, N2, N3, N4, N5],
		",\n\t(MR_Code *) ", io__write_int, !IO),
	io__write_string(",\n\t", !IO),
	io__write_list(CodeAddrs, ",\n\t", output_static_code_addr, !IO),
	io__write_string("\n};\n", !IO).

%-----------------------------------------------------------------------------%

:- pred output_maybe_pseudo_type_info_or_self_defn(
	rtti_maybe_pseudo_type_info_or_self::in, decl_set::in, decl_set::out,
	io__state::di, io__state::uo) is det.

output_maybe_pseudo_type_info_or_self_defn(plain(TypeInfo),
		!DeclSet, !IO) :-
	output_type_info_defn(TypeInfo, !DeclSet, !IO).
output_maybe_pseudo_type_info_or_self_defn(pseudo(PseudoTypeInfo),
		!DeclSet, !IO) :-
	output_pseudo_type_info_defn(PseudoTypeInfo, !DeclSet, !IO).
output_maybe_pseudo_type_info_or_self_defn(self, !DeclSet, !IO).

:- pred output_maybe_pseudo_type_info_defn(rtti_maybe_pseudo_type_info::in,
	decl_set::in, decl_set::out, io__state::di, io__state::uo) is det.

output_maybe_pseudo_type_info_defn(plain(TypeInfo), !DeclSet, !IO) :-
	output_type_info_defn(TypeInfo, !DeclSet, !IO).
output_maybe_pseudo_type_info_defn(pseudo(PseudoTypeInfo), !DeclSet, !IO) :-
	output_pseudo_type_info_defn(PseudoTypeInfo, !DeclSet, !IO).

:- pred output_type_info_defn(rtti_type_info::in,
	decl_set::in, decl_set::out, io__state::di, io__state::uo) is det.

output_type_info_defn(TypeInfo, !DeclSet, !IO) :-
	(
		rtti_data_to_id(type_info(TypeInfo), RttiId),
		DataAddr = rtti_addr(RttiId),
		decl_set_is_member(data_addr(DataAddr), !.DeclSet)
	->
		true
	;
		do_output_type_info_defn(TypeInfo, !DeclSet, !IO)
	).

:- pred do_output_type_info_defn(rtti_type_info::in,
	decl_set::in, decl_set::out, io__state::di, io__state::uo) is det.

do_output_type_info_defn(plain_arity_zero_type_info(_), !DeclSet, !IO).
do_output_type_info_defn(TypeInfo, !DeclSet, !IO) :-
	TypeInfo = plain_type_info(RttiTypeCtor, Args),
	TypeCtorRttiData = type_info(plain_arity_zero_type_info(RttiTypeCtor)),
	ArgRttiDatas = list__map(type_info_to_rtti_data, Args),
	output_type_ctor_and_arg_defns_and_decls(TypeCtorRttiData,
		ArgRttiDatas, !DeclSet, !IO),
	output_generic_rtti_data_defn_start(
		ctor_rtti_id(RttiTypeCtor, type_info(TypeInfo)),
		!DeclSet, !IO),
	io__write_string(" = {\n\t&", !IO),
	output_ctor_rtti_id(RttiTypeCtor, type_ctor_info, !IO),
	io__write_string(",\n{", !IO),
	output_cast_addr_of_rtti_datas("(MR_TypeInfo) ", ArgRttiDatas, !IO),
	io__write_string("}};\n", !IO).
do_output_type_info_defn(TypeInfo, !DeclSet, !IO) :-
	TypeInfo = var_arity_type_info(RttiVarArityId, Args),
	RttiTypeCtor = var_arity_id_to_rtti_type_ctor(RttiVarArityId),
	TypeCtorRttiData = type_info(
		plain_arity_zero_type_info(RttiTypeCtor)),
	ArgRttiDatas = list__map(type_info_to_rtti_data, Args),
	output_type_ctor_and_arg_defns_and_decls(TypeCtorRttiData,
		ArgRttiDatas, !DeclSet, !IO),
	output_generic_rtti_data_defn_start(
		ctor_rtti_id(RttiTypeCtor, type_info(TypeInfo)),
		!DeclSet, !IO),
	io__write_string(" = {\n\t&", !IO),
	output_ctor_rtti_id(RttiTypeCtor, type_ctor_info, !IO),
	io__write_string(",\n\t", !IO),
	list__length(Args, Arity),
	io__write_int(Arity, !IO),
	io__write_string(",\n{", !IO),
	output_cast_addr_of_rtti_datas("(MR_TypeInfo) ", ArgRttiDatas, !IO),
	io__write_string("}};\n", !IO).

:- pred output_pseudo_type_info_defn(rtti_pseudo_type_info::in,
	decl_set::in, decl_set::out, io__state::di, io__state::uo) is det.

output_pseudo_type_info_defn(PseudoTypeInfo, !DeclSet, !IO) :-
	(
		PseudoTypeInfo = type_var(_)
	->
		true
	;
		rtti_data_to_id(pseudo_type_info(PseudoTypeInfo), RttiId),
		DataAddr = rtti_addr(RttiId),
		decl_set_is_member(data_addr(DataAddr), !.DeclSet)
	->
		true
	;
		do_output_pseudo_type_info_defn(PseudoTypeInfo,
			!DeclSet, !IO)
	).

:- pred do_output_pseudo_type_info_defn(rtti_pseudo_type_info::in,
	decl_set::in, decl_set::out, io__state::di, io__state::uo) is det.

do_output_pseudo_type_info_defn(plain_arity_zero_pseudo_type_info(_),
		!DeclSet, !IO).
do_output_pseudo_type_info_defn(PseudoTypeInfo, !DeclSet, !IO) :-
	PseudoTypeInfo = plain_pseudo_type_info(RttiTypeCtor, Args),
	TypeCtorRttiData = pseudo_type_info(
		plain_arity_zero_pseudo_type_info(RttiTypeCtor)),
	ArgRttiDatas = list__map(maybe_pseudo_type_info_to_rtti_data, Args),
	output_type_ctor_and_arg_defns_and_decls(TypeCtorRttiData,
		ArgRttiDatas, !DeclSet, !IO),
	output_generic_rtti_data_defn_start(
		ctor_rtti_id(RttiTypeCtor, pseudo_type_info(PseudoTypeInfo)),
		!DeclSet, !IO),
	io__write_string(" = {\n\t&", !IO),
	output_ctor_rtti_id(RttiTypeCtor, type_ctor_info, !IO),
	io__write_string(",\n{", !IO),
	output_cast_addr_of_rtti_datas("(MR_PseudoTypeInfo) ",
		ArgRttiDatas, !IO),
	io__write_string("}};\n", !IO).
do_output_pseudo_type_info_defn(PseudoTypeInfo, !DeclSet, !IO) :-
	PseudoTypeInfo = var_arity_pseudo_type_info(RttiVarArityId, Args),
	RttiTypeCtor = var_arity_id_to_rtti_type_ctor(RttiVarArityId),
	TypeCtorRttiData = pseudo_type_info(
		plain_arity_zero_pseudo_type_info(RttiTypeCtor)),
	ArgRttiDatas = list__map(maybe_pseudo_type_info_to_rtti_data, Args),
	output_type_ctor_and_arg_defns_and_decls(TypeCtorRttiData,
		ArgRttiDatas, !DeclSet, !IO),
	output_generic_rtti_data_defn_start(
		ctor_rtti_id(RttiTypeCtor, pseudo_type_info(PseudoTypeInfo)),
		!DeclSet, !IO),
	io__write_string(" = {\n\t&", !IO),
	output_ctor_rtti_id(RttiTypeCtor, type_ctor_info, !IO),
	io__write_string(",\n\t", !IO),
	list__length(Args, Arity),
	io__write_int(Arity, !IO),
	io__write_string(",\n{", !IO),
	output_cast_addr_of_rtti_datas("(MR_PseudoTypeInfo) ",
		ArgRttiDatas, !IO),
	io__write_string("}};\n", !IO).
do_output_pseudo_type_info_defn(type_var(_), !DeclSet, !IO).

:- pred output_type_ctor_and_arg_defns_and_decls(rtti_data::in,
	list(rtti_data)::in, decl_set::in, decl_set::out,
	io__state::di, io__state::uo) is det.

output_type_ctor_and_arg_defns_and_decls(TypeCtorRttiData, ArgRttiDatas,
		!DeclSet, !IO) :-
	output_rtti_data_decls(TypeCtorRttiData, "", "", 0, _,
		!DeclSet, !IO),
	% We must output the definitions of the rtti_datas of the argument
	% typeinfos and/or pseudo-typeinfos, because they may contain other
	% typeinfos and/or pseudo-typeinfos nested within them. However,
	% zero arity typeinfos and pseudo-typeinfos have empty definitions,
	% yet the type_ctor_info they refer to still must be declared.
	% This is why both calls below are needed.
	list__foldl2(output_rtti_data_defn, ArgRttiDatas, !DeclSet, !IO),
	output_rtti_datas_decls(ArgRttiDatas, "", "", 0, _,
		!DeclSet, !IO).

%-----------------------------------------------------------------------------%

:- pred output_type_ctor_data_defn(type_ctor_data::in,
	decl_set::in, decl_set::out, io__state::di, io__state::uo) is det.

output_type_ctor_data_defn(TypeCtorData, !DeclSet, !IO) :-
	RttiTypeCtor = tcd_get_rtti_type_ctor(TypeCtorData),
	TypeCtorData = type_ctor_data(Version, Module, TypeName, TypeArity,
		UnifyUniv, CompareUniv, Flags, TypeCtorDetails),
	output_type_ctor_details_defn(RttiTypeCtor, TypeCtorDetails,
		MaybeFunctorsName, MaybeLayoutName, !DeclSet, !IO),
	det_univ_to_type(UnifyUniv, UnifyProcLabel),
	UnifyCodeAddr   = make_code_addr(UnifyProcLabel),
	det_univ_to_type(CompareUniv, CompareProcLabel),
	CompareCodeAddr = make_code_addr(CompareProcLabel),
	CodeAddrs = [UnifyCodeAddr, CompareCodeAddr],
	output_code_addrs_decls(CodeAddrs, "", "", 0, _, !DeclSet, !IO),
	output_generic_rtti_data_defn_start(
		ctor_rtti_id(RttiTypeCtor, type_ctor_info),
		!DeclSet, !IO),
	io__write_string(" = {\n\t", !IO),
	io__write_int(TypeArity, !IO),
	io__write_string(",\n\t", !IO),
	io__write_int(Version, !IO),
	io__write_string(",\n\t", !IO),
	io__write_int(type_ctor_details_num_ptags(TypeCtorDetails), !IO),
	io__write_string(",\n\t", !IO),
	rtti__type_ctor_rep_to_string(TypeCtorData, CtorRepStr),
	io__write_string(CtorRepStr, !IO),
	io__write_string(",\n\t", !IO),
	output_static_code_addr(UnifyCodeAddr, !IO),
	io__write_string(",\n\t", !IO),
	output_static_code_addr(CompareCodeAddr, !IO),
	io__write_string(",\n\t""", !IO),
	prog_out__sym_name_to_string(Module, ModuleName),
	c_util__output_quoted_string(ModuleName, !IO),
	io__write_string(""",\n\t""", !IO),
	c_util__output_quoted_string(TypeName, !IO),
	io__write_string(""",\n\t", !IO),
	(
		MaybeFunctorsName = yes(FunctorsName),
		io__write_string("{ (void *) &", !IO),
		output_ctor_rtti_id(RttiTypeCtor, FunctorsName, !IO),
		io__write_string(" }", !IO)
	;
		MaybeFunctorsName = no,
		io__write_string("{ 0 }", !IO)
	),
	io__write_string(",\n\t", !IO),
	(
		MaybeLayoutName = yes(LayoutName),
		io__write_string("{ (void *) &", !IO),
		output_ctor_rtti_id(RttiTypeCtor, LayoutName, !IO),
		io__write_string(" }", !IO)
	;
		MaybeLayoutName = no,
		io__write_string("{ 0 }", !IO)
	),
	io__write_string(",\n\t", !IO),
	io__write_int(type_ctor_details_num_functors(TypeCtorDetails), !IO),
	io__write_string(",\n\t", !IO),
	io__write_int(encode_type_ctor_flags(Flags), !IO),
% This code is commented out while the corresponding fields of the
% MR_TypeCtorInfo_Struct type are commented out.
%
%	io__write_string(",\n\t"),
%	(
%		{ MaybeHashCons = yes(HashConsDataAddr) },
%		io__write_string("&"),
%		output_ctor_rtti_id(RttiTypeCtor, HashConsDataAddr)
%	;
%		{ MaybeHashCons = no },
%		io__write_string("NULL")
%	),
%	io__write_string(",\n\t"),
%	output_maybe_static_code_addr(Prettyprinter),
	io__write_string("\n};\n", !IO).

:- pred output_type_ctor_details_defn(rtti_type_ctor::in,
	type_ctor_details::in,
	maybe(ctor_rtti_name)::out, maybe(ctor_rtti_name)::out,
	decl_set::in, decl_set::out, io__state::di, io__state::uo) is det.

output_type_ctor_details_defn(RttiTypeCtor, TypeCtorDetails,
		MaybeFunctorsName, MaybeLayoutName, !DeclSet, !IO) :-
	(
		TypeCtorDetails = enum(_, EnumFunctors, EnumByRep,
			EnumByName),
		list__foldl2(output_enum_functor_defn(RttiTypeCtor),
			EnumFunctors, !DeclSet, !IO),
		output_enum_value_ordered_table(RttiTypeCtor, EnumByRep,
			!DeclSet, !IO),
		output_enum_name_ordered_table(RttiTypeCtor, EnumByName,
			!DeclSet, !IO),
		MaybeLayoutName = yes(enum_value_ordered_table),
		MaybeFunctorsName = yes(enum_name_ordered_table)
	;
		TypeCtorDetails = du(_, DuFunctors, DuByRep, DuByName),
		list__foldl2(output_du_functor_defn(RttiTypeCtor), DuFunctors,
			!DeclSet, !IO),
		output_du_ptag_ordered_table(RttiTypeCtor, DuByRep,
			!DeclSet, !IO),
		output_du_name_ordered_table(RttiTypeCtor, DuByName,
			!DeclSet, !IO),
		MaybeLayoutName = yes(du_ptag_ordered_table),
		MaybeFunctorsName = yes(du_name_ordered_table)
	;
		TypeCtorDetails = reserved(_, MaybeResFunctors, ResFunctors,
			DuByRep, MaybeResByName),
		list__foldl2(output_maybe_res_functor_defn(RttiTypeCtor),
			MaybeResFunctors, !DeclSet, !IO),
		output_res_value_ordered_table(RttiTypeCtor, ResFunctors,
			DuByRep, !DeclSet, !IO),
		output_res_name_ordered_table(RttiTypeCtor, MaybeResByName,
			!DeclSet, !IO),
		MaybeLayoutName = yes(res_value_ordered_table),
		MaybeFunctorsName = yes(res_name_ordered_table)
	;
		TypeCtorDetails = notag(_, NotagFunctor),
		output_notag_functor_defn(RttiTypeCtor, NotagFunctor,
			!DeclSet, !IO),
		MaybeLayoutName = yes(notag_functor_desc),
		MaybeFunctorsName = yes(notag_functor_desc)
	;
		TypeCtorDetails = eqv(EqvType),
		output_maybe_pseudo_type_info_defn(EqvType,
			!DeclSet, !IO),
		TypeData = maybe_pseudo_type_info_to_rtti_data(EqvType),
		output_rtti_data_decls(TypeData, "", "", 0, _,
			!DeclSet, !IO),
		(
			EqvType = plain(TypeInfo),
			LayoutName = type_info(TypeInfo)
		;
			EqvType = pseudo(PseudoTypeInfo),
			LayoutName = pseudo_type_info(PseudoTypeInfo)
		),
		MaybeLayoutName = yes(LayoutName),
		MaybeFunctorsName = no
	;
		TypeCtorDetails = builtin(_),
		error("output_type_ctor_details_defn: builtin")
	;
		TypeCtorDetails = impl_artifact(_),
		error("output_type_ctor_details_defn: impl_artifact")
	;
		TypeCtorDetails = foreign,
		MaybeLayoutName = no,
		MaybeFunctorsName = no
	).

%-----------------------------------------------------------------------------%

:- pred output_enum_functor_defn(rtti_type_ctor::in, enum_functor::in,
	decl_set::in, decl_set::out, io__state::di, io__state::uo) is det.

output_enum_functor_defn(RttiTypeCtor, EnumFunctor, !DeclSet, !IO) :-
	EnumFunctor = enum_functor(FunctorName, Ordinal),
	output_generic_rtti_data_defn_start(
		ctor_rtti_id(RttiTypeCtor, enum_functor_desc(Ordinal)),
		!DeclSet, !IO),
	io__write_string(" = {\n\t""", !IO),
	c_util__output_quoted_string(FunctorName, !IO),
	io__write_string(""",\n\t", !IO),
	io__write_int(Ordinal, !IO),
	io__write_string("\n};\n", !IO).

:- pred output_notag_functor_defn(rtti_type_ctor::in, notag_functor::in,
	decl_set::in, decl_set::out, io__state::di, io__state::uo) is det.

output_notag_functor_defn(RttiTypeCtor, NotagFunctor, !DeclSet, !IO) :-
	NotagFunctor = notag_functor(FunctorName, ArgType, MaybeArgName),
	output_maybe_pseudo_type_info_defn(ArgType, !DeclSet, !IO),
	ArgTypeData = maybe_pseudo_type_info_to_rtti_data(ArgType),
	output_rtti_data_decls(ArgTypeData, "", "", 0, _,
		!DeclSet, !IO),
	output_generic_rtti_data_defn_start(
		ctor_rtti_id(RttiTypeCtor, notag_functor_desc),
		!DeclSet, !IO),
	io__write_string(" = {\n\t""", !IO),
	c_util__output_quoted_string(FunctorName, !IO),
	io__write_string(""",\n\t", !IO),
	(
		ArgType = plain(ArgTypeInfo),
		output_cast_addr_of_rtti_data("(MR_PseudoTypeInfo) ",
			type_info(ArgTypeInfo), !IO)
	;
		ArgType = pseudo(ArgPseudoTypeInfo),
		% We need to cast the argument to MR_PseudoTypeInfo in case
		% it turns out to be a small integer, not a pointer.
		output_cast_addr_of_rtti_data("(MR_PseudoTypeInfo) ",
			pseudo_type_info(ArgPseudoTypeInfo), !IO)
	),
	io__write_string(",\n\t", !IO),
	(
		MaybeArgName = yes(ArgName),
		io__write_string("""", !IO),
		io__write_string(ArgName, !IO),
		io__write_string("""", !IO)
	;
		MaybeArgName = no,
		io__write_string("NULL", !IO)
	),
	io__write_string("\n};\n", !IO).

:- pred output_du_functor_defn(rtti_type_ctor::in, du_functor::in,
	decl_set::in, decl_set::out, io__state::di, io__state::uo) is det.

output_du_functor_defn(RttiTypeCtor, DuFunctor, !DeclSet, !IO) :-
	DuFunctor = du_functor(FunctorName, OrigArity, Ordinal, Rep,
		ArgInfos, MaybeExistInfo),
	ArgTypes = list__map(du_arg_info_type, ArgInfos),
	MaybeArgNames = list__map(du_arg_info_name, ArgInfos),
	ArgNames = list__filter_map(project_yes, MaybeArgNames),
	(
		ArgInfos = [_ | _],
		output_du_arg_types(RttiTypeCtor, Ordinal, ArgTypes,
			!DeclSet, !IO)
	;
		ArgInfos = []
	),
	(
		ArgNames = [_ | _],
		output_du_arg_names(RttiTypeCtor, Ordinal, MaybeArgNames,
			!DeclSet, !IO)
	;
		ArgNames = []
	),
	(
		MaybeExistInfo = yes(ExistInfo),
		output_exist_info(RttiTypeCtor, Ordinal, ExistInfo,
			!DeclSet, !IO)
	;
		MaybeExistInfo = no
	),
	output_generic_rtti_data_defn_start(
		ctor_rtti_id(RttiTypeCtor, du_functor_desc(Ordinal)),
		!DeclSet, !IO),
	io__write_string(" = {\n\t""", !IO),
	c_util__output_quoted_string(FunctorName, !IO),
	io__write_string(""",\n\t", !IO),
	io__write_int(OrigArity, !IO),
	io__write_string(",\n\t", !IO),
	ContainsVarBitVector = compute_contains_var_bit_vector(ArgTypes),
	io__write_int(ContainsVarBitVector, !IO),
	io__write_string(",\n\t", !IO),
	(
		Rep = du_ll_rep(Ptag, SectagAndLocn)
	;
		Rep = du_hl_rep(_),
		error("output_du_functor_defn: du_hl_rep")
	),
	(
		SectagAndLocn = sectag_none,
		Locn = "MR_SECTAG_NONE",
		Stag = -1
	;
		SectagAndLocn = sectag_local(Stag),
		Locn = "MR_SECTAG_LOCAL"
	;
		SectagAndLocn = sectag_remote(Stag),
		Locn = "MR_SECTAG_REMOTE"
	),
	io__write_string(Locn, !IO),
	io__write_string(",\n\t", !IO),
	io__write_int(Ptag, !IO),
	io__write_string(",\n\t", !IO),
	io__write_int(Stag, !IO),
	io__write_string(",\n\t", !IO),
	io__write_int(Ordinal, !IO),
	io__write_string(",\n\t", !IO),
	io__write_string("(MR_PseudoTypeInfo *) ", !IO), % cast away const
	(
		ArgInfos = [_ | _],
		output_addr_of_ctor_rtti_id(RttiTypeCtor, field_types(Ordinal),
			!IO)
	;
		ArgInfos = [],
		io__write_string("NULL", !IO)
	),
	io__write_string(",\n\t", !IO),
	(
		ArgNames = [_ | _],
		output_addr_of_ctor_rtti_id(RttiTypeCtor, field_names(Ordinal),
			!IO)
	;
		ArgNames = [],
		io__write_string("NULL", !IO)
	),
	io__write_string(",\n\t", !IO),
	(
		MaybeExistInfo = yes(_),
		output_addr_of_ctor_rtti_id(RttiTypeCtor, exist_info(Ordinal),
			!IO)
	;
		MaybeExistInfo = no,
		io__write_string("NULL", !IO)
	),
	io__write_string("\n};\n", !IO).

:- pred output_res_functor_defn(rtti_type_ctor::in, reserved_functor::in,
	decl_set::in, decl_set::out, io__state::di, io__state::uo) is det.

output_res_functor_defn(RttiTypeCtor, ResFunctor, !DeclSet, !IO) :-
	ResFunctor = reserved_functor(FunctorName, Ordinal, Rep),
	output_generic_rtti_data_defn_start(
		ctor_rtti_id(RttiTypeCtor, res_functor_desc(Ordinal)),
		!DeclSet, !IO),
	io__write_string(" = {\n\t""", !IO),
	c_util__output_quoted_string(FunctorName, !IO),
	io__write_string(""",\n\t", !IO),
	io__write_int(Ordinal, !IO),
	io__write_string(",\n\t", !IO),
	io__write_string("(void *) ", !IO),
	(
		Rep = null_pointer,
		io__write_string("NULL", !IO)
	;
		Rep = small_pointer(SmallPtr),
		io__write_int(SmallPtr, !IO)
	;
		Rep = reserved_object(_, _, _),
		error("output_res_functor_defn: reserved object")
	),
	io__write_string("\n};\n", !IO).

:- pred output_maybe_res_functor_defn(rtti_type_ctor::in,
	maybe_reserved_functor::in, decl_set::in, decl_set::out,
	io__state::di, io__state::uo) is det.

output_maybe_res_functor_defn(RttiTypeCtor, MaybeResFunctor, !DeclSet, !IO) :-
	(
		MaybeResFunctor = res_func(ResFunctor),
		output_res_functor_defn(RttiTypeCtor, ResFunctor,
			!DeclSet, !IO)
	;
		MaybeResFunctor = du_func(DuFunctor),
		output_du_functor_defn(RttiTypeCtor, DuFunctor,
			!DeclSet, !IO)
	).

%-----------------------------------------------------------------------------%

:- pred output_exist_locns_array(rtti_type_ctor::in, int::in,
	list(exist_typeinfo_locn)::in,
	decl_set::in, decl_set::out, io__state::di, io__state::uo) is det.

output_exist_locns_array(RttiTypeCtor, Ordinal, Locns, !DeclSet, !IO) :-
	output_generic_rtti_data_defn_start(
		ctor_rtti_id(RttiTypeCtor, exist_locns(Ordinal)),
		!DeclSet, !IO),
	(
			% ANSI/ISO C doesn't allow empty arrays, so
			% place a dummy value in the array if necessary.
		Locns = []
	->
		io__write_string("= { {0, 0} };\n", !IO)
	;
		io__write_string(" = {\n", !IO),
		output_exist_locns(Locns, !IO),
		io__write_string("};\n", !IO)
	).

:- pred output_exist_info(rtti_type_ctor::in, int::in, exist_info::in,
	decl_set::in, decl_set::out, io__state::di, io__state::uo) is det.

output_exist_info(RttiTypeCtor, Ordinal, ExistInfo, !DeclSet, !IO) :-
	ExistInfo = exist_info(Plain, InTci, Tci, Locns),
	output_exist_locns_array(RttiTypeCtor, Ordinal, Locns,
		!DeclSet, !IO),
	output_generic_rtti_data_defn_start(
		ctor_rtti_id(RttiTypeCtor, exist_info(Ordinal)),
		!DeclSet, !IO),
	io__write_string(" = {\n\t", !IO),
	io__write_int(Plain, !IO),
	io__write_string(",\n\t", !IO),
	io__write_int(InTci, !IO),
	io__write_string(",\n\t", !IO),
	io__write_int(Tci, !IO),
	io__write_string(",\n\t", !IO),
	output_ctor_rtti_id(RttiTypeCtor, exist_locns(Ordinal), !IO),
	io__write_string("\n};\n", !IO).

:- pred output_du_arg_types(rtti_type_ctor::in, int::in,
	list(rtti_maybe_pseudo_type_info_or_self)::in,
	decl_set::in, decl_set::out, io__state::di, io__state::uo) is det.

output_du_arg_types(RttiTypeCtor, Ordinal, ArgTypes, !DeclSet, !IO) :-
	list__foldl2(output_maybe_pseudo_type_info_or_self_defn, ArgTypes,
		!DeclSet, !IO),
	ArgTypeDatas = list__map(maybe_pseudo_type_info_or_self_to_rtti_data,
		ArgTypes),
	output_rtti_datas_decls(ArgTypeDatas, "", "", 0, _,
		!DeclSet, !IO),
	output_generic_rtti_data_defn_start(
		ctor_rtti_id(RttiTypeCtor, field_types(Ordinal)),
		!DeclSet, !IO),
	io__write_string(" = {\n", !IO),
	require(list__is_not_empty(ArgTypes),
		"output_du_arg_types: empty list"),
	output_cast_addr_of_rtti_datas("(MR_PseudoTypeInfo) ",
		ArgTypeDatas, !IO),
	io__write_string("};\n", !IO).

:- pred output_du_arg_names(rtti_type_ctor::in, int::in,
	list(maybe(string))::in, decl_set::in, decl_set::out,
	io__state::di, io__state::uo) is det.

output_du_arg_names(RttiTypeCtor, Ordinal, MaybeNames, !DeclSet, !IO) :-
	output_generic_rtti_data_defn_start(
		ctor_rtti_id(RttiTypeCtor, field_names(Ordinal)),
		!DeclSet, !IO),
	io__write_string(" = {\n", !IO),
	require(list__is_not_empty(MaybeNames),
		"output_du_arg_names: empty list"),
	output_maybe_quoted_strings(MaybeNames, !IO),
	io__write_string("};\n", !IO).

%-----------------------------------------------------------------------------%

:- pred output_enum_value_ordered_table(rtti_type_ctor::in,
	map(int, enum_functor)::in, decl_set::in, decl_set::out,
	io__state::di, io__state::uo) is det.

output_enum_value_ordered_table(RttiTypeCtor, FunctorMap, !DeclSet, !IO) :-
	Functors = map__values(FunctorMap),
	FunctorRttiNames = list__map(enum_functor_rtti_name, Functors),
	output_generic_rtti_data_defn_start(
		ctor_rtti_id(RttiTypeCtor, enum_value_ordered_table),
		!DeclSet, !IO),
	io__write_string(" = {\n", !IO),
	output_addr_of_ctor_rtti_names(RttiTypeCtor, FunctorRttiNames, !IO),
	io__write_string("};\n", !IO).

:- pred output_enum_name_ordered_table(rtti_type_ctor::in,
	map(string, enum_functor)::in, decl_set::in, decl_set::out,
	io__state::di, io__state::uo) is det.

output_enum_name_ordered_table(RttiTypeCtor, FunctorMap, !DeclSet, !IO) :-
	Functors = map__values(FunctorMap),
	FunctorRttiNames = list__map(enum_functor_rtti_name, Functors),
	output_generic_rtti_data_defn_start(
		ctor_rtti_id(RttiTypeCtor, enum_name_ordered_table),
		!DeclSet, !IO),
	io__write_string(" = {\n", !IO),
	output_addr_of_ctor_rtti_names(RttiTypeCtor, FunctorRttiNames, !IO),
	io__write_string("};\n", !IO).

:- pred output_du_name_ordered_table(rtti_type_ctor::in,
	map(string, map(int, du_functor))::in, decl_set::in, decl_set::out,
	io__state::di, io__state::uo) is det.

output_du_name_ordered_table(RttiTypeCtor, NameArityMap, !DeclSet, !IO) :-
	map__values(NameArityMap, ArityMaps),
	list__map(map__values, ArityMaps, FunctorLists),
	list__condense(FunctorLists, Functors),
	FunctorRttiNames = list__map(du_functor_rtti_name, Functors),
	output_generic_rtti_data_defn_start(
		ctor_rtti_id(RttiTypeCtor, du_name_ordered_table),
		!DeclSet, !IO),
	io__write_string(" = {\n", !IO),
	output_addr_of_ctor_rtti_names(RttiTypeCtor, FunctorRttiNames, !IO),
	io__write_string("};\n", !IO).

:- pred output_du_stag_ordered_table(rtti_type_ctor::in,
	pair(int, sectag_table)::in, decl_set::in, decl_set::out,
	io__state::di, io__state::uo) is det.

output_du_stag_ordered_table(RttiTypeCtor, Ptag - SectagTable, !DeclSet,
		!IO) :-
	SectagTable = sectag_table(_SectagLocn, _NumSharers, SectagMap),
	map__values(SectagMap, SectagFunctors),
	FunctorNames = list__map(du_functor_rtti_name, SectagFunctors),
	output_generic_rtti_data_defn_start(
		ctor_rtti_id(RttiTypeCtor, du_stag_ordered_table(Ptag)),
		!DeclSet, !IO),
	io__write_string(" = {\n", !IO),
	output_addr_of_ctor_rtti_names(RttiTypeCtor, FunctorNames, !IO),
	io__write_string("\n};\n", !IO).

:- pred output_du_ptag_ordered_table(rtti_type_ctor::in,
	map(int, sectag_table)::in, decl_set::in, decl_set::out,
	io__state::di, io__state::uo) is det.

output_du_ptag_ordered_table(RttiTypeCtor, PtagMap, !DeclSet, !IO) :-
	map__to_assoc_list(PtagMap, PtagList),
	list__foldl2(output_du_stag_ordered_table(RttiTypeCtor), PtagList,
		!DeclSet, !IO),
	output_generic_rtti_data_defn_start(
		ctor_rtti_id(RttiTypeCtor, du_ptag_ordered_table),
		!DeclSet, !IO),
	io__write_string(" = {\n", !IO),
	( PtagList = [1 - _ | _] ->
			% Output a dummy ptag definition for the
			% reserved tag first.
		output_dummy_ptag_layout_defn(!IO),
		FirstPtag = 1
	; PtagList = [0 - _ | _] ->
		FirstPtag = 0
	;
		error("output_dummy_ptag_layout_defn: bad ptag list")
	),
	output_du_ptag_ordered_table_body(RttiTypeCtor, PtagList, FirstPtag,
		!IO),
	io__write_string("\n};\n", !IO).

:- pred output_du_ptag_ordered_table_body(rtti_type_ctor::in,
	assoc_list(int, sectag_table)::in, int::in,
	io__state::di, io__state::uo) is det.

output_du_ptag_ordered_table_body(_RttiTypeCtor, [], _CurPtag, !IO).
output_du_ptag_ordered_table_body(RttiTypeCtor,
		[Ptag - SectagTable | PtagTail], CurPtag, !IO) :-
	require(unify(Ptag, CurPtag),
		"output_du_ptag_ordered_table_body: ptag mismatch"),
	SectagTable = sectag_table(SectagLocn, NumSharers, _SectagMap),
	io__write_string("\t{ ", !IO),
	io__write_int(NumSharers, !IO),
	io__write_string(", ", !IO),
	rtti__sectag_locn_to_string(SectagLocn, LocnStr),
	io__write_string(LocnStr, !IO),
	io__write_string(",\n\t", !IO),
	output_ctor_rtti_id(RttiTypeCtor, du_stag_ordered_table(Ptag), !IO),
	( PtagTail = [] ->
		io__write_string(" }\n", !IO)
	;
		io__write_string(" },\n", !IO),
		output_du_ptag_ordered_table_body(RttiTypeCtor, PtagTail,
			CurPtag + 1, !IO)
	).

	% Output a `dummy' ptag layout, for use by tags that aren't *real*
	% tags, such as the tag reserved when --reserve-tag is on.
	%
	% XXX Note that if one of these dummy ptag definitions is actually
	% accessed by the Mercury runtime, the result will be undefined.
	% This should be fixed by adding a MR_SECTAG_DUMMY and handling it
	% gracefully.
:- pred output_dummy_ptag_layout_defn(io__state::di, io__state::uo) is det.

output_dummy_ptag_layout_defn(!IO) :-
	io__write_string("\t{ 0, MR_SECTAG_VARIABLE, NULL },\n", !IO).

:- pred output_res_addr_functors(rtti_type_ctor::in,
	reserved_functor::in, io__state::di, io__state::uo) is det.

output_res_addr_functors(RttiTypeCtor, ResFunctor, !IO) :-
	output_ctor_rtti_id(RttiTypeCtor, res_functor_rtti_name(ResFunctor),
		!IO),
	io__write_string(",\n", !IO).

:- pred output_res_value_ordered_table(rtti_type_ctor::in,
	list(reserved_functor)::in, map(int, sectag_table)::in,
	decl_set::in, decl_set::out, io__state::di, io__state::uo) is det.

output_res_value_ordered_table(RttiTypeCtor, ResFunctors, DuPtagTable,
		!DeclSet, !IO) :-
	ResFunctorReps = list__map(res_addr_rep, ResFunctors),
	list__filter(res_addr_is_numeric, ResFunctorReps,
		NumericResFunctorReps, SymbolicResFunctorReps),
	list__length(NumericResFunctorReps, NumNumericResFunctorReps),
	list__length(SymbolicResFunctorReps, NumSymbolicResFunctorReps),
	require(unify(NumSymbolicResFunctorReps, 0),
		"output_res_value_ordered_table: symbolic functors"),

	output_generic_rtti_data_defn_start(
		ctor_rtti_id(RttiTypeCtor, res_addr_functors), !DeclSet, !IO),
	io__write_string(" = {\n", !IO),
	list__foldl(output_res_addr_functors(RttiTypeCtor), ResFunctors, !IO),
	io__write_string("};\n", !IO),

	output_du_ptag_ordered_table(RttiTypeCtor, DuPtagTable, !DeclSet, !IO),

	output_generic_rtti_data_defn_start(
		ctor_rtti_id(RttiTypeCtor, res_value_ordered_table),
		!DeclSet, !IO),
	io__write_string(" = {\n\t""", !IO),
	io__write_int(NumNumericResFunctorReps, !IO),
	io__write_string(",\n\t", !IO),
	io__write_int(NumSymbolicResFunctorReps, !IO),
	io__write_string(",\n\t", !IO),
	io__write_string("NULL", !IO),
	io__write_string(",\n\t", !IO),
	output_ctor_rtti_id(RttiTypeCtor, res_addr_functors, !IO),
	io__write_string(",\n\t", !IO),
	output_ctor_rtti_id(RttiTypeCtor, du_ptag_ordered_table, !IO),
	io__write_string("\n};\n", !IO).

:- pred output_res_name_ordered_table(rtti_type_ctor::in,
	map(string, map(int, maybe_reserved_functor))::in,
	decl_set::in, decl_set::out, io__state::di, io__state::uo) is det.

output_res_name_ordered_table(RttiTypeCtor, NameArityMap, !DeclSet, !IO) :-
	map__values(NameArityMap, ArityMaps),
	list__map(map__values, ArityMaps, FunctorLists),
	list__condense(FunctorLists, Functors),
	output_generic_rtti_data_defn_start(
		ctor_rtti_id(RttiTypeCtor, res_name_ordered_table),
		!DeclSet, !IO),
	io__write_string(" = {\n\t""", !IO),
	list__foldl(output_res_name_ordered_table_element(RttiTypeCtor),
		Functors, !IO),
	io__write_string("\n};\n", !IO).

:- pred output_res_name_ordered_table_element(rtti_type_ctor::in,
	maybe_reserved_functor::in, io__state::di, io__state::uo) is det.

output_res_name_ordered_table_element(RttiTypeCtor, MaybeResFunctor, !IO) :-
	io__write_string("\t{ """, !IO),
	(
		MaybeResFunctor = res_func(ResFunctor),
		Name = ResFunctor ^ res_name,
		io__write_string(Name, !IO),
		io__write_string(""", ", !IO),
		io__write_string("0, ", !IO),
		io__write_string("MR_TRUE, ", !IO)
	;
		MaybeResFunctor = du_func(DuFunctor),
		Name = DuFunctor ^ du_name,
		Arity = DuFunctor ^ du_orig_arity,
		io__write_string(Name, !IO),
		io__write_string(""", ", !IO),
		io__write_int(Arity, !IO),
		io__write_string(", ", !IO),
		io__write_string("MR_FALSE, ", !IO)
	),
	RttiName = maybe_res_functor_rtti_name(MaybeResFunctor),
	output_ctor_rtti_id(RttiTypeCtor, RttiName, !IO),
	io__write_string(" },\n", !IO).

%-----------------------------------------------------------------------------%

:- func make_code_addr(rtti_proc_label) = code_addr.

make_code_addr(ProcLabel) = CodeAddr :-
	code_util__make_entry_label_from_rtti(ProcLabel, no, CodeAddr).

:- pred output_reserved_address(reserved_address::in,
	io__state::di, io__state::uo) is det.

output_reserved_address(null_pointer, !IO) :-
	io__write_string("NULL", !IO).
output_reserved_address(small_pointer(Val), !IO) :-
	io__write_string("(const void *) ", !IO),
	io__write_int(Val, !IO).
output_reserved_address(reserved_object(_, _, _), !IO) :-
	% These should only be used for the MLDS back-end
	unexpected(this_file, "reserved_object").

%-----------------------------------------------------------------------------%

output_rtti_data_decl(RttiData, !DeclSet, !IO) :-
	( RttiData = pseudo_type_info(type_var(_)) ->
		% These just get represented as integers,
		% so we don't need to declare them.
		% Also rtti_data_to_name/3 does not handle this case.
		true
	;
		rtti_data_to_id(RttiData, RttiId),
		output_generic_rtti_data_decl(RttiId, !DeclSet, !IO)
	).

%-----------------------------------------------------------------------------%

:- pred output_generic_rtti_data_decl(rtti_id::in, decl_set::in, decl_set::out,
	io__state::di, io__state::uo) is det.

output_generic_rtti_data_decl(RttiId, !DeclSet, !IO) :-
	output_rtti_id_storage_type_name(RttiId, no, !IO),
	io__write_string(";\n", !IO),
	DataAddr = rtti_addr(RttiId),
	decl_set_insert(data_addr(DataAddr), !DeclSet).

:- pred output_generic_rtti_data_defn_start(rtti_id::in,
	decl_set::in, decl_set::out, io__state::di, io__state::uo) is det.

output_generic_rtti_data_defn_start(RttiId, !DeclSet, !IO) :-
	io__write_string("\n", !IO),
	output_rtti_id_storage_type_name(RttiId, yes, !IO),
	DataAddr = rtti_addr(RttiId),
	decl_set_insert(data_addr(DataAddr), !DeclSet).

output_rtti_id_storage_type_name(RttiId, BeingDefined, !IO) :-
	output_rtti_type_decl(RttiId, !IO),
	rtti_id_linkage(RttiId, Linkage),
	globals__io_get_globals(Globals, !IO),
	LinkageStr = c_data_linkage_string(Globals, Linkage, yes,
		BeingDefined),
	io__write_string(LinkageStr, !IO),

	InclCodeAddr = rtti_id_would_include_code_addr(RttiId),
	c_data_const_string(Globals, InclCodeAddr, ConstStr),
	io__write_string(ConstStr, !IO),

	rtti_id_c_type(RttiId, CType, IsArray),
	c_util__output_quoted_string(CType, !IO),
	io__write_string(" ", !IO),
	output_rtti_id(RttiId, !IO),
	(
		IsArray = yes,
		io__write_string("[]", !IO)
	;
		IsArray = no
	).

	% Each type_info and pseudo_type_info may have a different C type,
	% depending on what kind of type_info or pseudo_type_info it is,
	% and also on its arity. We need to declare that C type here.

:- pred output_rtti_type_decl(rtti_id::in, io__state::di, io__state::uo)
	is det.

output_rtti_type_decl(RttiId, !IO) :-
	(
		rtti_type_template_arity(RttiId, Arity),
		Arity > max_always_declared_arity
	->
		Template =
"#ifndef MR_TYPE_INFO_LIKE_STRUCTS_FOR_ARITY_%d_GUARD
#define MR_TYPE_INFO_LIKE_STRUCTS_FOR_ARITY_%d_GUARD
MR_DECLARE_ALL_TYPE_INFO_LIKE_STRUCTS_FOR_ARITY(%d);
#endif
",
		io__format(Template, [i(Arity), i(Arity), i(Arity)], !IO)
	;
		true
	).

:- pred rtti_type_template_arity(rtti_id::in, int::out) is semidet.

rtti_type_template_arity(RttiId, NumArgTypes) :-
	RttiId = ctor_rtti_id(_, RttiName),
	RttiName = type_info(TypeInfo),
	(
		TypeInfo = plain_type_info(_, ArgTypes)
	;
		TypeInfo = var_arity_type_info(_, ArgTypes)
	),
	NumArgTypes = list__length(ArgTypes).
rtti_type_template_arity(RttiId, NumArgTypes) :-
	RttiId = ctor_rtti_id(_, RttiName),
	RttiName = pseudo_type_info(PseudoTypeInfo),
	(
		PseudoTypeInfo = plain_pseudo_type_info(_, ArgTypes)
	;
		PseudoTypeInfo = var_arity_pseudo_type_info(_, ArgTypes)
	),
	NumArgTypes = list__length(ArgTypes).

:- func max_always_declared_arity = int.

max_always_declared_arity = 20.

%-----------------------------------------------------------------------------%

rtti_out__init_rtti_data_if_nec(Data, !IO) :-
	(
		Data = type_ctor_info(TypeCtorData)
	->
		RttiTypeCtor = tcd_get_rtti_type_ctor(TypeCtorData),
		io__write_string("\tMR_INIT_TYPE_CTOR_INFO(\n\t\t", !IO),
		output_ctor_rtti_id(RttiTypeCtor, type_ctor_info, !IO),
		io__write_string(",\n\t\t", !IO),
		RttiTypeCtor = rtti_type_ctor(ModuleName, TypeName, Arity),
		ModuleNameString = sym_name_mangle(ModuleName),
		string__append(ModuleNameString, "__", UnderscoresModule),
		(
			string__append(UnderscoresModule, _, TypeName)
		->
			true
		;
			io__write_string(UnderscoresModule, !IO)
		),
		MangledTypeName = name_mangle(TypeName),
		io__write_string(MangledTypeName, !IO),
		io__write_string("_", !IO),
		io__write_int(Arity, !IO),
		io__write_string("_0);\n", !IO)
	;
		Data = base_typeclass_info(_ModName, ClassName, ClassArity,
			base_typeclass_info(_N1, _N2, _N3, _N4, _N5,
			Methods))
	->
		io__write_string("#ifndef MR_STATIC_CODE_ADDRESSES\n", !IO),
			% the field number for the first method is 5,
			% since the methods are stored after N1 .. N5,
			% and fields are numbered from 0.
		FirstFieldNum = 5,
		CodeAddrs = list__map(make_code_addr, Methods),
		output_init_method_pointers(FirstFieldNum, CodeAddrs,
			ClassName, ClassArity, !IO),
		io__write_string("#endif /* MR_STATIC_CODE_ADDRESSES */\n",
			!IO)
	;
		true
	).

rtti_out__register_rtti_data_if_nec(Data, SplitFiles, !IO) :-
	(
		Data = type_ctor_info(TypeCtorData)
	->
		RttiTypeCtor = tcd_get_rtti_type_ctor(TypeCtorData),
		RttiId = ctor_rtti_id(RttiTypeCtor, type_ctor_info),
		(
			SplitFiles = yes,
			io__write_string("\t{\n\t", !IO),
			output_rtti_id_storage_type_name(RttiId, no, !IO),
			io__write_string(
				";\n\tMR_register_type_ctor_info(\n\t\t&",
				!IO),
			output_rtti_id(RttiId, !IO),
			io__write_string(");\n\t}\n", !IO)
		;
			SplitFiles = no,
			io__write_string(
				"\tMR_register_type_ctor_info(\n\t\t&", !IO),
			output_rtti_id(RttiId, !IO),
			io__write_string(");\n", !IO)
		)
	;
		Data = base_typeclass_info(_InstanceModuleName, _ClassId,
			_InstanceString, _BaseTypeClassInfo)
	->
		% XXX Registering base_typeclass_infos by themselves is not
		% enough. A base_typeclass_info doesn't say which types it
		% declares to be members of which typeclass, and for now
		% we don't even have any data structures in the runtime system
		% to describe such membership information.
		%
		% io__write_string(
		%	"\tMR_register_base_typeclass_info(\n\t\t&"),
		% output_base_typeclass_info_storage_type_name(
		%	InstanceModuleName, ClassId, InstanceString, no),
		% io__write_string(");\n")
		true
	;
		true
	).


:- pred output_init_method_pointers(int, list(code_addr), class_id, string,
		io__state, io__state).
:- mode output_init_method_pointers(in, in, in, in, di, uo) is det.

output_init_method_pointers(_, [], _, _, !IO).
output_init_method_pointers(FieldNum, [Arg|Args], ClassId, InstanceStr, !IO) :-
	io__write_string("\t\t", !IO),
	io__write_string("MR_field(MR_mktag(0), ", !IO),
	output_base_typeclass_info_name(ClassId, InstanceStr, !IO),
	io__format(", %d) =\n\t\t\t", [i(FieldNum)], !IO),
	output_code_addr(Arg, !IO),
	io__write_string(";\n", !IO),
	output_init_method_pointers(FieldNum + 1, Args, ClassId, InstanceStr,
		!IO).

%-----------------------------------------------------------------------------%

:- pred output_rtti_datas_decls(list(rtti_data)::in,
	string::in, string::in, int::in, int::out, decl_set::in, decl_set::out,
	io__state::di, io__state::uo) is det.

output_rtti_datas_decls([], _, _, N, N, !DeclSet, !IO).
output_rtti_datas_decls([RttiData | RttiDatas], FirstIndent, LaterIndent,
		N0, N, !DeclSet, !IO) :-
	output_rtti_data_decls(RttiData, FirstIndent, LaterIndent,
		N0, N1, !DeclSet, !IO),
	output_rtti_datas_decls(RttiDatas, FirstIndent, LaterIndent,
		N1, N, !DeclSet, !IO).

:- pred output_rtti_data_decls(rtti_data::in,
	string::in, string::in, int::in, int::out, decl_set::in, decl_set::out,
	io__state::di, io__state::uo) is det.

output_rtti_data_decls(RttiData, FirstIndent, LaterIndent,
		N0, N, !DeclSet, !IO) :-
	( RttiData = pseudo_type_info(type_var(_)) ->
		% These just get represented as integers,
		% so we don't need to declare them.
		% Also rtti_data_to_name/3 does not handle this case.
		N = N0
	;
		rtti_data_to_id(RttiData, RttiId),
		output_rtti_id_decls(RttiId, FirstIndent, LaterIndent,
			N0, N, !DeclSet, !IO)
	).

:- pred output_rtti_id_decls(rtti_id::in, string::in, string::in,
	int::in, int::out, decl_set::in, decl_set::out,
	io__state::di, io__state::uo) is det.

output_rtti_id_decls(RttiId, FirstIndent, LaterIndent,
		N0, N1, !DeclSet, !IO) :-
	output_data_addr_decls(rtti_addr(RttiId), FirstIndent, LaterIndent,
		N0, N1, !DeclSet, !IO).

:- pred output_addr_of_ctor_rtti_names(rtti_type_ctor::in,
	list(ctor_rtti_name)::in, io__state::di, io__state::uo) is det.

output_addr_of_ctor_rtti_names(_, [], !IO).
output_addr_of_ctor_rtti_names(RttiTypeCtor, [RttiName | RttiNames], !IO) :-
	io__write_string("\t", !IO),
	io__write_list([RttiName | RttiNames], ",\n\t",
		output_addr_of_ctor_rtti_id(RttiTypeCtor), !IO),
	io__write_string("\n", !IO).

:- pred output_cast_addr_of_rtti_datas(string::in, list(rtti_data)::in,
	io__state::di, io__state::uo) is det.

output_cast_addr_of_rtti_datas(_, [], !IO).
output_cast_addr_of_rtti_datas(Cast, [RttiData | RttiDatas], !IO) :-
	io__write_string("\t", !IO),
	io__write_list([RttiData | RttiDatas], ",\n\t",
		output_cast_addr_of_rtti_data(Cast), !IO),
	io__write_string("\n", !IO).

:- pred output_addr_of_rtti_datas(list(rtti_data)::in,
	io__state::di, io__state::uo) is det.

output_addr_of_rtti_datas([], !IO).
output_addr_of_rtti_datas([RttiData | RttiDatas], !IO) :-
	io__write_string("\t", !IO),
	io__write_list([RttiData | RttiDatas], ",\n\t",
		output_addr_of_rtti_data, !IO),
	io__write_string("\n", !IO).

output_cast_addr_of_rtti_data(Cast, RttiData, !IO) :-
	io__write_string(Cast, !IO),
	output_addr_of_rtti_data(RttiData, !IO).

output_addr_of_rtti_data(RttiData, !IO) :-
	( RttiData = pseudo_type_info(type_var(VarNum)) ->
		% rtti_data_to_name/3 does not handle this case
		io__write_int(VarNum, !IO)
	;
		rtti_data_to_id(RttiData, RttiId),
		output_addr_of_rtti_id(RttiId, !IO)
	).

:- pred output_addr_of_rtti_id(rtti_id::in, io__state::di, io__state::uo)
	is det.

output_addr_of_rtti_id(RttiId, !IO) :-
	%
	% If the RttiName is not an array, then
	% we need to use `&' to take its address
	%
	( rtti_id_has_array_type(RttiId) = yes ->
		true
	;
		io__write_string("&", !IO)
	),
	output_rtti_id(RttiId, !IO).

:- pred output_addr_of_ctor_rtti_id(rtti_type_ctor::in, ctor_rtti_name::in,
	io__state::di, io__state::uo) is det.

output_addr_of_ctor_rtti_id(RttiTypeCtor, RttiName, !IO) :-
	output_addr_of_rtti_id(ctor_rtti_id(RttiTypeCtor, RttiName), !IO).

output_rtti_id(RttiId, !IO) :-
	io__write_string(mercury_data_prefix, !IO),
	rtti__id_to_c_identifier(RttiId, Str),
	io__write_string(Str, !IO).

:- pred output_ctor_rtti_id(rtti_type_ctor::in, ctor_rtti_name::in,
	io__state::di, io__state::uo) is det.

output_ctor_rtti_id(RttiTypeCtor, RttiName, !IO) :-
	output_rtti_id(ctor_rtti_id(RttiTypeCtor, RttiName), !IO).

%-----------------------------------------------------------------------------%

:- pred output_maybe_quoted_string(maybe(string)::in,
	io__state::di, io__state::uo) is det.

output_maybe_quoted_string(MaybeName, !IO) :-
	(
		MaybeName = yes(Name),
		io__write_string("""", !IO),
		c_util__output_quoted_string(Name, !IO),
		io__write_string("""", !IO)
	;
		MaybeName = no,
		io__write_string("NULL", !IO)
	).

:- pred output_maybe_quoted_strings(list(maybe(string))::in,
	io__state::di, io__state::uo) is det.

output_maybe_quoted_strings(MaybeNames, !IO) :-
	io__write_string("\t", !IO),
	io__write_list(MaybeNames, ",\n\t", output_maybe_quoted_string, !IO),
	io__write_string("\n", !IO).

%-----------------------------------------------------------------------------%

:- pred output_exist_locn(exist_typeinfo_locn::in,
	io__state::di, io__state::uo) is det.

output_exist_locn(Locn, !IO) :-
	(
		Locn = plain_typeinfo(SlotInCell),
		io__write_string("{ ", !IO),
		io__write_int(SlotInCell, !IO),
		io__write_string(", -1 }", !IO)
	;
		Locn = typeinfo_in_tci(SlotInCell, SlotInTci),
		io__write_string("{ ", !IO),
		io__write_int(SlotInCell, !IO),
		io__write_string(", ", !IO),
		io__write_int(SlotInTci, !IO),
		io__write_string(" }", !IO)
	).

:- pred output_exist_locns(list(exist_typeinfo_locn)::in,
	io__state::di, io__state::uo) is det.

output_exist_locns(Locns, !IO) :-
	io__write_string("\t", !IO),
	io__write_list(Locns, ",\n\t", output_exist_locn, !IO),
	io__write_string("\n", !IO).

:- pred output_maybe_static_code_addr(maybe(code_addr)::in,
	io__state::di, io__state::uo) is det.

output_maybe_static_code_addr(yes(CodeAddr), !IO) :-
	output_static_code_addr(CodeAddr, !IO).
output_maybe_static_code_addr(no, !IO) :-
	io__write_string("NULL", !IO).

:- pred output_static_code_addr(code_addr::in, io__state::di, io__state::uo)
	is det.

output_static_code_addr(CodeAddr, !IO) :-
	io__write_string("MR_MAYBE_STATIC_CODE(", !IO),
	output_code_addr(CodeAddr, !IO),
	io__write_string(")", !IO).

%-----------------------------------------------------------------------------%

:- pred rtti_id_linkage(rtti_id::in, linkage::out) is det.

rtti_id_linkage(RttiId, Linkage) :-
	(
			% ANSI/ISO C doesn't allow forward declarations
			% of static data with incomplete types (in this
			% case array types without an explicit array
			% size), so make the declarations extern.
		yes = rtti_id_has_array_type(RttiId)
	->
		Linkage = extern
	;
		Exported = rtti_id_is_exported(RttiId),
		( Exported = yes, Linkage = extern
		; Exported = no, Linkage = static
		)
        ).

%-----------------------------------------------------------------------------%

:- func this_file = string.
this_file = "rtti_out.m".

%-----------------------------------------------------------------------------%
