# Setting up cpancover

## Overview

Cpancover requires bash 5 or later and docker. Running `cpancover` on the host
also requires plenv and Perl 5.42.0 or later.

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

You need plenv only to run `cpancover` on the host.

Install plenv by following the instructions on
[GitHub](https://github.com/tokuhirom/plenv). If you are running Homebrew:

```sh
brew install plenv
```

## Running

To run the system as a whole:

```sh
cd /path/to/Devel--Cover
. ./utils/setup
```

`utils/setup` puts `utils` on your `PATH`, so that you can run `dc` without a
path. The system perl is enough for `utils/setup` and for `dc docker-build`.

There are two ways to run cpancover, and both need the docker image. Pull the
image from Docker Hub:

```sh
dc cpancover-docker-pull
```

`dc docker-build` builds `pjcj/cpancover` from the `main` branch on GitHub and
pushes it to Docker Hub. `dc -e dev docker-build` builds `pjcj/cpancover_dev`
from the files of your checkout and does not push it. After a dev build, pass
`-e dev` to the other commands too, so that they use `pjcj/cpancover_dev` and
`~/cover/staging_dev`.

The first way runs everything in containers. Run cpancover:

```sh
dc cpancover-controller-run
```

The `cpancover-controller-run` command runs until stopped, collecting coverage
for each newly uploaded distribution. `dc cpancover-controller-run-once` runs a
single pass. Both commands start a controller container, which runs `dc` from
the checkout inside the image, so the host needs no cpancover perl. After each
pass that adds a report, the controller writes the top level HTML and JSON
itself. cpancover.com runs this way.

The loop passes `--on_cpan` to `cpancover --generate_html`, so the count and the
coverage bar on the index page leave out distributions that CPAN no longer
lists. Their reports and pages stay, greyed in the distribution lists with a
hover tip saying so.

`dc cpancover-docker-ps` lists the cpancover containers. Stop and remove them
with:

```sh
dc cpancover-docker-kill
dc cpancover-docker-rm
```

Or, for slightly more control, jobs can be run as follows. In this second way
`bin/cpancover` runs on the host and still starts a docker container for each
build. Install or upgrade a cpancover perl:

```sh
dc install-cpancover-perl 5.42.0
```

This installs a plenv perl named `cpancover` with most of the modules that
cpancover needs. Nothing selects that perl. If an older perl runs
`bin/cpancover`, the `use 5.42.0` line stops it and `dc` ignores the failure.
Select the perl and install the modules that `dc install-cpancover-perl` leaves
out:

```sh
export PLENV_VERSION=cpancover
cpanm File::HomeDir MetaCPAN::Client CPAN::Releases::Latest HTML::Entities
```

Then run cpancover:

```sh
dc cpancover-latest | head -2000 | dc cpancover
```

The top level HTML and JSON are generated with:

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

Each distdir holds the rendered HTML report and the JSON summary of one
distribution. Above those directories is a summary HTML page with links to the
individual coverage reports.

## Web server

If you want anyone to be able to look at the results, you'll need a web server
somewhere. The results are all static HTML so there is not much configuration
required.

cpancover.com uses [Caddy](https://caddyserver.com). Its web root is a `www`
directory beside the results directory, and each entry of `www` is a link to a
results directory. Make the web root first:

```sh
mkdir ~/cover/www
ln -s ../staging ~/cover/www/latest
```

If `~/cover/staging` is a link, make `www` beside the directory that the link
names, since `cpancover_caddyfile` in `utils/dc` resolves `$results_dir/../www`
with `readlink -f` and names the resolved path as the root, not `~/cover/www`.

Then check the configuration that `dc` generates and install it:

```sh
dc cpancover-check-caddy
dc cpancover-configure-caddy
```

The first command validates the generated configuration and shows how it differs
from the installed one. The second writes `/etc/caddy/Caddyfile` and reloads
Caddy, so it needs `sudo`. The generated file names cpancover.com and its
certificate contact, so change `cpancover_caddyfile` in `utils/dc` for another
site.

To look at the results on your own machine, run `dc cpancover-serve`, which
serves them at `http://localhost:8080/latest/`.

[cpancover site layout](technical/cpancover-site-layout.md) explains how the
directories, the links and the Caddy configuration decide which results a URL
shows.

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
