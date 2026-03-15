# Coverage for ADJUST Blocks

ADJUST blocks are a construct introduced by Perl's `class` feature (5.38+).
This document describes how Devel::Cover discovers and collects coverage for
them, and how their storage differs from named method CVs.

## What ADJUST Blocks Are

An `ADJUST` block runs during object construction, after field initialisers
have executed. It is syntactically similar to `BEGIN` or `END`, but unlike
those phase blocks it runs once per object created:

```perl
class Point {
  field $x :param;
  field $y :param;

  ADJUST {
    die "x must be positive" unless $x > 0;
  }
}
```

Every `ADJUST` block compiles into its own anonymous CV, invoked with full
`ENTERSUB` overhead each time an object of that class (or any subclass) is
constructed.

## How ADJUST CVs Are Stored

Named `method` CVs are found by walking the symbol table: each method is a
GV (glob value) in the class stash, and `B::walksymtable` visits every GV.
ADJUST CVs are anonymous and are not stored as GVs anywhere.

Instead they are held in a dedicated array attached to the stash's auxiliary
structure. Every package stash (`HV*`) may carry an `xpvhv_aux` extension
accessed via `HvAUX(stash)`. For class stashes, Perl sets the
`HvAUXf_IS_CLASS` flag and populates the `xhv_class_adjust_blocks` field, an
`AV*` of `CV*` pointers - one per `ADJUST` block in declaration order.

`B::HV` does not expose `xhv_class_adjust_blocks`. This field is part of the
internal `xpvhv_aux` struct added for the `class` feature and has no
corresponding `B` API. A small XS shim inside `Cover.xs` provides access
without a dependency on any particular Perl release of `B`.

## The XS Shim

`adjust_blocks(stash)` in `Cover.xs` takes a stash as a hash reference,
checks for the `HvAUXf_IS_CLASS` flag, and returns code references to each
ADJUST block CV:

```c
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
```

The `#if PERL_VERSION >= 38` guard makes the function body a no-op on older
Perls that do not have the `class` feature or the `xhv_class_adjust_blocks`
field. The function signature is still compiled and exported so that Perl code
can call it unconditionally.

## Integration into CV Discovery

`adjust_blocks` is called from the `walksymtable` callback in `check_files`
(`lib/Devel/Cover.pm`). Each time `walksymtable` is about to recurse into a
sub-stash, the callback calls `adjust_blocks` on that stash, wraps the
returned code references as `B::CV` objects via `B::svref_2object`, filters
them with `check_file`, and adds any that pass to `%Cvs`:

```perl
walksymtable(\%main::, "find_cv", sub {
  return 0 if $seen_pkg{ $_[0] }++;
  no strict "refs";
  $Cvs{$_} ||= $_ for
    grep  check_file($_),
    map   B::svref_2object($_),
    adjust_blocks(\%{ $_[0] });
  1
});
```

Once in `%Cvs`, the existing `get_cover` pipeline processes ADJUST CVs
without further modification.

## ADJUST Block Optree

Unlike `method` CVs, ADJUST CVs do not begin with `methstart`. They compile
as plain anonymous subroutines, so `check_file` and `sub_info` handle them
without special casing:

```text
leavesub
  lineseq
    nextstate       <- B::COP; file and line of the ADJUST block body
    ... body ops ...
```

## Inherited ADJUST Blocks

When a subclass is declared with `:isa(Parent)`, Perl copies references to
the parent's ADJUST CVs into the subclass's `xhv_class_adjust_blocks` array.
The same `CV*` pointer appears in both:

```text
Animal::xhv_class_adjust_blocks -> [ ADJUST_CV ]
Dog::xhv_class_adjust_blocks    -> [ ADJUST_CV ]   (same pointer, inherited)
```

`adjust_blocks` is called for both stashes during the `walksymtable` pass,
but `$Cvs{$cv} ||= $cv` ensures the CV enters `%Cvs` only once and `get_cover`
processes it only once. The execution count, however, reflects all
constructions - constructing one `Animal` and one `Dog` yields a count of 2
for the inherited ADJUST block.
