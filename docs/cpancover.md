How to set up cpancover
=======================

Overview
--------

Cpancover requires a bourne shell, plenv, and docker, as well as a recent perl.
The code requires Perl 5.16.0 but earlier versions may work.

Docker
------

Each module is built in an individual docker container.  This should allow its
resources to be constrained.  In addition the docker container is killed after a
certain time.

I have only run this in Ubuntu 14.04 and 16.04.  The docker version in 14.04,
0.9.1 (as of 31.05.2104) is insufficient.  Version 0.11.1 is fine.  I don't
know about the versions in between.

The latest version of docker can be installed on Ubuntu as follows:
(see https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/)

    # aptitude update
    # aptitude install apt-transport-https ca-certificates curl software-properties-common
    # curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    # sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    # aptitude update
    # aptitude install docker-ce

You may need to add yourself to the docker group.

To build the docker container, check out the
[devel-cover-docker](https://github.com/pjcj/devel-cover-docker) project and
follow the instructions there.

If you want to use your own docker container, edit the file `utils/dc` to point
to the correct container.

Plenv
-----

Install plenv by following the instructions on
[github](https://github.com/tokuhirom/plenv).

Running
-------

To run the system as a whole:

    $ cd /cover/dc
    $ . ./utils/setup

Install or upgrade a cpancover perl:

    $ dc install_cpancover_perl 5.26.1

Run cpancover:

    $ dc cpancover-run

The `cpancover-run` command will just sit there picking up on newly uploaded
distributions and running the coverage for them.  Or, for slightly more
control, jobs can be run as follows:

    $ dc cpancover-latest | head -2000 | dc cpancover

The top level HTML and JSON is generated with:

    $ dc cpancover-generate-html

Results
-------

The results of the runs will be stored in the `~/staging` directory.  If this
is not where you want them stored (which is rather likely) then the simplest
solution is probably to make that directory a symlink to the real location.  If
you would prefer not to do that, or you want to run multiple separate cpancover
instances (probably only for development purposes), then you can change the
`$CPANCOVER_STAGING` variable in the `utils/dc` script.

The results consist of the Devel::Cover `cover_db` directory for each package
tested, including the generated HTML output for that DB and the JSON summary
file.  Sitting above those directories is summary HTML providing links to the
individual coverage reports.

Web server
----------

If you want anyone to be able to look at the results, you'll need a web server
somewhere.  The results are all static HTML so there is not much configuration
required.

If you use nginx, the file in `utils/cpancover.nginx` can be copied into the
`/etc/nginx/sites-available` directory and from thence symlinked into
sites-enabled.  The static files are all gzipped and served as such where
possible.

cpancover.com
-------------

The server which is currently running cpancover.com has been graciously
provided by [Bytemark](http://www.bytemark.co.uk/r/cpancover).  It has plenty
of memory and cpu power, but not a large amount of disk space.  That's fine
though, it has sufficient for cpancover's needs.

The server is on the account of pjcj at bytemark.  Logins are owned by pjcj and
the metacpan group.

The server is currently running Ubuntu 16.04 LTS and was upgraded from 14.04
LTS.

The Devel::Cover directory from which cpancover is run is in `/cover/dc`.  It
is a git checkout of the Devel::Cover repository but, ideally, that should be
treated as a read-only directory.  The staging directory is symlinked to
`/cover/staging`.

In addition to hosting and running cpancover.com, I also use this server for
some development work, and in particular for testing Devel::Cover against all
the versions of perl which are supported, plus recent development versions.
For each version there is a standard and a threaded plenv installation.

The development directory for these purposes is `/cover/Devel--Cover`.  New
versions of perl can be installed by adding them to `utils/all_versions` and
running `dc all_versions --build`.
