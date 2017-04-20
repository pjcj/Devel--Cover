/*
 * Copyright 2001-2016, Paul Johnson (paul@pjcj.net)
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

#define PERL_NO_GET_CONTEXT
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

#ifndef START_MY_CXT
/* No threads in 5.6 */
#define START_MY_CXT    static my_cxt_t my_cxt;
#define dMY_CXT_SV      dNOOP
#define dMY_CXT         dNOOP
#define MY_CXT_INIT     NOOP
#define MY_CXT          my_cxt

#define pMY_CXT         void
#define pMY_CXT_
#define _pMY_CXT
#define aMY_CXT
#define aMY_CXT_
#define _aMY_CXT
#endif

#define MY_CXT_KEY "Devel::Cover::_guts" XS_VERSION

#define PDEB(a) a
#define NDEB(a) ;
#define D PerlIO_printf
#define L Perl_debug_log
#define svdump(sv) do_sv_dump(0, L, (SV *)sv, 0, 10, 1, 0);

#define None       0x00000000
#define Statement  0x00000001
#define Branch     0x00000002
#define Condition  0x00000004
#define Subroutine 0x00000008
#define Path       0x00000010
#define Pod        0x00000020
#define Time       0x00000040
#define All        0xffffffff

#define CAN_PROFILE defined HAS_GETTIMEOFDAY || defined HAS_TIMES

struct unique {  /* Well, we'll be fairly unlucky if it's not */
    OP *addr,
        op;
};

#define KEY_SZ sizeof(struct unique)

typedef struct {
    unsigned      covering;
    int           collecting_here;
    HV           *cover,
                 *statements,
                 *branches,
                 *conditions,
#if CAN_PROFILE
                 *times,
#endif
                 *modules,
                 *files;
    AV           *ends;
    char          profiling_key[KEY_SZ];
    bool          profiling_key_valid;
    SV           *module,
                 *lastfile;
    int           tid;
    int           replace_ops;
    /* - fix up whatever is broken with module_relative on Windows here */

#if PERL_VERSION > 8
    Perl_ppaddr_t ppaddr[MAXO];
#else
    OP           *(*ppaddr[MAXO])(pTHX);
#endif
} my_cxt_t;

#ifdef USE_ITHREADS
static perl_mutex DC_mutex;
#endif

static HV  *Pending_conditionals,
           *Return_ops;
static int  tid;

START_MY_CXT

#define collecting(criterion) (MY_CXT.covering & (criterion))

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

/* op->op_sibling is deprecated on new perls, but the OpSIBLING macro doesn't
   exist on older perls. We don't need to check for PERL_OP_PARENT here
   because if PERL_OP_PARENT was set, and we needed to check op_moresib,
   we would already have this macro. */
#ifndef OpSIBLING
#define OpSIBLING(o) (0 + (o)->op_sibling)
#endif

static double get_elapsed() {
#ifdef WIN32
    dTHX;
#endif
    struct timeval time;
    double   e;

    gettimeofday(&time, NULL);
    e = time.tv_sec * 1e6 + time.tv_usec;

    return e;
}

static double elapsed() {
    static double p;
           double e, t;

    t = get_elapsed();
    e = t - p;
    p = t;

    return e;
}

#elif defined HAS_TIMES

#ifndef HZ
#  ifdef CLK_TCK
#    define HZ CLK_TCK
#  else
#    define HZ 60
#  endif
#endif

static int cpu() {
#ifdef WIN32
    dTHX;
#endif
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

    return e / HZ;
}

#endif /* HAS_GETTIMEOFDAY */

static char *get_key(OP *o) {
    static struct unique uniq;

    uniq.addr          = o;
    uniq.op            = *o;
    uniq.op.op_ppaddr  = 0;  /* we mess with this field */
    uniq.op.op_targ    = 0;  /* might change            */

    return (char *)&uniq;
}

static char *hex_key(char *key) {
    static char hk[KEY_SZ * 2 + 1];
    unsigned int c;
    for (c = 0; c < KEY_SZ; c++) {
        NDEB(D(L, "%d of %d, <%02X> at %p\n",
               c, KEY_SZ, (unsigned char)key[c], hk + c * 2));
        sprintf(hk + c * 2, "%02X", (unsigned char)key[c]);
    }
    hk[c * 2] = 0;
    return hk;
}

static void set_firsts_if_needed(pTHX) {
    SV *init = (SV *)get_cv("Devel::Cover::first_init", 0);
    SV *end  = (SV *)get_cv("Devel::Cover::first_end",  0);
    NDEB(svdump(end));
    if (PL_initav && av_len(PL_initav) >= 0)
    {
        SV **cv = av_fetch(PL_initav, 0, 0);
        if (*cv != init) {
            av_unshift(PL_initav, 1);
            av_store(PL_initav, 0, init);
        }
    }
    if (PL_endav && av_len(PL_endav) >= 0) {
        SV **cv = av_fetch(PL_endav, 0, 0);
        if (*cv != end) {
            av_unshift(PL_endav, 1);
            av_store(PL_endav, 0, end);
        }
    }
}

static int check_if_collecting(pTHX_ COP *cop) {
    dMY_CXT;

#if !NO_TAINT_SUPPORT
    int tainted = PL_tainted;
#endif
    char *file = CopFILE(cop);
    int in_re_eval = strnEQ(file, "(reeval ", 8);
    NDEB(D(L, "check_if_collecting at: %s:%ld\n", file, CopLINE(cop)));
    if (file && strNE(SvPV_nolen(MY_CXT.lastfile), file)) {
        int found = 0;
        if (MY_CXT.files) {
            SV **f = hv_fetch(MY_CXT.files, file, strlen(file), 0);
            if (f) {
                MY_CXT.collecting_here = SvIV(*f);
                found = 1;
                NDEB(D(L, "File: %s:%ld [%d]\n",
                          file, CopLINE(cop), MY_CXT.collecting_here));
            }
        }

        if (!found && MY_CXT.replace_ops && !in_re_eval) {
            dSP;
            int count;
            SV *rv;

            ENTER;
            SAVETMPS;

            PUSHMARK(SP);
            XPUSHs(sv_2mortal(newSVpv(file, 0)));
            PUTBACK;

            count = call_pv("Devel::Cover::use_file", G_SCALAR);

            SPAGAIN;

            if (count != 1)
                croak("use_file returned %d values\n", count);

            rv = POPs;
            MY_CXT.collecting_here = SvTRUE(rv) ? 1 : 0;

            NDEB(D(L, "-- %s - %d\n", file, MY_CXT.collecting_here));

            PUTBACK;
            FREETMPS;
            LEAVE;
        }

        sv_setpv(MY_CXT.lastfile, file);
    }
    NDEB(D(L, "%s - %d\n",
              SvPV_nolen(MY_CXT.lastfile), MY_CXT.collecting_here));

#if PERL_VERSION > 6
    if (SvTRUE(MY_CXT.module)) {
        STRLEN mlen,
               flen = strlen(file);
        char  *m    = SvPV(MY_CXT.module, mlen);
        if (flen >= mlen && strnEQ(m, file + flen - mlen, mlen)) {
            SV **dir = hv_fetch(MY_CXT.modules, file, strlen(file), 1);
            if (!SvROK(*dir)) {
                SV *cwd = newSV(0);
                AV *d   = newAV();
                *dir = newRV_inc((SV*) d);
                av_push(d, newSVsv(MY_CXT.module));
                if (getcwd_sv(cwd)) {
                    av_push(d, newSVsv(cwd));
                    NDEB(D(L, "require %s as %s from %s\n",
                              m, file, SvPV_nolen(cwd)));
                }
            }
        }
        sv_setpv(MY_CXT.module, "");
        set_firsts_if_needed(aTHX);
    }
#endif

#if !NO_TAINT_SUPPORT
    PL_tainted = tainted;
#endif
    return MY_CXT.collecting_here;
}

#if CAN_PROFILE

static void cover_time(pTHX)
{
    dMY_CXT;
    SV **count;
    NV   c;

    if (collecting(Time)) {
        /*
         * Profiling information is stored against MY_CXT.profiling_key,
         * the key for the op we have just run.
         */

        NDEB(D(L, "Cop at %p, op at %p\n", PL_curcop, PL_op));

        if (MY_CXT.profiling_key_valid) {
            count = hv_fetch(MY_CXT.times, MY_CXT.profiling_key, KEY_SZ, 1);
            c     = (SvTRUE(*count) ? SvNV(*count) : 0) +
#if defined HAS_GETTIMEOFDAY
                    elapsed();
#else
                    cpu();
#endif
            sv_setnv(*count, c);
        }
        if (PL_op) {
            memcpy(MY_CXT.profiling_key, get_key(PL_op), KEY_SZ);
            MY_CXT.profiling_key_valid = 1;
        } else {
            MY_CXT.profiling_key_valid = 0;
        }
    }
}

#endif

static int collecting_here(pTHX) {
    dMY_CXT;

    if (MY_CXT.collecting_here) return 1;

#if CAN_PROFILE
    cover_time(aTHX);
    MY_CXT.profiling_key_valid = 0;
#endif

    NDEB(D(L, "op %p is %s\n", PL_op, OP_NAME(PL_op)));
    if (hv_exists(Return_ops, get_key(PL_op), KEY_SZ))
        return MY_CXT.collecting_here = 1;
    else
        return 0;
}

static void store_return(pTHX) {
    dMY_CXT;

    /*
     * If we are jumping somewhere we might not be collecting
     * coverage there, so store where we will be coming back to
     * so we can turn on coverage straight away.  We need to
     * store more than one return op because a non collecting
     * sub may call back to a collecting sub.
     */

    if (MY_CXT.collecting_here && PL_op->op_next) {
        (void)hv_fetch(Return_ops, get_key(PL_op->op_next), KEY_SZ, 1);
        NDEB(D(L, "adding return op %p\n", PL_op->op_next));
    }
}

static void store_module(pTHX) {
    dMY_CXT;
    dSP;

#if PERL_VERSION > 8
    SvSetSV_nosteal(MY_CXT.module, (SV*)newSVpv(SvPV_nolen(TOPs), 0));
    NDEB(D(L, "require %s\n", SvPV_nolen(MY_CXT.module)));
#endif
}

static void call_report(pTHX) {
    dSP;
    PUSHMARK(SP);
    call_pv("Devel::Cover::report", G_VOID|G_DISCARD|G_EVAL);
    SPAGAIN;
}

static void cover_statement(pTHX_ OP *op) {
    dMY_CXT;

    char *ch;
    SV  **count;
    IV    c;

    if (!collecting(Statement)) return;

    ch    = get_key(op);
    count = hv_fetch(MY_CXT.statements, ch, KEY_SZ, 1);
    c     = SvTRUE(*count) ? SvIV(*count) + 1 : 1;

    NDEB(D(L, "Statement: %s:%ld\n", CopFILE(cCOPx(op)), CopLINE(cCOPx(op))));

    sv_setiv(*count, c);
    NDEB(op_dump(op));
}

static void cover_current_statement(pTHX) {
#if CAN_PROFILE
    cover_time(aTHX);
#endif

    cover_statement(aTHX_ PL_op);
}

static void add_branch(pTHX_ OP *op, int br) {
    dMY_CXT;

    AV  *branches;
    SV **count;
    int  c;
    SV **tmp = hv_fetch(MY_CXT.branches, get_key(op), KEY_SZ, 1);

    if (SvROK(*tmp)) {
        branches = (AV *) SvRV(*tmp);
    } else {
        *tmp = newRV_inc((SV*) (branches = newAV()));
        av_unshift(branches, 2);
    }

    count = av_fetch(branches, br, 1);
    c     = SvTRUE(*count) ? SvIV(*count) + 1 : 1;
    sv_setiv(*count, c);
    NDEB(D(L, "Adding branch making %d at %p\n", c, op));
}

static AV *get_conditional_array(pTHX_ OP *op) {
    dMY_CXT;

    AV  *conds;
    SV **cref = hv_fetch(MY_CXT.conditions, get_key(op), KEY_SZ, 1);

    if (SvROK(*cref))
        conds = (AV *) SvRV(*cref);
    else
        *cref = newRV_inc((SV*) (conds = newAV()));

    return conds;
}

static void set_conditional(pTHX_ OP *op, int cond, int value) {
    /*
     * The conditional array comprises six elements:
     *
     * 0 - 1 iff we are in an xor and the first operand was true
     * 1 - not short circuited - second operand is false
     * 2 - not short circuited - second operand is true
     * 3 - short circuited, or for xor second operand is false
     * 4 - for xor second operand is true
     * 5 - 1 iff we are in void context
     */

    SV **count = av_fetch(get_conditional_array(aTHX_ op), cond, 1);
    sv_setiv(*count, value);
    NDEB(D(L, "Setting %d conditional to %d at %p\n", cond, value, op));
}

static void add_conditional(pTHX_ OP *op, int cond) {
    SV **count = av_fetch(get_conditional_array(aTHX_ op), cond, 1);
    int  c     = SvTRUE(*count) ? SvIV(*count) + 1 : 1;
    sv_setiv(*count, c);
    NDEB(D(L, "Adding %d conditional making %d at %p\n", cond, c, op));
}

#ifdef USE_ITHREADS
static AV *get_conds(pTHX_ AV *conds) {
    dMY_CXT;

    AV    *thrconds;
    HV    *threads;
    SV    *tid,
         **cref;
    char  *t;

    if (av_exists(conds, 2)) {
        SV **cref = av_fetch(conds, 2, 0);
        threads = (HV *) *cref;
    } else {
        threads = newHV();
        HvSHAREKEYS_off(threads);
        av_store(conds, 2, (SV *)threads);
    }

    tid = newSViv(MY_CXT.tid);

    t = SvPV_nolen(tid);
    cref = hv_fetch(threads, t, strlen(t), 1);

    if (SvROK(*cref))
        thrconds = (AV *)SvRV(*cref);
    else
        *cref = newRV_inc((SV*) (thrconds = newAV()));

    return thrconds;
}
#endif

static void add_condition(pTHX_ SV *cond_ref, int value) {
    int   final       = !value;
    AV   *conds       = (AV *)                 SvRV(cond_ref);
    OP   *next        = INT2PTR(OP *,          SvIV(*av_fetch(conds, 0, 0)));
    OP *(*addr)(pTHX) = INT2PTR(OP *(*)(pTHX), SvIV(*av_fetch(conds, 1, 0)));
    I32   i;

    if (!final && next != PL_op)
        croak("next (%p) does not match PL_op (%p)", next, PL_op);

#ifdef USE_ITHREADS
    i = 0;
    conds = get_conds(aTHX_ conds);
#else
    i = 2;
#endif
    NDEB(D(L, "Looking through %d conditionals at %p\n",
           av_len(conds) - 1, PL_op));
    for (; i <= av_len(conds); i++) {
        OP  *op    = INT2PTR(OP *, SvIV(*av_fetch(conds, i, 0)));
        SV **count = av_fetch(get_conditional_array(aTHX_ op), 0, 1);
        int  type  = SvTRUE(*count) ? SvIV(*count) : 0;
        sv_setiv(*count, 0);

        /* Check if we have come from an xor with a true first op */
        if (final)     value  = 1;
        if (type == 1) value += 2;

        NDEB(D(L, "Found %p: %d, %d\n", op, type, value));
        add_conditional(aTHX_ op, value);
    }

#ifdef USE_ITHREADS
    i = -1;
#else
    i = 1;
#endif
    while (av_len(conds) > i) av_pop(conds);

    NDEB(svdump(conds));
    NDEB(D(L, "addr is %p, next is %p, PL_op is %p, length is %d final is %d\n",
              addr, next, PL_op, av_len(conds), final));
    if (!final) next->op_ppaddr = addr;
}

static void dump_conditions(pTHX) {
    HE *e;

    MUTEX_LOCK(&DC_mutex);
    hv_iterinit(Pending_conditionals);
    PDEB(D(L, "Pending_conditionals:\n"));

    while ((e = hv_iternext(Pending_conditionals))) {
        I32   len;
        char *key         = hv_iterkey(e, &len);
        SV   *cond_ref    = hv_iterval(Pending_conditionals, e);
        AV   *conds       = (AV *)                 SvRV(cond_ref);
        OP   *next        = INT2PTR(OP *,          SvIV(*av_fetch(conds, 0,0)));
        OP *(*addr)(pTHX) = INT2PTR(OP *(*)(pTHX), SvIV(*av_fetch(conds, 1,0)));
        I32   i;

#ifdef USE_ITHREADS
        i = 0;  /* TODO - this can't be right */
        conds = get_conds(aTHX_ conds);
#else
        i = 2;
#endif

        PDEB(D(L, "  %s: op %p, next %p (%ld)\n",
               hex_key(key), next, addr, (long)av_len(conds) - 1));

        for (; i <= av_len(conds); i++) {
            OP  *op    = INT2PTR(OP *, SvIV(*av_fetch(conds, i, 0)));
            SV **count = av_fetch(get_conditional_array(aTHX_ op), 0, 1);
            int  type  = SvTRUE(*count) ? SvIV(*count) : 0;
            sv_setiv(*count, 0);

            PDEB(D(L, "    %2d: %p, %d\n", i - 2, op, type));
        }
    }
    MUTEX_UNLOCK(&DC_mutex);
}

#if PERL_VERSION > 18
/* For if ($a || $b) and unless ($a && $b), rpeep skips past a few
 * logops and messes with Devel::Cover.
 *
 * This function will find the skipped op if there is one
 */
static OP *find_skipped_conditional(pTHX_ OP *o) {
    OP *right,
       *next;

    if (o->op_type != OP_OR && o->op_type != OP_AND)
        return NULL;

    /* Get to the end of the "a || b || c" block */
    right = OpSIBLING(cLOGOP->op_first);
    while (right && OpSIBLING(cLOGOPx(right)))
        right = OpSIBLING(cLOGOPx(right));

    if (!right)
        return NULL;

    next = right->op_next;
    while (next && next->op_type == OP_NULL)
        next = next->op_next;

    if (!next)
        return NULL;

    if (o == next)
        return NULL;

    if (next->op_type != OP_OR && next->op_type != OP_AND)
        return NULL;

    /* if ($a || $b) or unless ($a && $b) */
    if (o->op_type == next->op_type)
        return NULL;

    if ((next->op_flags & OPf_WANT) != OPf_WANT_VOID)
        return NULL;

    if (!cLOGOPx(next)->op_other || !o->op_next)
        return NULL;

    if (cLOGOPx(next)->op_other != o->op_next)
        return NULL;

    return next;
}
#endif

/* NOTE: caller must protect get_condition calls by locking DC_mutex */

static OP *get_condition(pTHX) {
    SV **pc = hv_fetch(Pending_conditionals, get_key(PL_op), KEY_SZ, 0);

    if (pc && SvROK(*pc)) {
        dSP;
        NDEB(D(L, "get_condition from %p, %p: %p (%s)\n",
                  PL_op, (void *)PL_op->op_targ, pc, hex_key(get_key(PL_op))));
        /* dump_conditions(aTHX); */
        NDEB(svdump(Pending_conditionals));
        add_condition(aTHX_ *pc, SvTRUE(TOPs) ? 2 : 1);
    } else {
        PDEB(D(L, "All is lost, I know not where to go from %p, %p: %p (%s)\n",
                  PL_op, (void *)PL_op->op_targ, pc, hex_key(get_key(PL_op))));
        dump_conditions(aTHX);
        NDEB(svdump(Pending_conditionals));
        /* croak("urgh"); */
        exit(1);
    }

    return PL_op;
}

static void finalise_conditions(pTHX) {
    /*
     * Our algorithm for conditions relies on ending up at a particular
     * op which we use to call get_condition().  It's possible that we
     * never get to that op; for example we might return out of a sub.
     * This causes us to lose coverage information.
     *
     * This function is called after the program has been run in order
     * to collect that lost information.
     */

    HE *e;

    NDEB(D(L, "finalise_conditions\n"));
    /* dump_conditions(aTHX); */
    NDEB(svdump(Pending_conditionals));

    MUTEX_LOCK(&DC_mutex);
    hv_iterinit(Pending_conditionals);

    while ((e = hv_iternext(Pending_conditionals)))
        add_condition(aTHX_ hv_iterval(Pending_conditionals, e), 0);
    MUTEX_UNLOCK(&DC_mutex);
}

static void cover_cond(pTHX)
{
    dMY_CXT;
    if (collecting(Branch)) {
        dSP;
        int val = SvTRUE(TOPs);
        add_branch(aTHX_ PL_op, !val);
    }
}

static void cover_logop(pTHX) {
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
     * the op we are messing with, the second element of which is the
     * op_ppaddr we overwrote, and the subsequent elements are the ops
     * about which we are collecting the condition coverage information.
     * Note that an op may be collecting condition coverage information
     * about a number of conditions.
     */

    dMY_CXT;

    NDEB(D(L, "logop() at %p\n", PL_op));
    NDEB(op_dump(PL_op));

    if (!collecting(Condition))
        return;

    if (cLOGOP->op_first->op_type == OP_ITER) {
        /* loop - ignore it for now*/
    } else {
        dSP;

        int left_val     = SvTRUE(TOPs);
#if PERL_VERSION > 8
        int left_val_def = SvOK(TOPs);
#endif
        /* We don't count X= as void context because we care about the value
         * of the RHS. */
        int void_context = GIMME_V == G_VOID &&
#if PERL_VERSION > 8
                           PL_op->op_type != OP_DORASSIGN &&
#endif
                           PL_op->op_type != OP_ANDASSIGN &&
                           PL_op->op_type != OP_ORASSIGN;
        NDEB(D(L, "left_val: %d, void_context: %d at %p\n",
                  left_val, void_context, PL_op));
        NDEB(op_dump(PL_op));

        set_conditional(aTHX_ PL_op, 5, void_context);

        if ((PL_op->op_type == OP_AND       &&  left_val)     ||
            (PL_op->op_type == OP_ANDASSIGN &&  left_val)     ||
            (PL_op->op_type == OP_OR        && !left_val)     ||
            (PL_op->op_type == OP_ORASSIGN  && !left_val)     ||
#if PERL_VERSION > 8
            (PL_op->op_type == OP_DOR       && !left_val_def) ||
            (PL_op->op_type == OP_DORASSIGN && !left_val_def) ||
#endif
            (PL_op->op_type == OP_XOR)) {
            /* no short circuit */

            OP *right = OpSIBLING(cLOGOP->op_first);

            NDEB(op_dump(right));

            if (void_context                ||
                right->op_type == OP_NEXT   ||
                right->op_type == OP_LAST   ||
                right->op_type == OP_REDO   ||
                right->op_type == OP_GOTO   ||
                right->op_type == OP_RETURN ||
                right->op_type == OP_DIE) {
                /*
                 * If we are in void context, or the right side of the op is a
                 * branch, we don't care what its value is - it won't be
                 * returning one.  We're just glad to be here, so we chalk up
                 * success.
                 */

                NDEB(D(L, "Add conditional 2\n"));
                add_conditional(aTHX_ PL_op, 2);
            } else {
                char *ch;
                AV   *conds;
                SV  **cref,
                     *cond;
                OP   *next;

                if (PL_op->op_type == OP_XOR && left_val) {
                    /*
                     * This is an xor.  It does not short circuit.  We
                     * have just executed the first op.  When we get to
                     * next we will have already done the xor, so we can
                     * work out what the value of the second op was.
                     *
                     * We set a flag in the first element of the array
                     * to say that we had a true value from the first
                     * op.
                     */

                    set_conditional(aTHX_ PL_op, 0, 1);
                }

#if PERL_VERSION > 14
                NDEB(D(L, "Getting next\n"));
                next = (PL_op->op_type == OP_XOR)
                    ? PL_op->op_next
                    : right->op_next;
#else
                next = PL_op->op_next;
#endif
                if (!next) return;  /* in fold_constants */
                NDEB(op_dump(PL_op));
                NDEB(op_dump(next));

                ch   = get_key(next);
                MUTEX_LOCK(&DC_mutex);
                cref = hv_fetch(Pending_conditionals, ch, KEY_SZ, 1);

                if (SvROK(*cref))
                    conds = (AV *)SvRV(*cref);
                else
                    *cref = newRV_inc((SV*) (conds = newAV()));

                if (av_len(conds) < 0) {
                    av_push(conds, newSViv(PTR2IV(next)));
                    av_push(conds, newSViv(PTR2IV(next->op_ppaddr)));
                }

#ifdef USE_ITHREADS
                conds = get_conds(aTHX_ conds);
#endif

                cond = newSViv(PTR2IV(PL_op));
                av_push(conds, cond);

                NDEB(D(L, "Adding conditional %p (%s) "
                          "making %d at %p (%s), ppaddr: %p\n",
                       next, PL_op_name[next->op_targ], av_len(conds) - 1,
                       PL_op, hex_key(ch), next->op_ppaddr));
                /* dump_conditions(aTHX); */
                NDEB(svdump(Pending_conditionals));
                NDEB(op_dump(PL_op));
                NDEB(op_dump(next));

                next->op_ppaddr = get_condition;
                MUTEX_UNLOCK(&DC_mutex);
            }
        } else {
            /* short circuit */
#if PERL_VERSION > 14
            OP *up = OpSIBLING(cLOGOP->op_first)->op_next;
#if PERL_VERSION > 18
            OP *skipped;
#endif

            while (up && up->op_type == PL_op->op_type) {
                NDEB(D(L, "Considering adding %p (%s) -> (%p) "
                                        "from %p (%s) -> (%p)\n",
                       up, PL_op_name[up->op_type], up->op_next,
                       PL_op, PL_op_name[PL_op->op_type], PL_op->op_next));
                add_conditional(aTHX_ up, 3);
                if (up->op_next == PL_op->op_next)
                    break;
                up = OpSIBLING(cLOGOPx(up)->op_first)->op_next;
            }
#endif
            add_conditional(aTHX_ PL_op, 3);

#if PERL_VERSION > 18
            skipped = PL_op;
            while (skipped = find_skipped_conditional(aTHX_ skipped))
                add_conditional(aTHX_ skipped, 2); /* Should this ever be 1? */
#endif
        }
    }
}

#if PERL_VERSION > 16
/* A sequence of variable declarations may have been optimized
 * to a single OP_PADRANGE. The original sequence may span multiple lines,
 * but only the first line has been marked as covered for now.
 * Mark other OP_NEXTSTATE inside the original sequence of statements.
 */
static void cover_padrange(pTHX) {
    dMY_CXT;
    if (!collecting(Statement)) return;
    OP *next = PL_op->op_next;
    OP *orig = OpSIBLING(PL_op);

    /* Ignore padrange preparing subroutine call. */
    while (orig && orig != next) {
	if (orig->op_type == OP_ENTERSUB) return;
	orig = orig->op_next;
    }
    orig = OpSIBLING(PL_op);
    while (orig && orig != next) {
	if (orig->op_type == OP_NEXTSTATE) {
	    cover_statement(aTHX_ orig);
	}
	orig = orig->op_next;
    }
}

static OP *dc_padrange(pTHX) {
    dMY_CXT;
    check_if_collecting(aTHX_ PL_curcop);
    NDEB(D(L, "dc_padrange() at %p (%d)\n", PL_op, collecting_here(aTHX)));
    if (MY_CXT.covering) cover_padrange(aTHX);
    return MY_CXT.ppaddr[OP_PADRANGE](aTHX);
}
#endif

static OP *dc_nextstate(pTHX) {
    dMY_CXT;
    NDEB(D(L, "dc_nextstate() at %p (%d)\n", PL_op, collecting_here(aTHX)));
    if (MY_CXT.covering) check_if_collecting(aTHX_ cCOP);
    if (collecting_here(aTHX)) cover_current_statement(aTHX);
    return MY_CXT.ppaddr[OP_NEXTSTATE](aTHX);
}

#if PERL_VERSION <= 10
static OP *dc_setstate(pTHX) {
    dMY_CXT;
    NDEB(D(L, "dc_setstate() at %p (%d)\n", PL_op, collecting_here(aTHX)));
    if (MY_CXT.covering) check_if_collecting(aTHX_ cCOP);
    if (collecting_here(aTHX)) cover_current_statement(aTHX);
    return MY_CXT.ppaddr[OP_SETSTATE](aTHX);
}
#endif

static OP *dc_dbstate(pTHX) {
    dMY_CXT;
    NDEB(D(L, "dc_dbstate() at %p (%d)\n", PL_op, collecting_here(aTHX)));
    if (MY_CXT.covering) check_if_collecting(aTHX_ cCOP);
    if (collecting_here(aTHX)) cover_current_statement(aTHX);
    return MY_CXT.ppaddr[OP_DBSTATE](aTHX);
}

static OP *dc_entersub(pTHX) {
    dMY_CXT;
    NDEB(D(L, "dc_entersub() at %p (%d)\n", PL_op, collecting_here(aTHX)));
    if (MY_CXT.covering) store_return(aTHX);
    return MY_CXT.ppaddr[OP_ENTERSUB](aTHX);
}

static OP *dc_cond_expr(pTHX) {
    dMY_CXT;
    check_if_collecting(aTHX_ PL_curcop);
    NDEB(D(L, "dc_cond_expr() at %p (%d)\n", PL_op, collecting_here(aTHX)));
    if (MY_CXT.covering && collecting_here(aTHX)) cover_cond(aTHX);
    return MY_CXT.ppaddr[OP_COND_EXPR](aTHX);
}

static OP *dc_and(pTHX) {
    dMY_CXT;
    NDEB(D(L, "dc_and() at %p (%d)\n", PL_op, collecting_here(aTHX)));
    check_if_collecting(aTHX_ PL_curcop);
    NDEB(D(L, "dc_and() at %p (%d)\n", PL_curcop, collecting_here(aTHX)));
    NDEB(D(L, "PL_curcop: %s:%d\n", CopFILE(PL_curcop), CopLINE(PL_curcop)));
    if (MY_CXT.covering && collecting_here(aTHX)) cover_logop(aTHX);
    return MY_CXT.ppaddr[OP_AND](aTHX);
}

static OP *dc_andassign(pTHX) {
    dMY_CXT;
    check_if_collecting(aTHX_ PL_curcop);
    NDEB(D(L, "dc_andassign() at %p (%d)\n", PL_op, collecting_here(aTHX)));
    if (MY_CXT.covering && collecting_here(aTHX)) cover_logop(aTHX);
    return MY_CXT.ppaddr[OP_ANDASSIGN](aTHX);
}

static OP *dc_or(pTHX) {
    dMY_CXT;
    check_if_collecting(aTHX_ PL_curcop);
    NDEB(D(L, "dc_or() at %p (%d)\n", PL_op, collecting_here(aTHX)));
    if (MY_CXT.covering && collecting_here(aTHX)) cover_logop(aTHX);
    return MY_CXT.ppaddr[OP_OR](aTHX);
}

static OP *dc_orassign(pTHX) {
    dMY_CXT;
    check_if_collecting(aTHX_ PL_curcop);
    NDEB(D(L, "dc_orassign() at %p (%d)\n", PL_op, collecting_here(aTHX)));
    if (MY_CXT.covering && collecting_here(aTHX)) cover_logop(aTHX);
    return MY_CXT.ppaddr[OP_ORASSIGN](aTHX);
}

#if PERL_VERSION > 8
static OP *dc_dor(pTHX) {
    dMY_CXT;
    check_if_collecting(aTHX_ PL_curcop);
    NDEB(D(L, "dc_dor() at %p (%d)\n", PL_op, collecting_here(aTHX)));
    if (MY_CXT.covering && collecting_here(aTHX)) cover_logop(aTHX);
    return MY_CXT.ppaddr[OP_DOR](aTHX);
}

static OP *dc_dorassign(pTHX) {
    dMY_CXT;
    check_if_collecting(aTHX_ PL_curcop);
    NDEB(D(L, "dc_dorassign() at %p (%d)\n", PL_op, collecting_here(aTHX)));
    if (MY_CXT.covering && collecting_here(aTHX)) cover_logop(aTHX);
    return MY_CXT.ppaddr[OP_DORASSIGN](aTHX);
}
#endif

OP *dc_xor(pTHX) {
    dMY_CXT;
    check_if_collecting(aTHX_ PL_curcop);
    NDEB(D(L, "dc_xor() at %p (%d)\n", PL_op, collecting_here(aTHX)));
    if (MY_CXT.covering && collecting_here(aTHX)) cover_logop(aTHX);
    return MY_CXT.ppaddr[OP_XOR](aTHX);
}

static OP *dc_require(pTHX) {
    dMY_CXT;
    NDEB(D(L, "dc_require() at %p (%d)\n", PL_op, collecting_here(aTHX)));
    if (MY_CXT.covering && collecting_here(aTHX)) store_module(aTHX);
    return MY_CXT.ppaddr[OP_REQUIRE](aTHX);
}

static OP *dc_exec(pTHX) {
    dMY_CXT;
    NDEB(D(L, "dc_exec() at %p (%d)\n", PL_op, collecting_here(aTHX)));
    if (MY_CXT.covering && collecting_here(aTHX)) call_report(aTHX);
    return MY_CXT.ppaddr[OP_EXEC](aTHX);
}

static void replace_ops (pTHX) {
    dMY_CXT;
    int i;
    NDEB(D(L, "initialising replace_ops\n"));
    for (i = 0; i < MAXO; i++)
        MY_CXT.ppaddr[i] = PL_ppaddr[i];

    PL_ppaddr[OP_NEXTSTATE] = dc_nextstate;
#if PERL_VERSION <= 10
    PL_ppaddr[OP_SETSTATE]  = dc_setstate;
#endif
    PL_ppaddr[OP_DBSTATE]   = dc_dbstate;
    PL_ppaddr[OP_ENTERSUB]  = dc_entersub;
#if PERL_VERSION > 16
    PL_ppaddr[OP_PADRANGE]  = dc_padrange;
#endif
    PL_ppaddr[OP_COND_EXPR] = dc_cond_expr;
    PL_ppaddr[OP_AND]       = dc_and;
    PL_ppaddr[OP_ANDASSIGN] = dc_andassign;
    PL_ppaddr[OP_OR]        = dc_or;
    PL_ppaddr[OP_ORASSIGN]  = dc_orassign;
#if PERL_VERSION > 8
    PL_ppaddr[OP_DOR]       = dc_dor;
    PL_ppaddr[OP_DORASSIGN] = dc_dorassign;
#endif
    PL_ppaddr[OP_XOR]       = dc_xor;
    PL_ppaddr[OP_REQUIRE]   = dc_require;
    PL_ppaddr[OP_EXEC]      = dc_exec;
}

static void initialise(pTHX) {
    dMY_CXT;

    NDEB(D(L, "initialising\n"));

    MUTEX_LOCK(&DC_mutex);
    if (!Pending_conditionals) {
        Pending_conditionals = newHV();
#ifdef USE_ITHREADS
        HvSHAREKEYS_off(Pending_conditionals);
#endif
    }
    if (!Return_ops) {
        Return_ops = newHV();
#ifdef USE_ITHREADS
        HvSHAREKEYS_off(Return_ops);
#endif
    }
    MUTEX_UNLOCK(&DC_mutex);

    MY_CXT.collecting_here = 1;

    if (!MY_CXT.covering) {
        /* TODO - this probably leaks all over the place */

        SV **tmp;

        MY_CXT.cover      = newHV();
#ifdef USE_ITHREADS
        HvSHAREKEYS_off(MY_CXT.cover);
#endif

        tmp               = hv_fetch(MY_CXT.cover, "statement", 9, 1);
        MY_CXT.statements = newHV();
        *tmp              = newRV_inc((SV*) MY_CXT.statements);

        tmp               = hv_fetch(MY_CXT.cover, "branch",    6, 1);
        MY_CXT.branches   = newHV();
        *tmp              = newRV_inc((SV*) MY_CXT.branches);

        tmp               = hv_fetch(MY_CXT.cover, "condition", 9, 1);
        MY_CXT.conditions = newHV();
        *tmp              = newRV_inc((SV*) MY_CXT.conditions);

#if CAN_PROFILE
        tmp               = hv_fetch(MY_CXT.cover, "time",      4, 1);
        MY_CXT.times      = newHV();
        *tmp              = newRV_inc((SV*) MY_CXT.times);
#endif

        tmp               = hv_fetch(MY_CXT.cover, "module",    6, 1);
        MY_CXT.modules    = newHV();
        *tmp              = newRV_inc((SV*) MY_CXT.modules);

        MY_CXT.files      = get_hv("Devel::Cover::Files", FALSE);

#ifdef USE_ITHREADS
        HvSHAREKEYS_off(MY_CXT.statements);
        HvSHAREKEYS_off(MY_CXT.branches);
        HvSHAREKEYS_off(MY_CXT.conditions);
#if CAN_PROFILE
        HvSHAREKEYS_off(MY_CXT.times);
#endif
        HvSHAREKEYS_off(MY_CXT.modules);
#endif

        MY_CXT.profiling_key_valid = 0;
        MY_CXT.module              = newSVpv("", 0);
        MY_CXT.lastfile            = newSVpvn("", 1);
        MY_CXT.covering            = All;
        MY_CXT.tid                 = tid++;

        MY_CXT.replace_ops = SvTRUE(get_sv("Devel::Cover::Replace_ops", FALSE));
        NDEB(D(L, "running with Replace_ops as %d\n", MY_CXT.replace_ops));
    }
}

static int runops_cover(pTHX) {
    dMY_CXT;

    NDEB(D(L, "entering runops_cover\n"));

#if defined HAS_GETTIMEOFDAY
    elapsed();
#elif defined HAS_TIMES
    cpu();
#endif

    for (;;) {
        NDEB(D(L, "running func %p from %p (%s)\n",
               PL_op->op_ppaddr, PL_op, OP_NAME(PL_op)));

        if (!MY_CXT.covering)
            goto call_fptr;

        /* Nothing to collect when we've hijacked the ppaddr */
        {
            int hijacked;
            MUTEX_LOCK(&DC_mutex);
            hijacked = PL_op->op_ppaddr == get_condition;
            MUTEX_UNLOCK(&DC_mutex);
            if (hijacked)
                goto call_fptr;
        }

        /* Check to see whether we are interested in this file */

        if (PL_op->op_type == OP_NEXTSTATE)
            check_if_collecting(aTHX_ cCOP);
        else if (PL_op->op_type == OP_ENTERSUB)
            store_return(aTHX);

        if (!collecting_here(aTHX))
            goto call_fptr;

        /*
         * We are about the run the op PL_op, so we'll collect
         * information for it now.
         */

        switch (PL_op->op_type) {
            case OP_NEXTSTATE:
#if PERL_VERSION <= 10
            case OP_SETSTATE:
#endif
            case OP_DBSTATE: {
                cover_current_statement(aTHX);
                break;
            }

#if PERL_VERSION > 16
            case OP_PADRANGE: {
		cover_padrange(aTHX);
		break;
            }
#endif

            case OP_COND_EXPR: {
                cover_cond(aTHX);
                break;
            }

            case OP_AND:
            case OP_ANDASSIGN:
            case OP_OR:
            case OP_ORASSIGN:
#if PERL_VERSION > 8
            case OP_DOR:
            case OP_DORASSIGN:
#endif
            case OP_XOR: {
                cover_logop(aTHX);
                break;
            }

            case OP_REQUIRE: {
                store_module(aTHX);
                break;
            }

            case OP_EXEC: {
                call_report(aTHX);
                break;
            }

            default:
                ;  /* IBM's xlC compiler on AIX is very picky */
        }

        call_fptr:
        if (!(PL_op = PL_op->op_ppaddr(aTHX)))
            break;

        PERL_ASYNC_CHECK();
    }

#if CAN_PROFILE
    cover_time(aTHX);
#endif

    MY_CXT.collecting_here = 1;

    NDEB(D(L, "exiting runops_cover\n"));

    TAINT_NOT;
    return 0;
}

static int runops_orig(pTHX) {
    NDEB(D(L, "entering runops_orig\n"));

    while ((PL_op = PL_op->op_ppaddr(aTHX))) {
        PERL_ASYNC_CHECK();
    }

    NDEB(D(L, "exiting runops_orig\n"));

    TAINT_NOT;
    return 0;
}

static int runops_trace(pTHX) {
    PDEB(D(L, "entering runops_trace\n"));

    for (;;) {
        PDEB(D(L, "running func %p from %p (%s)\n",
               PL_op->op_ppaddr, PL_op, OP_NAME(PL_op)));

        if (!(PL_op = PL_op->op_ppaddr(aTHX)))
            break;

        PERL_ASYNC_CHECK();
    }

    PDEB(D(L, "exiting runops_trace\n"));

    TAINT_NOT;
    return 0;
}

static char *svclassnames[] = {
    "B::NULL",
    "B::IV",
    "B::NV",
    "B::RV",
    "B::PV",
    "B::PVIV",
    "B::PVNV",
    "B::PVMG",
    "B::BM",
    "B::GV",
    "B::PVLV",
    "B::AV",
    "B::HV",
    "B::CV",
    "B::FM",
    "B::IO",
};

static SV *make_sv_object(pTHX_ SV *arg, SV *sv) {
    IV    iv;
    char *type;

    iv = PTR2IV(sv);
    type = svclassnames[SvTYPE(sv)];
    sv_setiv(newSVrv(arg, type), iv);
    return arg;
}


typedef OP *B__OP;
typedef AV *B__AV;


MODULE = Devel::Cover PACKAGE = Devel::Cover

PROTOTYPES: ENABLE

void
set_criteria(flag)
        unsigned flag
    PREINIT:
        dMY_CXT;
    PPCODE:
        MY_CXT.covering = flag;
        /* fprintf(stderr, "Cover set to %d\n", flag); */
        if (MY_CXT.replace_ops) return;
        PL_runops = MY_CXT.covering ? runops_cover : runops_orig;

void
add_criteria(flag)
        unsigned flag
    PREINIT:
        dMY_CXT;
    PPCODE:
        MY_CXT.covering |= flag;
        if (MY_CXT.replace_ops) return;
        PL_runops = MY_CXT.covering ? runops_cover : runops_orig;

void
remove_criteria(flag)
        unsigned flag
    PREINIT:
        dMY_CXT;
    PPCODE:
        MY_CXT.covering &= ~flag;
        if (MY_CXT.replace_ops) return;
        PL_runops = MY_CXT.covering ? runops_cover : runops_orig;

unsigned
get_criteria()
    PREINIT:
        dMY_CXT;
    CODE:
        RETVAL = MY_CXT.covering;
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
coverage_subroutine()
    CODE:
        RETVAL = Subroutine;
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

double
get_elapsed()
    CODE:
#ifdef HAS_GETTIMEOFDAY
        RETVAL = get_elapsed();
#else
        RETVAL = 0;
#endif
    OUTPUT:
        RETVAL

SV *
coverage(final)
        unsigned final
    PREINIT:
        dMY_CXT;
    CODE:
        NDEB(D(L, "Getting coverage %d\n", final));
        if (final) finalise_conditions(aTHX);
        if (MY_CXT.cover)
            RETVAL = newRV_inc((SV*) MY_CXT.cover);
        else
            RETVAL = &PL_sv_undef;
    OUTPUT:
        RETVAL

SV *
get_key(o)
        B::OP o
    CODE:
        RETVAL = newSV(KEY_SZ + 1);
        sv_setpvn(RETVAL, get_key(o), KEY_SZ);
    OUTPUT:
        RETVAL

void
set_first_init_and_end()
    PPCODE:
        set_firsts_if_needed(aTHX);

void
collect_inits()
    PREINIT:
        dMY_CXT;
    PPCODE:
        int i;
        NDEB(svdump(end));
        if (!MY_CXT.ends) MY_CXT.ends = newAV();
        if (PL_initav)
            for (i = 0; i <= av_len(PL_initav); i++) {
                SV **cv = av_fetch(PL_initav, i, 0);
                SvREFCNT_inc(*cv);
                av_push(MY_CXT.ends, *cv);
            }

void
set_last_end()
    PREINIT:
        dMY_CXT;
    PPCODE:
        int i;
        SV *end = (SV *)get_cv("last_end", 0);
        av_push(PL_endav, end);
        NDEB(svdump(end));
        if (!MY_CXT.ends) MY_CXT.ends = newAV();
        if (PL_endav)
            for (i = 0; i <= av_len(PL_endav); i++) {
                SV **cv = av_fetch(PL_endav, i, 0);
                SvREFCNT_inc(*cv);
                av_push(MY_CXT.ends, *cv);
            }

B::AV
get_ends()
    PREINIT:
        dMY_CXT;
    CODE:
        if (!MY_CXT.ends) MY_CXT.ends = newAV();  /* TODO: how? */
            RETVAL = MY_CXT.ends;
    OUTPUT:
        RETVAL

BOOT:
    {
        MY_CXT_INIT;
#ifdef USE_ITHREADS
        MUTEX_INIT(&DC_mutex);
#endif
        initialise(aTHX);
        if (MY_CXT.replace_ops) {
            replace_ops(aTHX);
#if defined HAS_GETTIMEOFDAY
            elapsed();
#elif defined HAS_TIMES
            cpu();
#endif
            /* PL_runops = runops_trace; */
        } else {
            PL_runops = runops_cover;
        }
#if PERL_VERSION > 6
        PL_savebegin = TRUE;
#endif
    }
