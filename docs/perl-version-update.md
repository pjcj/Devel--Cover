# Updating the Default Perl Version

These steps update the default Perl version used by Devel::Cover development and
the cpancover infrastructure.

Replace `<version>` throughout with the new version number (e.g. `5.42.1`).

01. Install the new Perl as `dc-dev`

    - `dc install-dc-dev-perl <version>`
    - This replaces the `dc-dev` plenv installation in place

02. Add the new version to `utils/all_versions`

    - Add `<version>` to the appropriate place in the version list
    - Update the hard-coded `-key` shortlist in `get_options` so it still covers
      the newest stable version (threaded and non-threaded) and the newest
      development version

03. Build all `dc-*` versions for multi-version testing

    - `make all_build_perl`
    - Builds non-threaded and threaded variants for all configured versions

04. Update the latest version constants

    - Change `$Latest_t` in `Makefile.PL` to the new version in the format
      "v5.42.1"
    - If the new version is a stable release, set `$Latest_released_perl` in
      `t/lib/Devel/Cover/Test.pm` to its minor number, which decides which
      development versions are skipped as obsolete
    - `t/internal/latest_released_perl.t` checks the second of these

05. Update the default Perl version in `docker/BUILD`

    - Change the `perl=` line near the top of the file

06. Update the CI matrix in `.github/workflows/ci.yml`

    - Add the new version to the ubuntu matrix and move the threaded entry to it
    - CI uses `shogo82148/actions-setup-perl`, which must support the new
      version first

07. Regenerate the build

    - `perl Makefile.PL && make`

08. Generate golden results for all versions

    - `make all_gold`
    - This may be a no-op if the new version produces identical output

09. Run tests across all versions to verify

    - `make all_test`

10. Install the new Perl on any host that runs `cpancover` outside a controller
    container

    - `dc install-cpancover-perl <version>`
    - This replaces the `cpancover` plenv installation in place
    - `dc cpancover` and `dc cpancover-generate-html` need the `cpancover` plenv
      Perl to run `bin/cpancover` on the host
    - The "Running" section of `docs/cpancover.md` says how to select the
      `cpancover` plenv Perl and install the modules that cpancover also needs
    - `cpancover.com` needs no `cpancover` plenv Perl, because its orchestration
      code runs in the controller container with the Perl of the Docker image
      that you rebuild in the next step

11. **On `cpancover.com`**: rebuild and push the cpancover Docker images

    - `dc docker-build`
    - See `docs/cpancover.md` and `docker/README.md` for full details on the
      Docker build and deployment process
