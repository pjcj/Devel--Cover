/*
 * Copyright 2001-2003, Paul Johnson (pjcj@cpan.org)
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

static unsigned Covering = All;   /* Until we find out what we really want */

#define collecting(criteria) (Covering & (criteria))

static HV *Cover_hv,
          *Statements,
          *Branches,
          *Conditions,
          *Times,
          *Pending_conditionals;

static int Got_condition = 0;
static OP *Profiling_op  = 0;

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
    char   ch[ch_sz + 1];
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
    static int            sec  = 0,
                          usec = 0;
    int                   e;

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
    static int        utime = 0,
                      stime = 0;
    int               e;

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

static char *get_key(OP *o)
{
    static union sequence uniq;

    uniq.op.addr = o;
    uniq.op.seq  = o->op_seq;
    uniq.ch[ch_sz] = 0;
    return uniq.ch;
}

static void add_branch(OP *op, int br)
{
    AV  *branches;
    SV **count;
    int  c;
    SV **tmp = hv_fetch(Branches, get_key(op), ch_sz, 1);

    if (SvROK(*tmp))
        branches = (AV *) SvRV(*tmp);
    else
    {
        *tmp = newRV_inc((SV*) (branches = newAV()));
        av_unshift(branches, 2);
    }

    count = av_fetch(branches, br, 1);
    c     = SvTRUE(*count) ? SvIV(*count) + 1 : 1;
    sv_setiv(*count, c);
    NDEB(D(L, "Adding branch making %d at %p\n", c, op));
}

static AV *get_conditional_array(OP *op)
{
    AV  *conds;
    SV **tmp = hv_fetch(Conditions, get_key(op), ch_sz, 1);

    if (SvROK(*tmp))
        conds = (AV *) SvRV(*tmp);
    else
        *tmp = newRV_inc((SV*) (conds = newAV()));

    return conds;
}

static void set_conditional(OP *op, int cond, int value)
{
    SV **count;
    AV  *conds = get_conditional_array(op);

    count = av_fetch(conds, cond, 1);
    sv_setiv(*count, value);
    NDEB(D(L, "Setting %d conditional to %d at %p\n", cond, value, op));
}

static void add_conditional(OP *op, int cond)
{
    SV **count;
    int  c;
    AV  *conds = get_conditional_array(op);

    count = av_fetch(conds, cond, 1);
    c     = SvTRUE(*count) ? SvIV(*count) + 1 : 1;
    sv_setiv(*count, c);
    NDEB(D(L, "Adding %d conditional making %d at %p\n", cond, c, op));
}

static OP *get_condition(pTHX)
{
    char *ch;
    AV   *conds;
    SV  **sv;
    OP   *op;
    OP *(*f)(pTHX);
    I32   i;

    NDEB(D(L, "In get_condition\n"));

    ch = get_key(PL_op);
    sv = hv_fetch(Pending_conditionals, ch, ch_sz, 0);

    if (sv && SvROK(*sv))
    {
        conds = (AV *) SvRV(*sv);
        NDEB(D(L, "Looking through %d conditionals\n", av_len(conds)));

        sv = av_fetch(conds, 0, 0);
        f  = (OP *(*)(pTHX)) SvIV(*sv);

        for (i = 1; i <= av_len(conds); i++)
        {
            sv = av_fetch(conds, i, 0);
            op = (OP *) SvIV(*sv);

            {
                dSP;
                SV **count;
                int  type;
                AV  *conds = get_conditional_array(op);
                int value = SvTRUE(TOPs) ? 2 : 1;

                count = av_fetch(conds, 0, 1);
                type  = SvTRUE(*count) ? SvIV(*count) : 0;
                sv_setiv(*count, 0);

                /* Check if we have come from an xor with a true right op */
                if (type == 1)
                    value += 2;

                NDEB(D(L, "%3d: Found %p\n", i, PL_op));
                add_conditional(op, value);
            }
        }

        av_clear(conds);

        NDEB(D(L, "f is %p\n", f));

        PL_op->op_ppaddr = f;
    }
    else
    {
        Perl_croak(aTHX_
                   "All is lost, I know not where to go from %p, %d: %p\n",
                   PL_op, PL_op->op_seq, sv);
    }

    Got_condition = 1;

    return PL_op;
}

static void cover_cond()
{
    if (collecting(Branch))
    {
        dSP;
        int val = SvTRUE(TOPs);
        add_branch(PL_op, !val);
    }
}

static void cover_logop()
{
    /*
     * For OP_AND, if the first operand is false, we have short
     * circuited the second, otherwise the value of the and op is the
     * value of the second operand.
     *
     * For OP_OR, if the first operand is true, we have short circuited
     * the second, otherwise the value of the and op is the value of the
     * second operand.
     *
     * We check the value of the first operand by simply looking on the
     * stack.  To check the second operand it is necessary to note the
     * location of the next op after this logop.  When we get there, we
     * look at the stack and store the coverage information indexed to
     * this op.
     *
     * This scheme also works for OP_XOR with a small modification
     * because it doesn't short circuit.  See the comment below.
     *
     * To find out when we get to the next op we change the op_ppaddr to
     * point to get_condition(), which will do the necessary work and
     * then reset and run the original op_ppaddr.  We also store
     * information in the Pending_conditionals hash.  This is keyed on
     * the op and the value is an array, the first element of which is
     * the op_ppaddr we overwrote, and the subsequent elements are the
     * ops about which we are collecting the condition coverage
     * information.  Note that an op may be collecting condition
     * coverage information about a number of conditions.
     */

    if (!collecting(Condition))
        return;

    if (cLOGOP->op_first->op_type == OP_ITER)
    {
        /* loop - ignore it for now*/
    }
    else
    {
        dSP;
        int left_val = SvTRUE(TOPs);
        if (PL_op->op_type == OP_AND       &&  left_val ||
            PL_op->op_type == OP_ANDASSIGN &&  left_val ||
            PL_op->op_type == OP_OR        && !left_val ||
            PL_op->op_type == OP_ORASSIGN  && !left_val ||
            PL_op->op_type == OP_XOR)
        {
            char *ch;
            AV *conds;
            SV **tmp,
               *cond,
               *ppaddr;
            OP *next,
               *right;

            right = cLOGOP->op_first->op_sibling;
            NDEB(op_dump(right));

            if (right->op_type == OP_NEXT ||
                right->op_type == OP_LAST ||
                right->op_type == OP_REDO ||
                right->op_type == OP_GOTO)
            {
                /*
                 * If the right side of the op is a branch, we don't
                 * care what its value is - it won't be returning one.
                 * We're just glad to be here, so we chalk up success.
                 */

                add_conditional(PL_op, 2);
            }
            else
            {
                if (PL_op->op_type == OP_XOR && left_val)
                {
                    /*
                     * This is an xor.  It does not short circuit.  We
                     * have just executed the right op, rather than the
                     * left op as with and and or.  When we get to next
                     * we will have already done the xor, so we can work
                     * out what the value of the left op was.
                     *
                     * We set a flag in the first element of the array
                     * to say that we had a true value from the right
                     * op.
                     */

                    set_conditional(PL_op, 0, 1);
                }

                NDEB(op_dump(PL_op));

                next = PL_op->op_next;
                ch   = get_key(next);
                tmp  = hv_fetch(Pending_conditionals, ch, ch_sz, 1);

                if (SvROK(*tmp))
                    conds = (AV *)SvRV(*tmp);
                else
                    *tmp = newRV_inc((SV*) (conds = newAV()));

                if (av_len(conds) < 0)
                {
                    NDEB(D(L, "setting f to %p\n", next->op_ppaddr));
                    ppaddr = newSViv((IV) next->op_ppaddr);
                    av_push(conds, ppaddr);
                }

                cond = newSViv((IV) PL_op);
                av_push(conds, cond);

                NDEB(D(L, "Adding conditional %p to %d, making %d\n",
                       next, next->op_seq, av_len(conds)));
                NDEB(svdump(Pending_conditionals));
                NDEB(op_dump(PL_op));
                NDEB(op_dump(next));

                next->op_ppaddr = get_condition;
            }
        }
        else
        {
            add_conditional(PL_op, 3);
        }
    }
}

#if CAN_PROFILE

static void cover_time()
{
    SV   **count;
    IV     c;
    char  *ch;

    if (collecting(Time))
    {
        /*
         * Profiling information is stored against Profiling_op, the one
         * we have just run.
         */

        NDEB(D(L, "Cop at %p, op at %p, timing %p\n", PL_curcop, PL_op, Profiling_op));

        if (Profiling_op)
        {
            ch    = get_key(Profiling_op);
            count = hv_fetch(Times, ch, ch_sz, 1);
            c     = (SvTRUE(*count) ? SvIV(*count) : 0) +
#if 0
                    Profiling == 1 ? cpu() : elapsed();
#else
                    elapsed();
#endif
            sv_setiv(*count, c);
            NDEB(D(L, "Adding time: sum %d at %p\n", c, Profiling_op));
        }
        Profiling_op = PL_op;
    }
}

#endif

static int runops_cover(pTHX)
{
    SV   **count;
    IV     c;
    char  *ch;
    HV    *Files           = 0;
    int    collecting_here = 1;
    char  *lastfile        = 0;

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

#if CAN_PROFILE
    elapsed();
#endif

    for (;;)
    {
        NDEB(D(L, "running func %p\n", PL_op->op_ppaddr));

        if (Got_condition)
        {
            Got_condition = 0;
            goto call_fptr;
        }

        if (!Covering)
            goto call_fptr;

        /* Check to see whether we are interested in this file */

        if (PL_op->op_type == OP_NEXTSTATE)
        {
            char *file = CopFILE(cCOP);
            if (file && (!lastfile || lastfile && strNE(lastfile, file)))
            {
                if (!Files)
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
        {
#if CAN_PROFILE
            cover_time();
            Profiling_op = 0;
#endif
            goto call_fptr;
        }

        /*
         * We are about the run the op PL_op, so we'll collect
         * information for it now.
         */

        switch (PL_op->op_type)
        {
            case OP_SETSTATE:
            case OP_NEXTSTATE:
            case OP_DBSTATE:
            {
#if CAN_PROFILE
                cover_time();
#endif
                if (collecting(Statement))
                {
                    ch    = get_key(PL_op);
                    count = hv_fetch(Statements, ch, ch_sz, 1);
                    c     = SvTRUE(*count) ? SvIV(*count) + 1 : 1;
                    sv_setiv(*count, c);
                    NDEB(op_dump(PL_op));
                }
                break;
            }

            case OP_COND_EXPR:
            {
                cover_cond();
                break;
            }

            case OP_AND:
            case OP_OR:
            case OP_ANDASSIGN:
            case OP_ORASSIGN:
            case OP_XOR:
            {
                cover_logop();
                break;
            }

            default:
                ;  /* IBM's xlC compiler on AIX is very picky */
        }

        call_fptr:
        if (!(PL_op = CALL_FPTR(PL_op->op_ppaddr)(aTHX)))
        {
#if CAN_PROFILE
            cover_time();
#endif
            break;
        }

        PERL_ASYNC_CHECK();
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

#if 0
static void cv_destroy_cb(pTHX_ CV *cv)
{
    SV *sv;
    IV iv;
    dSP;

    PDEB(D(L, "cv_destroy_cb %p - %p\n", cv, Covering));

    if (!Covering)
        return;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);

    sv = sv_newmortal();
    iv = PTR2IV(cv);
    sv_setiv(newSVrv(sv, "B::CV"), iv);

    XPUSHs(sv);
    /* XPUSHs(sv_2mortal(newSViv(cv))); */

    PUTBACK;

    call_pv("Devel::Cover::get_cover_x", G_DISCARD);

    FREETMPS;
    LEAVE;

    NDEB(svdump(cv));
}
#endif

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

BOOT:
    PL_runops        = runops_orig;
    /* PL_savebegin     = TRUE; */
    /* PL_savecheck     = TRUE; */
    /* PL_saveinit      = TRUE; */
    /* PL_saveend       = TRUE; */
    /* PL_cv_destroy_cb = cv_destroy_cb; */
