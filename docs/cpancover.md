# Setting up cpancover

## Overview

Cpancover requires a Bourne shell, plenv, docker and Perl 5.42.0 or later.

## Docker

Each module is built in an individual docker container. This should allow its
resources to be constrained. In addition the docker container is killed after a
certain time, set in seconds by `CPANCOVER_TIMEOUT`.

The build container exports the coverage database and every other entry of the
build directory, so that the report has every source the database lists. The
host then renders the report in a second container from the same image, with no
network, where no code of the distribution has run. It publishes only the output
of the second container, so the site serves nothing the build wrote.
`CPANCOVER_RENDER_TIMEOUT` sets the time limit of the render in seconds and
`CPANCOVER_EXPORT_MAX_MB` sets the size limit of the export in megabytes.

The Docker infrastructure is in the `docker/` directory of this repository. See
`docker/README.md` for full details on building and managing Docker images.

You may need to add yourself to the docker group.

## Plenv

Install plenv by following the instructions on
[GitHub](https://github.com/tokuhirom/plenv). If you are running Homebrew:

```sh
brew install plenv
```

## Running

To run the system as a whole:

```sh
cd /cover/dc
. ./utils/setup
```

Install or upgrade a cpancover perl:

```sh
dc install-cpancover-perl 5.42.0
```

Run cpancover:

```sh
dc cpancover-controller-run
```

The `cpancover-controller-run` command runs until stopped, collecting coverage
for each newly uploaded distribution. Or, for slightly more control, jobs can be
run as follows:

```sh
dc cpancover-latest | head -2000 | dc cpancover
```

The top level HTML and JSON are generated with:

```sh
dc cpancover-generate-html
```

The loop passes `--on_cpan` to `cpancover --generate_html`, so the count and the
coverage bar on the index page leave out distributions that CPAN no longer
lists. Their reports and pages stay, greyed in the distribution lists with a
hover tip saying so.

## Results

The results of the runs will be stored in the `~/cover/staging` directory. If
this is not where you want them stored (which is rather likely) then the
simplest solution is probably to make that directory a symlink to the real
location. If you would prefer not to do that, or you want to run multiple
separate cpancover instances (probably only for development purposes), then you
can pass `--results_dir` to the `utils/dc` script.

Each distdir holds the rendered HTML report and the JSON summary of one
distribution. Above those directories is a summary HTML page with links to the
individual coverage reports.

## Web server

If you want anyone to be able to look at the results, you'll need a web server
somewhere. The results are all static HTML so there is not much configuration
required.

If you use nginx, copy `utils/cpancover.nginx` into `/etc/nginx/sites-available`
and symlink it into `sites-enabled`. The static files are all gzipped and served
as such where possible.

## cpancover.com

The server which is currently running cpancover.com has been graciously provided
by [Bytemark](https://www.bytemark.co.uk). It has plenty of memory and CPU
power, but not a large amount of disk space. That's fine though, as it has
sufficient for cpancover's needs.

The server is on the account of pjcj at bytemark. Logins are owned by pjcj and
the metacpan group.

The server is currently running Ubuntu 24.04 LTS.

The Devel::Cover directory from which cpancover is run is in `/cover/dc`. It is
a git checkout of the Devel::Cover repository but, ideally, that should be
treated as a read-only directory. The staging directory is symlinked to
`/cover/staging`.

In addition to hosting and running cpancover.com, I also use this server for
some development work, and in particular for testing Devel::Cover against all
supported versions of perl, plus recent development versions. For each version
there is a standard and a threaded plenv installation.

The development directory for these purposes is `/cover/Devel--Cover`. New
versions of perl can be installed by adding them to `utils/all_versions` and
running `dc all-versions --build`.

To install a version of perl with development tools run
`dc install-dc-dev-perl 5.38.2`.
