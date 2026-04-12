/*
 * Copyright 2001-2026, Paul Johnson (paul@pjcj.net)
 *
 * This software is free.  It is licensed under the same terms as Perl itself.
 *
 * The latest version of this software should be available from my homepage:
 * https://pjcj.net
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

#define CALLOP *PL_op

#define MY_CXT_KEY "Devel::Cover::_guts" XS_VERSION

#define PDEB(a) a
#define NDEB(a) ; /* if change to a, comment defining PERL_NO_GET_CONTEXT */
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

#if defined HAS_GETTIMEOFDAY || defined HAS_TIMES
#define CAN_PROFILE 1
#else
#define CAN_PROFILE 0
#endif

struct unique {         /* Well, we'll be fairly unlucky if it's not */
  OP    *addr;          /* op address                                */
  size_t op_identity;   /* hash of meaningful OP fields              */
  size_t fileinfohash;  /* hashed file location or 0                 */
};

#define KEY_SZ sizeof(struct unique)

/*
 * C-level cache mapping OP * -> statement count.  Avoids the full get_key +
 * hv_fetch path for repeat statement executions (~95% of all hits in a typical
 * program).  Uses open addressing with linear probing, keyed by the raw op
 * pointer.
 *
 * On a cache hit, two checks guard against slab reuse: op_next and the CopFILE
 * pointer.  This is sufficient because cover_current_statement is only called
 * for NEXTSTATE/DBSTATE ops.  op_identity and fileinfohash are stored for key
 * reconstruction at flush time but are not checked on the hot path.
 *
 * Cached counts are flushed into the Perl statements HV when the coverage() XS
 * function is called (i.e. at report time).
 */

typedef struct {
  OP         *addr;         /* key: op address (NULL = empty slot)    */
  OP         *op_next;      /* slab reuse guard: o->op_next at insert */
  const char *cop_file;     /* slab reuse guard: CopFILE at insert    */
  size_t      op_identity;  /* for struct unique key at flush time    */
  size_t      fileinfohash; /* for struct unique key at flush time    */
  IV          stmt_count;   /* accumulated statement count            */
} dc_stmt_slot;

typedef struct {
  dc_stmt_slot *slots;
  size_t        capacity; /* always power of 2                    */
  size_t        count;    /* occupied slots                       */
  size_t        mask;     /* capacity - 1                         */
} dc_stmt_cache;

#define DC_STMT_CACHE_INIT_CAP 1024
#define DC_STMT_CACHE_LOAD_PCT 70

/*
 * C-level cache mapping OP * -> AV * for condition and branch arrays. Avoids
 * the get_key + hv_fetch path on repeat executions.  Unlike the statement
 * cache, no flush is needed: the cached AV pointer IS the authoritative object
 * living in the conditions or branches HV.
 *
 * The same cache serves both condition and branch ops because the two sets are
 * disjoint (logops vs OP_COND_EXPR).
 */

typedef struct {
  OP     *addr;         /* key: op address (NULL = empty slot)    */
  OP     *op_next;      /* slab reuse guard: o->op_next at insert */
  size_t  op_identity;  /* slab reuse guard: hash_op_identity     */
  AV     *av;           /* cached AV pointer                      */
} dc_av_slot;

typedef struct {
  dc_av_slot *slots;
  size_t      capacity; /* always power of 2 */
  size_t      count;    /* occupied slots    */
  size_t      mask;     /* capacity - 1      */
} dc_av_cache;

#define DC_AV_CACHE_INIT_CAP 256
#define DC_AV_CACHE_LOAD_PCT 70

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
  char         *lastfile_ptr;  /* cached CopFILE pointer */
  int           tid;
  int           replace_ops;
  /* - fix up whatever is broken with module_relative on Windows here */

  dc_stmt_cache stmt_cache;
  dc_av_cache   av_cache;
  AV           *deferred_conditionals; /* sort-block conditions
                                        * awaiting resolution */
  Perl_ppaddr_t ppaddr[MAXO];
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

/*
 * op->op_sibling is deprecated on new perls, but the OpSIBLING macro doesn't
 * exist on older perls. We don't need to check for PERL_OP_PARENT here because
 * if PERL_OP_PARENT was set, and we needed to check op_moresib, we would
 * already have this macro.
 */
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

/*
 * https://codereview.stackexchange.com/questions/85556/simple-string-hashing-algorithm-implementation
 * https://en.wikipedia.org/wiki/Fowler%E2%80%93Noll%E2%80%93Vo_hash_function
 * http://www.isthe.com/chongo/tech/comp/fnv/index.html#public_domain
 *
 * FNV hash algorithms and source code have been released into the public
 * domain. The authors of the FNV algorithm took deliberate steps to disclose
 * the algorithm in a public forum soon after it was invented. More than a year
 * passed after this public disclosure and the authors deliberately took no
 * steps to patent the FNV algorithm. Therefore it is safe to say that the FNV
 * authors have no patent claims on the FNV algorithm as published.
 */

/*
 * Fowler/Noll/Vo (FNV) hash function, variant 1a
 * Hash filename bytes and line number directly, avoiding snprintf.
 */
static size_t fnv1a_hash_file_line(const char *file, long line) {
  size_t hash = 0x811c9dc5;
  const unsigned char *p;
  size_t i;
  while (*file) {
    hash ^= (unsigned char)*file++;
    hash *= 0x01000193;
  }
  p = (const unsigned char *)&line;
  for (i = 0; i < sizeof(line); i++) {
    hash ^= p[i];
    hash *= 0x01000193;
  }
  return hash;
}

/*
 * Fast fingerprint of the OP fields that distinguish one op from another at the
 * same address (slab reuse guard).  Replaces copying the full 40-byte OP struct
 * and zeroing two fields.  Only needs to be collision-resistant enough that two
 * unrelated ops sharing an address produce different values; fileinfohash
 * provides a second check for COPs.
 *
 * The old code copied the entire OP struct (40 bytes), then zeroed op_ppaddr
 * (we replace it during instrumentation) and op_targ (can change at runtime).
 * That left 20 meaningful bytes: op_next (8), op_sibling/op_sibparent (8), and
 * the type/flags bitfields (4). This function mixes those same fields into a
 * single size_t.
 *
 * 0x00000100000001B3 is the FNV-1a 64-bit prime.  It is used here as a mixing
 * multiplier rather than as part of a true FNV-1a hash
 * - its sparse-high / dense-low bit pattern spreads input bits well across the
 *   result.
 */
static size_t hash_op_identity(const OP *o) {
  size_t h = (size_t)o->op_next;
  h ^= (size_t)OpSIBLING(o) * 0x00000100000001B3ULL;
  h ^= ((size_t)o->op_type << 16)
     |  ((size_t)o->op_flags << 8)
     |   (size_t)o->op_private;
  h *= 0x00000100000001B3ULL;
  return h;
}

static char *get_key(OP *o) {
  static struct unique uniq;

  uniq.addr        = o;
  uniq.op_identity = hash_op_identity(o);
  if (o->op_type == OP_NEXTSTATE || o->op_type == OP_DBSTATE) {
    /* cop, has file location information */
    uniq.fileinfohash = fnv1a_hash_file_line(
      CopFILE((COP *)o), CopLINE((COP *)o));
  } else {
    /* no file location information available */
    uniq.fileinfohash = 0;
  }

  return (char *)&uniq;
}

static char *hex_key(char *key) {
  static char hk[KEY_SZ * 2 + 1];
  size_t c;
  for (c = 0; c < KEY_SZ; c++) {
    NDEB(D(L, "%zu of %zu, <%02X> at %p\n",
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
  NDEB(D(L, "check_if_collecting at: %s:%ld\n", file, (long)CopLINE(cop)));

  /*
   * Fast path: same CopFILE pointer as last time means same file.  Skip the
   * SV unpack, strcmp, and reeval check.
   */
  if (file != MY_CXT.lastfile_ptr) {
    if (file && strNE(SvPV_nolen(MY_CXT.lastfile), file)) {
      int found = 0;
      if (MY_CXT.files) {
        SV **f = hv_fetch(MY_CXT.files, file, strlen(file), 0);
        if (f) {
          MY_CXT.collecting_here = SvIV(*f);
          found = 1;
          NDEB(D(L, "File: %s:%ld [%d]\n",
                 file, (long)CopLINE(cop), MY_CXT.collecting_here));
        }
      }

      if (!found && MY_CXT.replace_ops
          && !strnEQ(file, "(reeval ", 8)) {
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

    /*
     * Update pointer even when strings match, so a new pointer for the same
     * file gets the fast path next time.
     */
    MY_CXT.lastfile_ptr = file;
  }

  NDEB(D(L, "%s - %d\n", SvPV_nolen(MY_CXT.lastfile), MY_CXT.collecting_here));

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
          NDEB(D(L, "require %s as %s from %s\n", m, file, SvPV_nolen(cwd)));
        }
      }
    }
    sv_setpv(MY_CXT.module, "");
    set_firsts_if_needed(aTHX);
  }

#if !NO_TAINT_SUPPORT
  PL_tainted = tainted;
#endif
  return MY_CXT.collecting_here;
}

static void dc_stmt_cache_init(dc_stmt_cache *c) {
  c->capacity = DC_STMT_CACHE_INIT_CAP;
  c->count    = 0;
  c->mask     = c->capacity - 1;
  Newxz(c->slots, c->capacity, dc_stmt_slot);
}

static void dc_stmt_grow(dc_stmt_cache *c);

/*
 * Look up by address.  Returns the slot if found (caller must check op_next for
 * slab reuse), or NULL if not in the cache.
 */
static dc_stmt_slot *dc_stmt_lookup(dc_stmt_cache *c, OP *addr) {
  size_t idx;
  if (!c->slots) return NULL;
  idx = ((size_t)addr >> 4) & c->mask;
  for (;;) {
    dc_stmt_slot *s = &c->slots[idx];
    if (!s->addr)        return NULL;  /* empty = not found */
    if (s->addr == addr) return s;     /* found             */
    idx = (idx + 1) & c->mask;
  }
}

/*
 * Insert a new entry.  Caller must ensure addr is not already present.  Returns
 * the new slot with stmt_count = 0.
 */
static dc_stmt_slot *dc_stmt_insert(
    dc_stmt_cache *c, OP *addr, OP *op_next, const char *cop_file,
    size_t op_identity, size_t fileinfohash) {
  size_t idx;
  dc_stmt_slot *s;

  if (!c->slots) dc_stmt_cache_init(c);

  /* Grow if above load factor */
  if (c->count * 100 >= c->capacity * DC_STMT_CACHE_LOAD_PCT)
    dc_stmt_grow(c);

  idx = ((size_t)addr >> 4) & c->mask;
  for (;;) {
    s = &c->slots[idx];
    if (!s->addr) break;  /* found empty slot */
    idx = (idx + 1) & c->mask;
  }

  s->addr         = addr;
  s->op_next      = op_next;
  s->cop_file     = cop_file;
  s->op_identity  = op_identity;
  s->fileinfohash = fileinfohash;
  s->stmt_count   = 0;
  c->count++;
  return s;
}

static void dc_stmt_grow(dc_stmt_cache *c) {
  dc_stmt_slot *old_slots = c->slots;
  size_t        old_cap   = c->capacity;
  size_t        i;

  c->capacity *= 2;
  c->mask      = c->capacity - 1;
  c->count     = 0;
  Newxz(c->slots, c->capacity, dc_stmt_slot);

  for (i = 0; i < old_cap; i++) {
    dc_stmt_slot *old = &old_slots[i];
    if (old->addr) {
      dc_stmt_slot *s = dc_stmt_insert(c, old->addr, old->op_next,
        old->cop_file, old->op_identity, old->fileinfohash);
      s->stmt_count = old->stmt_count;
    }
  }
  Safefree(old_slots);
}

/*
 * Flush all cached counts into the Perl statements HV, then zero the cached
 * counts.  The cache structure stays intact so that subsequent executions still
 * get cache hits.
 */
static void dc_stmt_cache_flush(pTHX_ dc_stmt_cache *c, HV *statements) {
  size_t i;

  if (!c->slots) return;

  for (i = 0; i < c->capacity; i++) {
    dc_stmt_slot *s = &c->slots[i];
    if (s->addr && s->stmt_count) {
      SV **sv;
      IV   existing;

      /* Reconstruct the struct unique key from cached fields */
      struct unique uniq;
      uniq.addr         = s->addr;
      uniq.op_identity  = s->op_identity;
      uniq.fileinfohash = s->fileinfohash;

      sv = hv_fetch(statements, (char *)&uniq, KEY_SZ, 1);
      existing = SvTRUE(*sv) ? SvIV(*sv) : 0;
      sv_setiv(*sv, existing + s->stmt_count);
      s->stmt_count = 0;
    }
  }
}

static void dc_av_cache_init(dc_av_cache *c) {
  c->capacity = DC_AV_CACHE_INIT_CAP;
  c->count    = 0;
  c->mask     = c->capacity - 1;
  Newxz(c->slots, c->capacity, dc_av_slot);
}

static void dc_av_grow(dc_av_cache *c);

static dc_av_slot *dc_av_lookup(dc_av_cache *c, OP *addr) {
  size_t idx;
  if (!c->slots) return NULL;
  idx = ((size_t)addr >> 4) & c->mask;
  for (;;) {
    dc_av_slot *s = &c->slots[idx];
    if (!s->addr)        return NULL;
    if (s->addr == addr) return s;
    idx = (idx + 1) & c->mask;
  }
}

static dc_av_slot *dc_av_insert(dc_av_cache *c, OP *addr,
                                OP *op_next, size_t op_identity,
                                AV *av) {
  size_t idx;
  dc_av_slot *s;

  if (!c->slots) dc_av_cache_init(c);

  if (c->count * 100 >= c->capacity * DC_AV_CACHE_LOAD_PCT)
    dc_av_grow(c);

  idx = ((size_t)addr >> 4) & c->mask;
  for (;;) {
    s = &c->slots[idx];
    if (!s->addr) break;
    idx = (idx + 1) & c->mask;
  }

  s->addr        = addr;
  s->op_next     = op_next;
  s->op_identity = op_identity;
  s->av          = av;
  c->count++;
  return s;
}

static void dc_av_grow(dc_av_cache *c) {
  dc_av_slot *old_slots = c->slots;
  size_t      old_cap   = c->capacity;
  size_t      i;

  c->capacity *= 2;
  c->mask      = c->capacity - 1;
  c->count     = 0;
  Newxz(c->slots, c->capacity, dc_av_slot);

  for (i = 0; i < old_cap; i++) {
    dc_av_slot *old = &old_slots[i];
    if (old->addr)
      dc_av_insert(c, old->addr, old->op_next, old->op_identity, old->av);
  }
  Safefree(old_slots);
}

/*
 * Fetch (or create) the AV for an op from the av_cache, falling back to
 * hv_fetch on the given backing HV on a cache miss.  If the AV is newly
 * created, pre-extend it with init_slots empty entries (0 = no extension).
 */
static AV *dc_av_cached_fetch(pTHX_ dc_av_cache *cache, HV *backing_hv,
                              OP *op, size_t identity, int init_slots) {
  AV         *av;
  dc_av_slot *slot = dc_av_lookup(cache, op);

  if (slot && slot->op_next == op->op_next && slot->op_identity == identity)
    return slot->av;

  /* Slow path: hv_fetch */
  {
    SV **svp = hv_fetch(backing_hv, get_key(op), KEY_SZ, 1);
    if (SvROK(*svp)) {
      av = (AV *) SvRV(*svp);
    } else {
      *svp = newRV_inc((SV*) (av = newAV()));
      if (init_slots)
        av_unshift(av, init_slots);
    }
  }

  if (slot) {
    slot->op_next     = op->op_next;
    slot->op_identity = identity;
    slot->av          = av;
  } else {
    dc_av_insert(cache, op, op->op_next, identity, av);
  }

  return av;
}

#if CAN_PROFILE

static void cover_time(pTHX_ const char *key)
{
  dMY_CXT;
  SV **count;
  NV   c;

  if (collecting(Time)) {
    /*
     * Profiling information is stored against MY_CXT.profiling_key,
     * the key for the op we have just run
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
    if (key) {
      memcpy(MY_CXT.profiling_key, key, KEY_SZ);
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
  cover_time(aTHX_ NULL);
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

  SvSetSV_nosteal(MY_CXT.module, (SV*)newSVpv(SvPV_nolen(TOPs), 0));
  NDEB(D(L, "require %s\n", SvPV_nolen(MY_CXT.module)));
}

static void call_report(pTHX) {
  dSP;
  PUSHMARK(SP);
  call_pv("Devel::Cover::report", G_VOID|G_DISCARD|G_EVAL);
  SPAGAIN;
}

static void cover_statement(pTHX_ OP *op, const char *ch) {
  dMY_CXT;

  SV  **count;
  IV    c;

  if (!collecting(Statement)) return;

  count = hv_fetch(MY_CXT.statements, ch, KEY_SZ, 1);
  c     = SvTRUE(*count) ? SvIV(*count) + 1 : 1;

  NDEB(D(L, "Statement: %s:%ld\n",
         CopFILE(cCOPx(op)), (long)CopLINE(cCOPx(op))));

  sv_setiv(*count, c);
  NDEB(op_dump(op));
}

static void cover_current_statement(pTHX) {
  dMY_CXT;

#if CAN_PROFILE
  /*
   * When time coverage is enabled we need the full key for the profiling_key
   * bookkeeping, so bypass the cache entirely.
   */
  if (collecting(Time)) {
    const char *ch = get_key(PL_op);
    cover_time(aTHX_ ch);
    cover_statement(aTHX_ PL_op, ch);
    return;
  }
#endif

  if (!collecting(Statement)) return;

  /* Fast path: C-level statement cache (time coverage is off) */
  {
    dc_stmt_slot *slot = dc_stmt_lookup(&MY_CXT.stmt_cache, PL_op);
    if (slot) {
      /*
       * Address found - check op_next and CopFILE as slab reuse
       * guards. Structurally identical eval'd modules at reused slab addresses
       * share op_next (and op_identity), but have different CopFILE
       * pointers. cover_current_statement is only called for NEXTSTATE/DBSTATE
       * ops, so CopFILE is always valid.
       */
      if (slot->op_next == PL_op->op_next
          && slot->cop_file == CopFILE((COP *)PL_op)) {
        slot->stmt_count++;
        return;
      }
      /* Slab reuse: flush stale count, update slot in place */
      if (slot->stmt_count) {
        struct unique uniq;
        SV **sv;
        IV   existing;
        uniq.addr         = slot->addr;
        uniq.op_identity  = slot->op_identity;
        uniq.fileinfohash = slot->fileinfohash;
        sv = hv_fetch(MY_CXT.statements,
                      (char *)&uniq, KEY_SZ, 1);
        existing = SvTRUE(*sv) ? SvIV(*sv) : 0;
        sv_setiv(*sv, existing + slot->stmt_count);
      }
      slot->op_next      = PL_op->op_next;
      slot->cop_file     = CopFILE((COP *)PL_op);
      slot->op_identity  = hash_op_identity(PL_op);
      slot->fileinfohash = fnv1a_hash_file_line(
        CopFILE((COP *)PL_op), CopLINE((COP *)PL_op));
      slot->stmt_count = 1;
      return;
    }

    /* Cache miss: insert and count the first execution */
    {
      const char *cop_file = CopFILE((COP *)PL_op);
      dc_stmt_slot *s = dc_stmt_insert(&MY_CXT.stmt_cache,
        PL_op, PL_op->op_next, cop_file, hash_op_identity(PL_op),
        fnv1a_hash_file_line(cop_file, CopLINE((COP *)PL_op)));
      s->stmt_count = 1;
    }
  }
}

static void add_branch(pTHX_ OP *op, int br) {
  dMY_CXT;
  AV  *branches = dc_av_cached_fetch(aTHX_ &MY_CXT.av_cache, MY_CXT.branches,
                                     op, hash_op_identity(op), 2);
  SV **count    = av_fetch(branches, br, 1);
  int  c        = SvTRUE(*count) ? SvIV(*count) + 1 : 1;
  sv_setiv(*count, c);
  NDEB(D(L, "Adding branch making %d at %p\n", c, op));
}

static AV *get_conditional_array(pTHX_ OP *op) {
  dMY_CXT;
  return dc_av_cached_fetch(aTHX_ &MY_CXT.av_cache, MY_CXT.conditions, op,
                            hash_op_identity(op), 0);
}

static void set_conditional(pTHX_ OP *op, int cond, int value) {
  /*
   * The conditional array is composed of six elements:
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
  int true_ish = (op->op_type == OP_DOR || op->op_type == OP_DORASSIGN)
    ? SvOK(*count) : SvTRUE(*count);
  int  c     = true_ish ? SvIV(*count) + 1 : 1;
  sv_setiv(*count, c);
  NDEB(D(L, "Adding %d conditional making %d at %p\n", cond, c, op));
}

#ifdef USE_ITHREADS
static AV *get_conds(pTHX_ AV *conds) {
  dMY_CXT;

  AV   *thrconds;
  HV   *threads;
  SV   *tid,
      **cref;
  char *t;

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
  NDEB(D(L, "Looking through %zd conditionals at %p\n",
         av_len(conds) - 1, PL_op));
  for (; i <= av_len(conds); i++) {
    OP  *op    = INT2PTR(OP *, SvIV(*av_fetch(conds, i, 0)));
    SV **count = av_fetch(get_conditional_array(aTHX_ op), 0, 1);
    int true_ish = (op->op_type == OP_DOR || op->op_type == OP_DORASSIGN)
      ? SvOK(*count) : SvTRUE(*count);
    int type  = true_ish ? SvIV(*count) : 0;
    sv_setiv(*count, 0);

    /* Check if we have come from an xor with a true first op */
    if (final)     value  = 1;
    if (type == 1) value += 2;

    NDEB(D(L, "Found %p (trueish=%d): %d, %d\n", op, true_ish, type, value));
    add_conditional(aTHX_ op, value);
  }

#ifdef USE_ITHREADS
  i = -1;
#else
  i = 1;
#endif
  while (av_len(conds) > i) av_pop(conds);

  NDEB(svdump(conds));
  NDEB(D(L, "addr is %p, next is %p, PL_op is %p, length is %zd final is %d\n",
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

/*
 * For if ($a || $b) and unless ($a && $b), rpeep skips past a few logops and
 * messes with Devel::Cover
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

/* NOTE: caller must protect get_condition* calls by locking DC_mutex */
static OP *get_condition(pTHX) {
  SV **pc = hv_fetch(Pending_conditionals, get_key(PL_op), KEY_SZ, 0);
  if (pc && SvROK(*pc)) {
    dSP;
    int true_ish;
    NDEB(D(L, "get_condition from %p, %p: %p (%s)\n",
          PL_op, (void *)PL_op->op_targ, pc, hex_key(get_key(PL_op))));
    /* dump_conditions(aTHX); */
    NDEB(svdump(Pending_conditionals));
    true_ish = (PL_op->op_type == OP_DOR || PL_op->op_type == OP_DORASSIGN)
      ? SvOK(TOPs) : SvTRUE(TOPs);
    NDEB(D(L, "   get_condition true_ish=%d\n", true_ish));
    add_condition(aTHX_ *pc, true_ish ? 2 : 1);
  } else {
    PDEB(D(L, "All is lost, I know not where to go from %p, %p: %p (%s)\n",
           PL_op, (void *)PL_op->op_targ, pc, hex_key(get_key(PL_op))));
    dump_conditions(aTHX);
    NDEB(svdump(Pending_conditionals));
    exit(1);
  }
  return PL_op;
}
static OP *get_condition_dor(pTHX) {
  SV **pc = hv_fetch(Pending_conditionals, get_key(PL_op), KEY_SZ, 0);
  if (pc && SvROK(*pc)) {
    dSP;
    int true_ish;
    NDEB(D(L, "get_condition_dor from %p, %p: %p (%s)\n",
           PL_op, (void *)PL_op->op_targ, pc, hex_key(get_key(PL_op))));
    /* dump_conditions(aTHX); */
    NDEB(svdump(Pending_conditionals));
    true_ish = SvOK(TOPs);
    NDEB(D(L, "   get_condition_dor true_ish=%d\n", true_ish));
    add_condition(aTHX_ *pc, true_ish ? 2 : 1);
  } else {
    PDEB(D(L, "All is lost, I know not where to go from %p, %p: %p (%s)\n",
           PL_op, (void *)PL_op->op_targ, pc, hex_key(get_key(PL_op))));
    dump_conditions(aTHX);
    NDEB(svdump(Pending_conditionals));
    exit(1);
  }
  return PL_op;
}

static void finalise_conditions(pTHX) {
  /*
   * Our algorithm for conditions relies on ending up at a particular op which
   * we use to call get_condition().  It's possible that we never get to that
   * op; for example we might return out of a sub. This causes us to lose
   * coverage information.
   *
   * This function is called after the program has been run in order to collect
   * that lost information.
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

/*
 * Resolve conditions deferred from sort blocks.  The stack top holds the sort
 * comparator's final value - the right operand of the outermost || whose
 * right->op_next was NULL.
 */
static void resolve_deferred_conditionals(pTHX_ AV *dc, I32 base) {
  if (av_len(dc) >= base) {
    dSP;
    int true_ish = SvTRUE(TOPs);
    while (av_len(dc) >= base) {
      SV *sv = av_pop(dc);
      OP *cond_op = INT2PTR(OP *, SvIV(sv));
      add_conditional(aTHX_ cond_op, true_ish ? 2 : 1);
      SvREFCNT_dec(sv);
    }
  }
}

static void cover_logop(pTHX) {
  /*
   * For OP_AND, if the first operand is false, we have short circuited the
   * second, otherwise the value of the op is the value of the second operand.
   *
   * For OP_OR, if the first operand is true, we have short circuited the
   * second, otherwise the value of the op is the value of the second operand.
   *
   * We check the value of the first operand by simply looking on the stack.  To
   * check the second operand it is necessary to note the location of the next
   * op after this logop.  When we get there, we look at the stack and store the
   * coverage information indexed to this op.
   *
   * This scheme also works for OP_XOR with a small modification because it
   * doesn't short circuit.  See the comment below.
   *
   * To find out when we get to the next op we change the op_ppaddr to point to
   * get_condition(), which will do the necessary work and then reset and run
   * the original op_ppaddr.  We also store information in the
   * Pending_conditionals hash.  This is keyed on the op and the value is an
   * array, the first element of which is the op we are messing with, the second
   * element of which is the op_ppaddr we overwrote, and the subsequent elements
   * are the ops about which we are collecting the condition coverage
   * information. Note that an op may be collecting condition coverage
   * information about a number of conditions.
   */

  dMY_CXT;

  NDEB(D(L, "logop() at %p\n", PL_op));
  NDEB(op_dump(PL_op));

  if (!collecting(Condition))
    return;

  if (cLOGOP->op_first->op_type == OP_ITER) {
    /* loop - ignore it for now */
  } else {
    dSP;

    int leftval_true_ish = (PL_op->op_type == OP_DOR || PL_op->op_type == OP_DORASSIGN)
      ? SvOK(TOPs) : SvTRUE(TOPs);
    /* We don't count X= as void context because we care about the value
     * of the RHS */
    int void_context = GIMME_V == G_VOID &&
                       PL_op->op_type != OP_DORASSIGN &&
                       PL_op->op_type != OP_ANDASSIGN &&
                       PL_op->op_type != OP_ORASSIGN;
    NDEB(D(L, "leftval_true_ish: %d, void_context: %d at %p\n",
           leftval_true_ish, void_context, PL_op));
    NDEB(op_dump(PL_op));

    set_conditional(aTHX_ PL_op, 5, void_context);

    if ((PL_op->op_type == OP_AND       &&  leftval_true_ish) ||
        (PL_op->op_type == OP_ANDASSIGN &&  leftval_true_ish) ||
        (PL_op->op_type == OP_OR        && !leftval_true_ish) ||
        (PL_op->op_type == OP_ORASSIGN  && !leftval_true_ish) ||
        (PL_op->op_type == OP_DOR       && !leftval_true_ish) ||
        (PL_op->op_type == OP_DORASSIGN && !leftval_true_ish) ||
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
         * If we are in void context, or the right side of the op is a branch,
         * we don't care what its value is - it won't be returning one.  We're
         * just glad to be here, so we chalk up success.
         */

        NDEB(D(L, "Add conditional 2\n"));
        add_conditional(aTHX_ PL_op, 2);
      } else {
        char *ch;
        AV   *conds;
        SV  **cref,
             *cond;
        OP   *next;

        if (PL_op->op_type == OP_XOR && leftval_true_ish) {
          /*
           * This is an xor.  It does not short circuit.  We have just executed
           * the first op.  When we get to next we will have already done the
           * xor, so we can work out what the value of the second op was.
           *
           * We set a flag in the first element of the array to say that we had
           * a true value from the first op.
           */

          set_conditional(aTHX_ PL_op, 0, 1);
        }

        NDEB(D(L, "Getting next\n"));
        next = (PL_op->op_type == OP_XOR)
          ? PL_op->op_next
          : right->op_next;
        while (next && next->op_type == OP_NULL)
          next = next->op_next;
        if (!next) {
          /*
           * Sort block (or fold_constants): right->op_next is NULL so we can't
           * hijack it.  Defer resolution to runops exit where the stack top
           * holds the right operand's value.
           */
          av_push(MY_CXT.deferred_conditionals, newSViv(PTR2IV(PL_op)));
          return;
        }
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
               "making %zd at %p (%s), ppaddr: %p\n",
               next, PL_op_name[next->op_targ], av_len(conds) - 1,
               PL_op, hex_key(ch), next->op_ppaddr));
        /* dump_conditions(aTHX); */
        NDEB(svdump(Pending_conditionals));
        NDEB(op_dump(PL_op));
        NDEB(op_dump(next));

        next->op_ppaddr = (next->op_type == OP_NEXTSTATE && (
          PL_op->op_type == OP_DOR || PL_op->op_type == OP_DORASSIGN))
          ? get_condition_dor : get_condition;
        MUTEX_UNLOCK(&DC_mutex);
      }
    } else {
      /* short circuit */
      OP *up = OpSIBLING(cLOGOP->op_first)->op_next;
      OP *skipped;

      while (up && up->op_type == PL_op->op_type) {
        NDEB(D(L, "Considering adding %p (%s) -> (%p) from %p (%s) -> (%p)\n",
               up, PL_op_name[up->op_type], up->op_next,
               PL_op, PL_op_name[PL_op->op_type], PL_op->op_next));
        add_conditional(aTHX_ up, 3);
        if (up->op_next == PL_op->op_next)
          break;
        up = OpSIBLING(cLOGOPx(up)->op_first)->op_next;
      }
      add_conditional(aTHX_ PL_op, 3);

      skipped = PL_op;
      while ((skipped = find_skipped_conditional(aTHX_ skipped)) != NULL)
        add_conditional(aTHX_ skipped, 2); /* Should this ever be 1? */
    }
  }
}

/*
 * A sequence of variable declarations may have been optimized to a single
 * OP_PADRANGE. The original sequence may span multiple lines, but only the
 * first line has been marked as covered for now. Mark other OP_NEXTSTATE inside
 * the original sequence of statements.
 */
static void cover_padrange(pTHX) {
  dMY_CXT;
  OP *next,
     *orig;
  if (!collecting(Statement)) return;
  next = PL_op->op_next;
  orig = OpSIBLING(PL_op);

  /* Ignore padrange preparing subroutine call */
  while (orig && orig != next) {
    if (orig->op_type == OP_ENTERSUB) return;
    orig = orig->op_next;
  }
  orig = OpSIBLING(PL_op);
  while (orig && orig != next) {
    if (orig->op_type == OP_NEXTSTATE) {
      cover_statement(aTHX_ orig, get_key(orig));
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

static OP *dc_nextstate(pTHX) {
  dMY_CXT;
  NDEB(D(L, "dc_nextstate() at %p (%d)\n", PL_op, collecting_here(aTHX)));
  if (MY_CXT.covering) check_if_collecting(aTHX_ cCOP);
  if (collecting_here(aTHX)) cover_current_statement(aTHX);
  return MY_CXT.ppaddr[OP_NEXTSTATE](aTHX);
}

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
  NDEB(D(L, "PL_curcop: %s:%ld\n",
         CopFILE(PL_curcop), (long)CopLINE(PL_curcop)));
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
  PL_ppaddr[OP_DBSTATE]   = dc_dbstate;
  PL_ppaddr[OP_ENTERSUB]  = dc_entersub;
  PL_ppaddr[OP_PADRANGE]  = dc_padrange;
  PL_ppaddr[OP_COND_EXPR] = dc_cond_expr;
  PL_ppaddr[OP_AND]       = dc_and;
  PL_ppaddr[OP_ANDASSIGN] = dc_andassign;
  PL_ppaddr[OP_OR]        = dc_or;
  PL_ppaddr[OP_ORASSIGN]  = dc_orassign;
  PL_ppaddr[OP_DOR]       = dc_dor;
  PL_ppaddr[OP_DORASSIGN] = dc_dorassign;
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
    Zero(&MY_CXT.stmt_cache, 1, dc_stmt_cache);
    Zero(&MY_CXT.av_cache, 1, dc_av_cache);
    MY_CXT.deferred_conditionals      = newAV();
    MY_CXT.module              = newSVpv("", 0);
    MY_CXT.lastfile            = newSVpvn("", 1);
    MY_CXT.lastfile_ptr        = NULL;
    MY_CXT.covering            = All;
    MY_CXT.tid                 = tid++;

    MY_CXT.replace_ops = SvTRUE(get_sv("Devel::Cover::Replace_ops", FALSE));
    NDEB(D(L, "running with Replace_ops as %d\n", MY_CXT.replace_ops));
  }
}

static int runops_cover(pTHX) {
  dMY_CXT;
  I32 deferred_base = av_len(MY_CXT.deferred_conditionals) + 1;

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
      hijacked = PL_op->op_ppaddr == get_condition
              || PL_op->op_ppaddr == get_condition_dor;
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
     * We are about the run the op PL_op, so we'll collect information for it
     * now
     */

    switch (PL_op->op_type) {
      case OP_NEXTSTATE:
      case OP_DBSTATE: {
        cover_current_statement(aTHX);
        break;
      }

      case OP_PADRANGE: {
        cover_padrange(aTHX);
        break;
      }

      case OP_COND_EXPR: {
        cover_cond(aTHX);
        break;
      }

      case OP_AND:
      case OP_ANDASSIGN:
      case OP_OR:
      case OP_ORASSIGN:
      case OP_DOR:
      case OP_DORASSIGN:
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
    if (!(PL_op = PL_op->op_ppaddr(aTHX))) {
      resolve_deferred_conditionals(aTHX_
        MY_CXT.deferred_conditionals, deferred_base);
      break;
    }

    PERL_ASYNC_CHECK();
  }

#if CAN_PROFILE
  cover_time(aTHX_ NULL);
#endif

  MY_CXT.collecting_here = 1;

  NDEB(D(L, "exiting runops_cover\n"));

  TAINT_NOT;
  return 0;
}

static int runops_orig(pTHX) {
  dMY_CXT;
  I32 deferred_base = av_len(MY_CXT.deferred_conditionals) + 1;

  NDEB(D(L, "entering runops_orig\n"));

  while ((PL_op = PL_op->op_ppaddr(aTHX))) {
    PERL_ASYNC_CHECK();
  }

  resolve_deferred_conditionals(aTHX_
    MY_CXT.deferred_conditionals, deferred_base);

  NDEB(D(L, "exiting runops_orig\n"));

  TAINT_NOT;
  return 0;
}

#if defined DO_RUNOPS_TRACE
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
#endif

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
typedef CV *B__CV;

/* Op class names for creating properly blessed B:: objects
 * Determine the B:: class name for an OP.  op_class() is only available on Perl
 * 5.26+, so provide a fallback using PL_opargs.
 */
static const char *dc_op_classname(pTHX_ const OP *o) {
  if (!o || !o->op_type) {
    if (!o) return "B::NULL";
    /*
     * Null ops that were originally nextstate/dbstate are still COPs in memory
     * - B::Deparse's pp_null dispatches to pp_nextstate which needs COP methods
     *   like stashpv and warnings.
     */
    if (o->op_targ == OP_NEXTSTATE || o->op_targ == OP_DBSTATE)
      return "B::COP";
    if (o->op_flags & OPf_KIDS)
      return "B::UNOP";
    return "B::OP";
  }
  switch (PL_opargs[o->op_type] & OA_CLASS_MASK) {
    case OA_BASEOP:        return "B::OP";
    case OA_UNOP:          return "B::UNOP";
    case OA_BINOP:         return "B::BINOP";
    case OA_LOGOP:         return "B::LOGOP";
    case OA_LISTOP:        return "B::LISTOP";
    case OA_PMOP:          return "B::PMOP";
    case OA_SVOP:          return "B::SVOP";
    case OA_PADOP:         return "B::PADOP";
    case OA_LOOP:          return "B::LOOP";
    case OA_COP:           return "B::COP";
    case OA_PVOP_OR_SVOP:
#ifdef USE_ITHREADS
                           return "B::PADOP";
#else
                           return "B::SVOP";
#endif
    case OA_BASEOP_OR_UNOP:
      return (o->op_flags & OPf_KIDS) ? "B::UNOP" : "B::OP";
    case OA_FILESTATOP:
      return (o->op_flags & OPf_KIDS) ? "B::UNOP" : "B::SVOP";
    case OA_LOOPEXOP:
      if (o->op_flags & OPf_STACKED) return "B::UNOP";
      if (o->op_flags & OPf_SPECIAL) return "B::OP";
      return "B::SVOP";
    default:               return "B::OP";
  }
}

/* Create a blessed B::OP-subclass SV wrapping an OP pointer */
static SV *dc_make_op_sv(pTHX_ OP *o) {
  SV *sv = newSV(0);
  sv_setiv(newSVrv(sv, dc_op_classname(aTHX_ o)), PTR2IV(o));
  return sv;
}

/* Create a blessed B::CV SV wrapping a CV pointer */
static SV *dc_make_cv_sv(pTHX_ CV *cv) {
  SV *sv = newSV(0);
  sv_setiv(newSVrv(sv, "B::CV"), PTR2IV(cv));
  return sv;
}

/* Call the Perl walk callback: callback->(op, type, cv) */
static void dc_walk_callback(pTHX_ OP *op, SV *callback,
                             const char *type, CV *cv) {
  dSP;
  ENTER; SAVETMPS;
  PUSHMARK(SP);
  XPUSHs(sv_2mortal(dc_make_op_sv(aTHX_ op)));
  XPUSHs(sv_2mortal(newSVpv(type, 0)));
  XPUSHs(sv_2mortal(dc_make_cv_sv(aTHX_ cv)));
  PUTBACK;
  call_sv(callback, G_DISCARD);
  FREETMPS; LEAVE;
}

/* Store a child→parent mapping in the parent map */
static void dc_store_parent(pTHX_ HV *parent_map, OP *child, OP *parent) {
  char key[24];
  STRLEN keylen = (STRLEN)snprintf(key, sizeof(key), "%" IVdf, PTR2IV(child));
  hv_store(parent_map, key, keylen, dc_make_op_sv(aTHX_ parent), 0);
}

/*
 * Recursive depth-first op tree walker.
 * Identifies coverage-relevant ops and calls back to Perl.
 * Populates parent_map with child→parent mappings so Perl callbacks
 * can walk the parent chain on all Perl versions (not just 5.26+).
 */
static void dc_walk_ops_r(pTHX_ OP *op, SV *callback, CV *cv, HV *parent_map) {
  OP *kid;

  if (!op) return;

  switch (op->op_type) {
    case OP_NEXTSTATE:
    case OP_DBSTATE:
      dc_walk_callback(aTHX_ op, callback, "statement", cv);
      break;

    case OP_COND_EXPR:
      dc_walk_callback(aTHX_ op, callback, "cond_expr", cv);
      break;

    case OP_AND:
    case OP_OR:
    case OP_DOR:
      if (cLOGOPx(op)->op_first->op_type == OP_ITER)
        dc_walk_callback(aTHX_ op, callback, "iter", cv);
      else
        dc_walk_callback(aTHX_ op, callback, "logop", cv);
      break;

    case OP_ANDASSIGN:
    case OP_ORASSIGN:
    case OP_DORASSIGN:
      dc_walk_callback(aTHX_ op, callback, "logassignop", cv);
      break;

    case OP_XOR:
      dc_walk_callback(aTHX_ op, callback, "xor", cv);
      break;

#if PERL_VERSION >= 26
    case OP_ARGDEFELEM:
      dc_walk_callback(aTHX_ op, callback, "argdefelem", cv);
      break;
#endif
#if PERL_VERSION >= 43
    case OP_PARAMTEST:
      dc_walk_callback(aTHX_ op, callback, "argdefelem", cv);
      break;
#endif

    case OP_NULL:
      if (op->op_targ == OP_NEXTSTATE || op->op_targ == OP_DBSTATE) {
        /*
         * Skip dead end-of-block ex-nextstates (closing braces, comment-only
         * files).  These have no sibling in the tree because they're the last
         * child of their parent lineseq.
         */
        if (OpSIBLING(op))
          dc_walk_callback(aTHX_ op, callback, "null_statement", cv);
      }
      break;

    default:
      break;
  }

  /* Recurse into children, storing parent mappings */
  if (op->op_flags & OPf_KIDS) {
    for (kid = cUNOPx(op)->op_first; kid; kid = OpSIBLING(kid)) {
      dc_store_parent(aTHX_ parent_map, kid, op);
      dc_walk_ops_r(aTHX_ kid, callback, cv, parent_map);
    }
  }

  /* Handle PMOP special children (regex replacement trees) */
  if (op->op_type == OP_SUBST) {
    PMOP *pm = cPMOPx(op);
#ifdef USE_ITHREADS
    if (pm->op_pmstashstartu.op_pmreplstart) {
      dc_store_parent(aTHX_ parent_map,
                      pm->op_pmstashstartu.op_pmreplstart, op);
      dc_walk_ops_r(aTHX_ pm->op_pmstashstartu.op_pmreplstart,
                    callback, cv, parent_map);
    }
#else
    if (pm->op_pmreplrootu.op_pmreplroot) {
      dc_store_parent(aTHX_ parent_map,
                      pm->op_pmreplrootu.op_pmreplroot, op);
      dc_walk_ops_r(aTHX_ pm->op_pmreplrootu.op_pmreplroot,
                    callback, cv, parent_map);
    }
#endif
  }
}

static void dc_walk_ops(pTHX_ OP *op, SV *callback, CV *cv, HV *parent_map) {
  hv_clear(parent_map);
  dc_walk_ops_r(aTHX_ op, callback, cv, parent_map);
}


MODULE = Devel::Cover PACKAGE = Devel::Cover

PROTOTYPES: ENABLE

void
set_criteria(flag)
    unsigned flag
  PREINIT:
    dMY_CXT;
  PPCODE:
    MY_CXT.covering = flag;
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
    if (MY_CXT.statements)
      dc_stmt_cache_flush(aTHX_ &MY_CXT.stmt_cache, MY_CXT.statements);
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
    if (!MY_CXT.ends) MY_CXT.ends = newAV();
    NDEB(svdump(MY_CXT.ends));
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

void
adjust_blocks(stash)
    HV *stash
  PPCODE:
#if PERL_VERSION >= 38
    if (HvHasAUX(stash) && HvAUX(stash)->xhv_aux_flags & HvAUXf_IS_CLASS) {
      AV *blocks = HvAUX(stash)->xhv_class_adjust_blocks;
      if (blocks) {
        SSize_t i;
        for (i = 0; i <= AvFILL(blocks); i++) {
          CV *cv = (CV *)AvARRAY(blocks)[i];
          if (cv && (SV *)cv != &PL_sv_undef)
            XPUSHs(sv_2mortal(newRV_inc((SV *)cv)));
        }
      }
    }
#endif

void
walk_ops(root_op, callback, cv, parent_map_ref)
    B::OP root_op
    SV   *callback
    B::CV cv
    SV   *parent_map_ref
  CODE:
    if (!SvROK(parent_map_ref) || SvTYPE(SvRV(parent_map_ref)) != SVt_PVHV)
      croak("parent_map must be a hash reference");
    dc_walk_ops(aTHX_ root_op, callback, cv,
                (HV *)SvRV(parent_map_ref));

BOOT:
  {
    MY_CXT_INIT;
#ifdef USE_ITHREADS
    MUTEX_INIT(&DC_mutex);
#endif
    initialise(aTHX);
    if (MY_CXT.replace_ops) {
      replace_ops(aTHX);
      PL_runops = runops_orig;
#if defined HAS_GETTIMEOFDAY
      elapsed();
#elif defined HAS_TIMES
      cpu();
#endif
#if defined DO_RUNOPS_TRACE
      PL_runops = runops_trace;
#endif
    } else {
      PL_runops = runops_cover;
    }
    PL_savebegin = TRUE;
  }
