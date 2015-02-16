%---------------------------------------------------------------------------%
% vim: ts=4 sw=4 et ft=mercury
%---------------------------------------------------------------------------%

:- module multidet_prune1.
:- interface.
:- import_module io.

:- pred main(io::di, io::uo) is det.

:- implementation.
:- import_module require.

:- pred q(int::in) is det.
:- pragma no_inline(q/1).

q(_).

main -->
    ( { X = 1 ; X = 2 ; fail }, { q(X) } ->
        io__write_int(1)
    ;
        io__write_int(2)
    ).
