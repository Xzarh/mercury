% This module c_main_int defines a Mercury predicate c_main which acts as an
% interface to the C function c_main(), which is defined in c_main.c.

% This source file is hereby placed in the public domain.  -fjh (the author).

:- module c_main_int.

:- interface.
:- import_module io.

% Since the c_main() function has side effects, we declare the corresponding
% Mercury predicate as one that takes an io__state pair.  If we didn't do
% this, the Mercury compiler might optimize away calls to it!

:- pred c_main(io__state::di, io__state::uo) is det.

:- implementation.

	% #include the header file containing the function prototype
	% for c_main(), using a `pragma c_header_code' declaration.
	% Note that any double quotes or backslashes in the C code for
	% the `#include' line must be escaped, since the C code is
	% given as a Mercury string.
:- pragma c_header_code("#include \"c_main.h\"").

	% Define the Mercury predicate c_main to call the C function
	% c_main.
:- pragma c_code(c_main(IO0::di, IO::uo), [may_call_mercury],
		"c_main(); IO = IO0;").
