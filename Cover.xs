/*
 * Copyright 2001, Paul Johnson (pjcj@cpan.org)
 *
 * This software is free.  It is licensed under the same terms as Perl itself.
 *
 * The latest version of this software should be available from my homepage:
 * http://www.pjcj.net
 *
 */

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#ifdef PERL_OBJECT
#define CALLOP this->*PL_op
#else
#define CALLOP *PL_op
#endif

static int covering = 1;
HV *hv = 0;

union address   /* Hack, hack, hackety hack. */
{
  char ch[sizeof(PL_op) + 1];
  void *plop;
};

static int
runops_cover(pTHX)
{
    union address addr;
    SV **count;
    IV c;

    if (!hv) hv = newHV();
    addr.ch[sizeof(PL_op)] = '\0';

    while ((PL_op = CALL_FPTR(PL_op->op_ppaddr)(aTHX))) {
        if (covering)
        {
            addr.plop = PL_op;
            count = hv_fetch(hv, addr.ch, sizeof(PL_op), 1);
            c = SvTRUE(*count) ? SvIV(*count) + 1 : 1;
            sv_setiv(*count, c);
        }
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
        covering = flag;

SV *
coverage()
    CODE:
          ST(0) = sv_newmortal();
          if (hv)
               sv_setsv(ST(0), newRV_inc((SV*) hv));
          else
               ST(0) = &PL_sv_undef;

BOOT:
    PL_runops = runops_cover;
