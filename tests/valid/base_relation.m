:- module base_relation.

:- interface.

:- import_module aditi.

:- pred base(aditi__state, int, int).
:- mode base(aditi_mui, in, out) is nondet.
:- mode base(aditi_mui, out, out) is nondet.

:- pragma base_relation(base/3).

