/*
** Copyright (C) 1997-2001 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** mercury_trace.h defines the interface by which the internal and external
** debuggers can control how the tracing subsystem treats events.
**
** The macros, functions and variables of this module are intended to be
** referred to only from code generated by the Mercury compiler, and from
** hand-written code in the Mercury runtime or the Mercury standard library,
** and even then only if at least some part of the program was compiled
** with some form of execution tracing.
**
** The parts of the tracing system that need to be present even when tracing
** is not enabled are in the module runtime/mercury_trace_base.
*/

#ifndef MERCURY_TRACE_H
#define MERCURY_TRACE_H

/*
** MR_Event_Info is used to hold the information for a trace event.  One
** of these is built by MR_trace_event and is passed (by reference)
** throughout the tracing system.
*/

typedef struct MR_Event_Info_Struct {
	MR_Unsigned			MR_event_number;
	MR_Unsigned			MR_call_seqno;
	MR_Unsigned			MR_call_depth;
	MR_Trace_Port			MR_trace_port;
	const MR_Label_Layout		*MR_event_sll;
	const char 			*MR_event_path;
	MR_Word				MR_saved_regs[MR_MAX_FAKE_REG];
	int				MR_max_mr_num;
} MR_Event_Info;

/*
** MR_Event_Details is used to save some globals across calls to
** MR_trace_debug_cmd.  It is passed to MR_trace_retry which can
** then override the saved values.
*/

typedef struct MR_Event_Details_Struct {
	MR_Unsigned			MR_event_number;
	MR_Unsigned			MR_call_seqno;
	MR_Unsigned			MR_call_depth;
} MR_Event_Details;

/*
** The above declarations are part of the interface between MR_trace_real
** and the internal and external debuggers. Even though MR_trace_real is
** defined in mercury_trace.c, its prototype is not here. Instead, it is
** in runtime/mercury_init.h. This is necessary because the address of
** MR_trace_real may be taken in automatically generated <main>_init.c files,
** and we do not want to include mercury_trace.h in such files; we don't want
** them to refer to the trace directory at all unless debugging is enabled.
*/

/*
** Ideally, MR_trace_retry works by resetting the state of the stacks and
** registers to the state appropriate for the call to the selected ancestor,
** setting *jumpaddr to point to the start of the code for the selected
** ancestor, and returning MR_RETRY_OK_DIRECT.
**
** If resetting the stacks requires discarding the stack frame of a procedure
** whose evaluation method is memo or loopcheck, we must also reset the call
** table entry for that particular call to uninitialized. There are two reasons
** for this. The first is that the call table entry was uninitialized at the
** time of the first call, so if the retried call is to do what the original
** call did, it must find the call table entry in the same state. The second
** reason is that if we did not reset the call table entry, then the retried
** call would find the "call active" marker left by the original call, and
** since this normally indicates an infinite loop, it will generate a runtime
** abort.
**
** Unfortunately, resetting the call table entry to uninitialized does not work
** in general for procedures whose evaluation method is minimal model tabling.
** In such procedures, a subgoal can be a consumer as well as a generator,
** and control passes between consumers and generators in a complex fashion.
** There is no safe way to reset the state of such a system, except to wait
** for normal forward execution to execute the completion operation on an
** SCC of mutually dependent subgoals.
**
** If the stack segments between the current call and the call to be retried
** contain one or more such complete SCCs, then MR_trace_retry will return
** either MR_RETRY_OK_FINISH_FIRST or MR_RETRY_OK_FAIL_FIRST. The first
** indicates that the `retry' command should be executed only after a `finish'
** command on the selected call has made the state of the SCC quiescent.
** However, if the selected call is itself a generator, then reaching one of
** its exit ports is not enough to make its SCC quiescent; for that, one must
** wait for its failure. This is why in such cases, MR_trace_retry will ask
** for the `retry' command to be executed only after a `fail' command.
** 
** If the fail command reaches an exception port on the selected call instead
** of the fail port, then the SCC cannot be made quiescent, and MR_trace_retry
** will return MR_RETRY_ERROR, putting a description of the error into
** *problem. It will also do this for other, more prosaic problems, such as
** when it finds that some of the stack frames it looks at lack debugging
** information.
**
** Retry across I/O is unsafe in general, at least for now. It is therefore
** only allowed if in_fp and out_fp are both non-NULL, and if the user, when
** asked whether he/she wants to perform the retry anyway, says yes.
*/

typedef	enum {
	MR_RETRY_OK_DIRECT,
	MR_RETRY_OK_FINISH_FIRST,
	MR_RETRY_OK_FAIL_FIRST,
	MR_RETRY_ERROR
} MR_Retry_Result;

extern	MR_Retry_Result	MR_trace_retry(MR_Event_Info *event_info,
				MR_Event_Details *event_details,
				int ancestor_level, const char **problem,
				FILE *in_fp, FILE *out_fp,
				MR_Code **jumpaddr);

/*
** MR_trace_cmd says what mode the tracer is in, i.e. how events should be
** treated.
**
** If MR_trace_cmd == MR_CMD_GOTO, the event handler will stop at the next
** event whose event number is equal to or greater than MR_trace_stop_event.
**
** If MR_trace_cmd == MR_CMD_NEXT, the event handler will stop at the next
** event at depth MR_trace_stop_depth.
**
** If MR_trace_cmd == MR_CMD_FINISH, the event handler will stop at the next
** event at depth MR_trace_stop_depth and whose port is EXIT or FAIL or
** EXCEPTION.
**
** If MR_trace_cmd == MR_CMD_FAIL, the event handler will stop at the next
** event at depth MR_trace_stop_depth and whose port is FAIL or EXCEPTION.
**
** If MR_trace_cmd == MR_CMD_RESUME_FORWARD, the event handler will stop at
** the next event of any call whose port is *not* REDO or FAIL or EXCEPTION.
**
** If MR_trace_cmd == MR_CMD_RETURN, the event handler will stop at
** the next event of any call whose port is *not* EXIT.
**
** If MR_trace_cmd == MR_CMD_MIN_DEPTH, the event handler will stop at
** the next event of any call whose depth is at least MR_trace_stop_depth.
**
** If MR_trace_cmd == MR_CMD_MAX_DEPTH, the event handler will stop at
** the next event of any call whose depth is at most MR_trace_stop_depth.
**
** If MR_trace_cmd == MR_CMD_TO_END, the event handler will not stop
** until the end of the program.
**
** If the event handler does not stop at an event, it will print the
** summary line for the event if MR_trace_print_intermediate is true.
*/

typedef enum {
	MR_CMD_GOTO,
	MR_CMD_NEXT,
	MR_CMD_FINISH,
	MR_CMD_FAIL,
	MR_CMD_RESUME_FORWARD,
	MR_CMD_EXCP,
	MR_CMD_RETURN,
	MR_CMD_MIN_DEPTH,
	MR_CMD_MAX_DEPTH,
	MR_CMD_TO_END
} MR_Trace_Cmd_Type;

typedef enum {
	MR_PRINT_LEVEL_NONE,	/* no events at all                        */
	MR_PRINT_LEVEL_SOME,	/* events matching an active spy point     */
	MR_PRINT_LEVEL_ALL	/* all events                              */
} MR_Trace_Print_Level;

typedef struct {
	MR_Trace_Cmd_Type	MR_trace_cmd;	
				/*
				** The MR_trace_stop_depth field is meaningful
				** if MR_trace_cmd is MR_CMD_NEXT or
				** MR_CMD_FINISH.
				*/
	MR_Unsigned		MR_trace_stop_depth;
				/*
				** The MR_trace_stop_event field is meaningful
				** if MR_trace_cmd is MR_CMD_GOTO  
				*/
	MR_Unsigned		MR_trace_stop_event;
	MR_Trace_Print_Level	MR_trace_print_level;
	bool			MR_trace_strict;

				/*
				** The next field is an optimization;
				** it must be set to !MR_trace_strict ||
				** MR_trace_print_level != MR_PRINT_LEVEL_NONE
				*/
	bool			MR_trace_must_check;
} MR_Trace_Cmd_Info;

#define	MR_port_is_final(port)		((port) == MR_PORT_EXIT || \
					 (port) == MR_PORT_FAIL || \
					 (port) == MR_PORT_EXCEPTION)

#define	MR_port_is_interface(port)	((port) <= MR_PORT_EXCEPTION)

#define	MR_port_is_entry(port)		((port) == MR_PORT_CALL)

#endif /* MERCURY_TRACE_H */
