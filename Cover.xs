/*
 * Copyright 2001-2002, Paul Johnson (pjcj@cpan.org)
 *
 * This software is free.  It is licensed under the same terms as Perl itself.
 *
 * The latest version of this software should be available from my homepage:
 * http://www.pjcj.net
 *
 */

#ifdef __cplusplus
extern "C" {
#endif

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#ifdef __cplusplus
}
#endif

#ifdef PERL_OBJECT
#define CALLOP this->*PL_op
#else
#define CALLOP *PL_op
#endif

#define PDEB(a) a
#define NDEB(a)
#define D PerlIO_printf
#define L Perl_debug_log
#define svdump(sv) do_sv_dump(0, L, (SV *)sv, 0, 10, 1, 0);

#define None      0x00000000
#define Statement 0x00000001
#define Branch    0x00000002
#define Condition 0x00000004
#define Path      0x00000008
#define Pod       0x00000010
#define Time      0x00000020
#define All       0xffffffff

static unsigned Covering = None;

#define collecting(criteria) (Covering & (criteria))

#define COND_WAITING 0x8000

static HV *Cover_hv,
          *Statements,
          *Branches,
          *Conditions,
          *Times,
          *Pending_conditionals;

typedef int seq_t;
#define ch_sz (sizeof(void *) + sizeof(seq_t))

struct unique    /* Well, we'll be fairly unlucky if it's not */
{
    void *addr;
    seq_t seq;
};

union sequence   /* Hack, hack, hackety hack. */
{
    struct unique op;
    char ch[ch_sz + 1];
};

#ifdef HAS_GETTIMEOFDAY

#ifdef __cplusplus
extern "C" {
#endif

#ifdef WIN32
#include <time.h>
#else
#include <sys/time.h>
#endif

#ifdef __cplusplus
}
#endif

static int elapsed()
{
    static struct timeval time;
    static int sec  = 0,
               usec = 0;
    int e;

    gettimeofday(&time, NULL);
    e    = (time.tv_sec - sec) * 1e6 + time.tv_usec - usec;
    sec  = time.tv_sec;
    usec = time.tv_usec;

    /* fprintf(stderr, "[[[%d]]]\n", sec * 1e6 + usec); */

    return e;
}

#endif /* HAS_GETTIMEOFDAY */

#ifdef HAS_TIMES

#ifndef HZ
#  ifdef CLK_TCK
#    define HZ CLK_TCK
#  else
#    define HZ 60
#  endif
#endif

static int cpu()
{
    static struct tms time;
    static int utime = 0,
               stime = 0;
    int e;

#ifndef VMS
    (void)PerlProc_times(&time);
#else
    (void)PerlProc_times((tbuffer_t *)&time);
#endif

    e = time.tms_utime - utime + time.tms_stime - stime;
    utime = time.tms_utime;
    stime = time.tms_stime;

    /* fprintf(stderr, "<<<%d>>>\n", utime + stime); */

    return e / HZ;
}

#endif /* HAS_TIMES */

#define CAN_PROFILE defined HAS_GETTIMEOFDAY || defined HAS_TIMES

/* The following comment has been superceded.  There aren't enough hooks
 * in the core to allow me to get at the seqence numbers of the ops
 * before they get used in runops_cover.  Well, I probably could do it
 * somehow, but for now the sequence number is just used, not changed.
 */

/* Completely abuse the sequence number.  It's not used for anything now
 * anyway.  In fact, I'm not sure it ever needs to be anything other
 * than 0, -1 or something else, and the -1 is only for the benefit of
 * the compiler.  I suppose B::Concise and similar modules can use it
 * for display purposes.
 *
 * Anyway, I use the MSB to store whether or not this op needs to store
 * some condition coverage, and the rest to store my own sequence number
 * which, when combined with the address of the op will hopefully be
 * unique over the lifetime of the program.
 *
 * The MSB should be reset by the time we get to op_free, but if it's
 * not we'll get a leak for 0x7fff.  In that respect we're no different
 * from perl itself.
 */

static void walk_reset_op_seq(OP *o)
{
    if (!o) return;
    NDEB(D(L, "%p : %d\n", o, o->op_seq));
    o->op_seq = 0;
    if (o->op_flags & OPf_KIDS)
    {
        OP *kid;
        for (kid = cUNOPo->op_first; kid; kid = kid->op_sibling)
            walk_reset_op_seq(kid);
    }
}

U16 get_seq(OP *o)
{
    static U16 max_seq = 0;

    if (!o->op_seq)
    {
        if (max_seq++ & COND_WAITING)
            max_seq = 1;
        o->op_seq = max_seq;
    }
    return o->op_seq;
}

static char *get_key(OP *o)
{
    static union sequence uniq;

    uniq.op.addr = o;
    /* uniq.op.seq  = get_seq(o); */
    uniq.op.seq  = o->op_seq;
    uniq.ch[ch_sz] = 0;
    return uniq.ch;
}

static void add_branch(OP *op, int br)
{
    AV *branches;
    SV **count;
    int c;
    SV **tmp = hv_fetch(Branches, get_key(op), ch_sz, 1);
    if (SvROK(*tmp))
        branches = (AV *)SvRV(*tmp);
    else
    {
        *tmp = newRV_inc((SV*) (branches = newAV()));
        av_unshift(branches, 2);
    }

    count = av_fetch(branches, br, 1);
    c     = SvTRUE(*count) ? SvIV(*count) + 1 : 1;
    sv_setiv(*count, c);
    NDEB(D(L, "Adding %d conditional making %d at %p\n", cond, c, op));
}


#define condition_waiting(o)       (get_seq(o) &   COND_WAITING)
#define condition_waiting_clear(o) (o->op_seq  &= ~COND_WAITING)

static void condition_waiting_set(OP *o)
{
    get_seq(o);
    o->op_seq |= COND_WAITING;
}

static void add_conditional(OP *op, int cond)
{
    AV *conds;
    SV **count;
    int c;
    SV **tmp = hv_fetch(Conditions, get_key(op), ch_sz, 1);
    if (SvROK(*tmp))
        conds = (AV *)SvRV(*tmp);
    else
    {
        *tmp = newRV_inc((SV*) (conds = newAV()));
        av_unshift(conds, 3);
    }

    count = av_fetch(conds, cond, 1);
    c     = SvTRUE(*count) ? SvIV(*count) + 1 : 1;
    sv_setiv(*count, c);
    NDEB(D(L, "Adding %d conditional making %d at %p\n", cond, c, op));
}

static int runops_cover(pTHX)
{
    SV **count;
    IV c;
    HV *Files;
    int collecting_here = 1;
    char *lastfile = 0;

#if CAN_PROFILE
    static COP *cop = 0;
    int lapsed;
    elapsed();
#endif

    NDEB(D(L, "runops_cover\n"));

    if (!Cover_hv)
    {
        /* TODO - this probably leaks all over the place */

        SV **tmp;

        Cover_hv   = newHV();

        tmp        = hv_fetch(Cover_hv, "statement", 9, 1);
        Statements = newHV();
        *tmp       = newRV_inc((SV*) Statements);

        tmp        = hv_fetch(Cover_hv, "branch", 6, 1);
        Branches   = newHV();
        *tmp       = newRV_inc((SV*) Branches);

        tmp        = hv_fetch(Cover_hv, "condition", 9, 1);
        Conditions = newHV();
        *tmp       = newRV_inc((SV*) Conditions);

#if CAN_PROFILE
        tmp        = hv_fetch(Cover_hv, "time", 4, 1);
        Times      = newHV();
        *tmp       = newRV_inc((SV*) Times);
#endif

        Pending_conditionals = newHV();
    }

    for (;;)
    {
        if (!(PL_op = CALL_FPTR(PL_op->op_ppaddr)(aTHX)))
            break;

        PERL_ASYNC_CHECK();

        if (!Covering)
            continue;

        /* Check to see whether we are interested in this file */

        if (PL_op->op_type == OP_NEXTSTATE)
        {
            char *file = CopFILE(cCOP);
            if (file && (!lastfile || lastfile && strNE(lastfile, file)))
            {
                Files = get_hv("Devel::Cover::Files", FALSE);
                if (Files)
                {
                    SV **f = hv_fetch(Files, file, strlen(file), 0);
                    collecting_here = f ? SvIV(*f) : 1;
                    NDEB(D(L, "File: %s [%d]\n", file, collecting_here));
                }
                lastfile = file;
            }
        }

        if (!collecting_here)
            continue;

        /* if (collecting(Condition) && condition_waiting(PL_op)) */
        if (collecting(Condition))
        {
            char *ch;
            AV *conds;
            SV **sv;
            I32 i;

            /* condition_waiting_clear(PL_op); */
            ch = get_key(PL_op);
            sv = hv_fetch(Pending_conditionals, ch, ch_sz, 0);

            if (sv && SvROK(*sv))
            {
                conds = (AV *)SvRV(*sv);
                NDEB(D(L, "Looking through %d conditionals\n",av_len(conds)+1));
                for (i = 0; i <= av_len(conds); i++)
                {
                    SV **sv = av_fetch(conds, i, 0);
                    OP *op  = (OP *) SvIV(*sv);

                    dSP;
                    NDEB(D(L, "%3d: Found %p\n", i, PL_op));
                    add_conditional(op, SvTRUE(TOPs) ? 2 : 1);
                }

                av_clear(conds);
            }
            else
            {
                /* We might get here in an eval for example, where there
                 * hasn't been a chance to hack the op_seq numbers
                 * first.  We've wasted a bit of effort, but it's no
                 * problem.
                 */
#if 0
                int i;

                svdump(Pending_conditionals);
                for (i = 0; i < ch_sz; i++)
                {
                    printf("%o:", ch[i] & 0xff);
                }
                op_dump(PL_op);
                Perl_croak(aTHX_ "No pending conditional found at %p, %d: %p\n",
                           PL_op, PL_op->op_seq, sv);
#endif
            }
        }

        switch (PL_op->op_type)
        {
            case OP_SETSTATE:
            case OP_NEXTSTATE:
            case OP_DBSTATE:
            {
#if CAN_PROFILE
                /* lapsed = Profiling && PL_curcop != cop ? elapsed() : -1; */
                lapsed = collecting(Time) ? elapsed() : -1;
#endif

                if (collecting(Statement))
                {
                    char *ch = get_key(PL_op);
                    count = hv_fetch(Statements, ch, ch_sz, 1);
                    c     = SvTRUE(*count) ? SvIV(*count) + 1 : 1;
                    sv_setiv(*count, c);

                    NDEB(op_dump(PL_op));
                }

#if CAN_PROFILE
                if (lapsed > -1)
                {
                    if (cop)
                    {
                        char *ch = get_key((OP *)cop);
                        count    = hv_fetch(Times, ch, ch_sz, 1);
                        c        = (SvTRUE(*count) ? SvIV(*count) : 0) +
#if 0
                                   Profiling == 1 ? cpu() : elapsed();
#else
                                   lapsed;
#endif
                        sv_setiv(*count, c);
                    }
                    elapsed();  /* reset the timer */
                    cop = PL_curcop;
                }
#endif
                break;
            }

            case OP_COND_EXPR:
            {
                if (collecting(Branch))
                {
                    dSP;
                    int val = SvTRUE(TOPs);
                    add_branch(PL_op, !val);
                }
                break;
            }

            case OP_AND:
            case OP_OR:
            {
                /*
                 * For OP_AND, if the first operand is false, we have
                 * short circuited the second, otherwise the value of
                 * the and op is the value of the second operand.
                 *
                 * For OP_OR, if the first operand is true, we have
                 * short circuited the second, otherwise the value of
                 * the and op is the value of the second operand.
                 *
                 * We check the value of the first operand by simply
                 * looking on the stack.  To check the second operand it
                 * is necessary to note the location of the next op
                 * after this logop.  When we get there, we look at the
                 * stack and store the coverage information indexed to
                 * this op.
                 *
                 * The information about the next op is stored in the
                 * Pending_conditionals array which we have to iterate
                 * through later.  collect_conditional tells how many
                 * conditionals are in the array.  When we find one we
                 * leave it in the array but change the data so we don't
                 * match again.  Then, when collect_conditional is zero
                 * Pending_conditionals is emptied.  This might not be
                 * the speed win I had hoped for.
                 */

                if (!collecting(Condition))
                    break;

                if (cLOGOP->op_first->op_type == OP_ITER)
                {
                    /* loop - ignore it */
                }
                else
                {
                    dSP;
                    int first_val = SvTRUE(TOPs);
                    if (PL_op->op_type == OP_AND && first_val ||
                        PL_op->op_type == OP_OR && !first_val)
                    {
                        char *ch;
                        AV *conds;
                        SV **tmp,
                           *cond;

                        ch = get_key(PL_op->op_next);
                        tmp = hv_fetch(Pending_conditionals, ch, ch_sz, 1);
                        if (SvROK(*tmp))
                            conds = (AV *)SvRV(*tmp);
                        else
                            *tmp = newRV_inc((SV*) (conds = newAV()));

                        cond = newSViv((IV)PL_op);
                        av_push(conds, cond);

                        /* condition_waiting_set(PL_op->op_next); */

                        NDEB(D(L, "Adding conditional %p to %d, making %d\n",
                                  PL_op->op_next, PL_op->op_next->op_seq,
                                  av_len(conds) + 1));
                        NDEB(svdump(Pending_conditionals));
                        NDEB(op_dump(PL_op));
                        NDEB(op_dump(PL_op->op_next));

                    }
                    else
                    {
                        add_conditional(PL_op, 0);
                    }
                }
                break;
            }

            default:
        }
    }

    TAINT_NOT;
    return 0;
}

static int runops_orig(pTHX)
{
    NDEB(D(L, "runops_orig\n"));

    while ((PL_op = CALL_FPTR(PL_op->op_ppaddr)(aTHX)))
    {
        PERL_ASYNC_CHECK();
    }

    TAINT_NOT;
    return 0;
}

MODULE = Devel::Cover PACKAGE = Devel::Cover

PROTOTYPES: ENABLE

void
set_criteria(flag)
        unsigned flag
    PPCODE:
        /* fprintf(stderr, "Cover set to %d\n", flag); */
        PL_runops = (Covering = flag) ? runops_cover : runops_orig;

void
add_criteria(flag)
        unsigned flag
    PPCODE:
        PL_runops = (Covering |= flag) ? runops_cover : runops_orig;

void
remove_criteria(flag)
        unsigned flag
    PPCODE:
        PL_runops = (Covering &= ~flag) ? runops_cover : runops_orig;

unsigned
get_criteria()
    CODE:
        RETVAL = Covering;
    OUTPUT:
        RETVAL

unsigned
coverage_none()
    CODE:
        RETVAL = None;
    OUTPUT:
        RETVAL

unsigned
coverage_statement()
    CODE:
        RETVAL = Statement;
    OUTPUT:
        RETVAL

unsigned
coverage_branch()
    CODE:
        RETVAL = Branch;
    OUTPUT:
        RETVAL

unsigned
coverage_condition()
    CODE:
        RETVAL = Condition;
    OUTPUT:
        RETVAL

unsigned
coverage_path()
    CODE:
        RETVAL = Path;
    OUTPUT:
        RETVAL

unsigned
coverage_pod()
    CODE:
        RETVAL = Pod;
    OUTPUT:
        RETVAL

unsigned
coverage_time()
    CODE:
        RETVAL = Time;
    OUTPUT:
        RETVAL

unsigned
coverage_all()
    CODE:
        RETVAL = All;
    OUTPUT:
        RETVAL

SV *
coverage()
    CODE:
          ST(0) = sv_newmortal();
          if (Cover_hv)
               sv_setsv(ST(0), newRV_inc((SV*) Cover_hv));
          else
               ST(0) = &PL_sv_undef;

void
reset_op_seq(op)
        void *op
    PPCODE:
        walk_reset_op_seq((OP *) op);

BOOT:
    PL_runops = runops_orig;
