#!/bin/sh
#---------------------------------------------------------------------------#
# Copyright (C) 1995 University of Melbourne.
# This file may only be copied under the terms of the GNU General
# Public License - see the file COPYING in the Mercury distribution.
#---------------------------------------------------------------------------#
#
# MCN - Mercury Compiler (compiled with NU-Prolog).
#
# Use `mcn -h' for help.
#
# Environment variables: MERCURY_INT_DIR, MERCURY_DEP_DIR, MERCURY_C_INCL_DIR,
# MERCURY_COMPILER.

INTDIR=${MERCURY_INT_DIR=@LIBDIR@/ints}
DEPDIR=${MERCURY_DEP_DIR=@LIBDIR@/deps}
C_INCL=${MERCURY_C_INCL_DIR=@LIBDIR@/inc}
MC=${MERCURY_COMPILER=@LIBDIR@/nuprolog/@FULLARCH@/mercury_compile.nu}

exec $MC -I "$INTDIR" -I "$DEPDIR" --c-include-directory "$C_INCL" "$@"
