%---------------------------------------------------------------------------%
% vim: ts=4 sw=4 et ft=mercury
%---------------------------------------------------------------------------%
%
% Test the s specifier of string__format.
%
%---------------------------------------------------------------------------%

:- module string_format_s.

:- interface.

:- import_module io.

:- pred main(io::di, io::uo) is det.

%---------------------------------------------------------------------------%

:- implementation.

:- import_module list.
:- import_module string.
:- import_module string_format_lib.

main -->
    { Strings = [s(""), s("a"), s("ab"), s("abc"), s("abcdefghijklmno")] },
    list__foldl(output_list(Strings), format_strings("s")).

%---------------------------------------------------------------------------%
