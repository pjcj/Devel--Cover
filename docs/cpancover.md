# How to set up cpancover

## Overview

Cpancover requires a bourne shell, plenv, and docker, as well as a recent
perl. The code requires Perl 5.42.0.

## Docker

Each module is built in an individual docker container. This should allow its
resources to be constrained. In addition the docker container is killed after a
certain time.

The Docker infrastructure is in the `docker/` directory of this repository. See
`docker/README.md` for full details on building and managing Docker images.

You may need to add yourself to the docker group.

## Plenv

Install plenv by following the instructions on
[github](https://github.com/tokuhirom/plenv). If you are running brew

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

The `cpancover-controller-run` command will just sit there picking up on newly
uploaded distributions and running the coverage for them. Or, for slightly more
control, jobs can be run as follows:

```sh
dc cpancover-latest | head -2000 | dc cpancover
```

The top level HTML and JSON is generated with:

```sh
dc cpancover-generate-html
```

## Results

The results of the runs will be stored in the `~/cover/staging` directory. If
this is not where you want them stored (which is rather likely) then the
simplest solution is probably to make that directory a symlink to the real
location. If you would prefer not to do that, or you want to run multiple
separate cpancover instances (probably only for development purposes), then you
can pass `--results_dir` to the `utils/dc` script.

The results consist of the Devel::Cover `cover_db` directory for each package
tested, including the generated HTML output for that DB and the JSON summary
file. Sitting above those directories is summary HTML providing links to the
individual coverage reports.

## Web server

If you want anyone to be able to look at the results, you'll need a web server
somewhere. The results are all static HTML so there is not much configuration
required.

If you use nginx, the file in `utils/cpancover.nginx` can be copied into the
`/etc/nginx/sites-available` directory and from thence symlinked into
sites-enabled. The static files are all gzipped and served as such where
possible.

## cpancover.com

The server which is currently running cpancover.com has been graciously provided
by [Bytemark](https://www.bytemark.co.uk). It has plenty of memory and cpu
power, but not a large amount of disk space. That's fine though, it has
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
the versions of perl which are supported, plus recent development versions. For
each version there is a standard and a threaded plenv installation.

The development directory for these purposes is `/cover/Devel--Cover`. New
versions of perl can be installed by adding them to `utils/all_versions` and
running `dc all-versions --build`.

To install a version of perl with development tools run
`dc install-dc-dev-perl 5.38.2`.
