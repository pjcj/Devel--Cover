# Documentation Standards

How to write and mark up documentation in this distribution. The rules below
describe what the documentation already does where it is consistent, and settle
the cases where it is not.

## Where documentation lives

- **POD in `lib/` and `bin/`** - user-facing. This is what people read on
  metacpan and through `perldoc`. `Devel::Cover.pod`, `Devel::Cover::Tutorial`,
  `bin/cover`, `bin/cpancover` and `bin/gcov2perl` are the main entry points.
- **POD inside `lib/Devel/Cover.pm`** - internal. It documents the collection
  machinery for people working on Devel::Cover itself, not for users.
- **`docs/`** - markdown telling someone doing a job what to do. Setting up
  cpancover, cutting a release, updating the default perl, this file.
- **`docs/technical/`** - markdown explaining how a thing works. Coverage
  internals such as branch and condition handling, MC/DC, SCAR and optree
  adjustment.

When you are unsure which of the last two a new document belongs in, ask whether
it tells the reader to do something or explains something to them.

The markup rules apply to all POD. The prose rules apply everywhere.

## POD markup

### Environment variables

Write the bare name in `C<>`, with no sigil.

```pod
Set C<DEVEL_COVER_OPTIONS> to add options.
```

Not `C<$DEVEL_COVER_OPTIONS>` and not a bare `$DEVEL_COVER_OPTIONS`. An
environment variable is not a Perl scalar, so the sigil claims something untrue
once the name is set in monospace. The accurate Perl spelling,
`$ENV{DEVEL_COVER_OPTIONS}`, is too heavy for prose. perlrun writes these names
bare for the same reason.

The internal POD in `Devel/Cover.pm` may keep the sigil where it really is
discussing a Perl variable.

### Command line options

Write options in `C<>` when they appear in prose.

```pod
The C<-loose_perms> option keeps the lock files writable.
```

Leave them bare inside a verbatim block. The OPTIONS listing in
`Devel::Cover.pod` is a literal rendering of what the reader types, and `C<>`
would show up as part of the text there.

### Programs

Use `F<>` for a program, whether or not it is ours.

```pod
The F<cover> program generates reports.
... a tree of tests run with F<prove> ...
```

### Modules

Use `L<>` for a module, which gives the reader a link.

```pod
Pod coverage comes from L<Pod::Coverage>.
```

### Code, values and everything else literal

Use `C<>` for Perl code, file names quoted inside code, option values, keywords
and attribute names.

```pod
A C<class> attribute may be included in C<details>.
Mark the whole decision with C<uncoverable mcdc all>.
```

`L<>` is a link and nothing else. `L<ignore_covered_err>` renders as a broken
link to a page that does not exist.

### Emphasis

`B<>` marks the term a list entry defines, as the report names do under
"Presentation in reports". `I<>` is rarely needed and rarely used here.

## Markdown

Two pre-commit hooks own the markdown in `docs/`, so most of the formatting is
not yours to decide.

- **mdformat** reformats the file. `.mdformat.toml` sets `wrap = 80` and
  `number = true`, so it wraps the prose and numbers ordered lists in sequence.
  Do not hand-wrap markdown and do not fight the result.
- **markdownlint** checks what is left. `.markdownlint.yaml` turns off MD013 and
  MD049 because mdformat already owns line length and emphasis markers.

The one rule worth remembering, because markdownlint will stop you otherwise, is
that every fenced block needs a language. Use `pod` for POD fragments, `perl`,
`sh`, `c` or `text` for the rest.

````text
```pod
The C<-loose_perms> option keeps the lock files writable.
```
````

## Prose

- British English throughout, except in existing APIs and standards. Write
  "optimised", "colour", "behaviour".
- Wrap POD at 80 columns. Use the full width, do not wrap short. In markdown
  mdformat does this for you.

## Checking

`podchecker` catches broken POD but not markup used wrongly, so it will pass a
`L<>` around something that is not a link. Read the rendered output when you
change markup.

```sh
podchecker lib/Devel/Cover.pod bin/cover
perldoc lib/Devel/Cover.pod
```

To find POD lines over the limit:

```sh
awk 'length > 80 {print FILENAME":"FNR}' lib/Devel/Cover.pod
```

Markdown needs neither of those. The hooks run on commit, and you can run them
first to see what they will change:

```sh
pre-commit run --files docs/documentation-standards.md
```
