# Devel::Cover Release Process

01. Update Changes

    - Add important changes
    - Credit the author as appropriate
    - Include github and RT numbers

02. Check it in

    - `git commit -m "Add Changes" Changes`

03. Update Contributors

04. Check it in

    - `git commit -m "Update Contributors" Contributors`

05. Update `$Latest_t` in `Makefile.PL`

    - Update test for obsolete development version skipping via
      `$LATEST_RELEASED_PERL` variable in Devel::Cover::Test.pm
    - Update version number in `Makefile.PL`

06. Check it in

    - `git commit -am "Bump version number"`

07. Run basic tests

    - `perl Makefile.PL && make`
    - `make test`

08. Test against all versions

    - `make all_test`

09. Return to base perl version

    - `perl Makefile.PL && make`

10. If there's a new stable release of perl:

    - `dc install_dzil`

11. Make the release

    - `dzil release`
