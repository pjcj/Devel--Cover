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

static int covering   = 1,
           profiling  = 1;

static HV *cover_hv   = 0,
          *profile_hv = 0;

union address   /* Hack, hack, hackety hack. */
{
    char ch[sizeof(PL_op) + 1];
    void *plop;
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

static int
elapsed()
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

static int
cpu()
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


static int
runops_cover(pTHX)
{
    union address addr;
    SV **count;
    IV c;

#ifdef HAS_GETTIMEOFDAY
    static COP *cop = 0;
    if (!profile_hv) profile_hv = newHV();
    elapsed();
#endif

    if (!cover_hv) cover_hv = newHV();
    addr.ch[sizeof(PL_op)] = '\0';

    /* fprintf(stderr, "runops_cover\n"); */
    while ((PL_op = CALL_FPTR(PL_op->op_ppaddr)(aTHX)))
    {
        if (covering)
        {
            addr.plop = PL_op;
            count     = hv_fetch(cover_hv, addr.ch, sizeof(PL_op), 1);
            c         = SvTRUE(*count) ? SvIV(*count) + 1 : 1;
            sv_setiv(*count, c);
        }
        if (profiling && PL_curcop != cop)
        {
            addr.plop = cop;
            cop       = PL_curcop;
            count     = hv_fetch(profile_hv, addr.ch, sizeof(PL_op), 1);
            c         = (SvTRUE(*count) ? SvIV(*count) : 0) + elapsed();
            /*
            c         = (SvTRUE(*count) ? SvIV(*count) : 0) +
                        profiling == 1 ? cpu() : elapsed();
            */
            sv_setiv(*count, c);
        }
        PERL_ASYNC_CHECK();
    }

    TAINT_NOT;
    return 0;
}

static int
runops_orig(pTHX)
{
    /* fprintf(stderr, "runops_orig\n"); */
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
set_cover(flag)
        int flag
    PPCODE:
        /* fprintf(stderr, "Cover set to %d\n", flag); */
        PL_runops = ((covering = flag) || profiling)
            ? runops_cover
            : runops_orig;

void
set_profile(flag)
        int flag
    PPCODE:
        /* fprintf(stderr, "Cover set to %d\n", flag); */
        PL_runops = ((profiling = flag) || covering)
            ? runops_cover
            : runops_orig;

SV *
coverage()
    CODE:
          ST(0) = sv_newmortal();
          if (cover_hv)
               sv_setsv(ST(0), newRV_inc((SV*) cover_hv));
          else
               ST(0) = &PL_sv_undef;

SV *
profiles()
    CODE:
          ST(0) = sv_newmortal();
          if (profile_hv)
               sv_setsv(ST(0), newRV_inc((SV*) profile_hv));
          else
               ST(0) = &PL_sv_undef;

BOOT:
    PL_runops = runops_cover;
