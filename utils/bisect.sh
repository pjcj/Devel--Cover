#!/bin/sh

# set -x

perl=~/g/perl/perl
bisect=${perl}-bisect
dc=~/g/perl/Devel--Cover
inst=/usr/local/pkg/bisect
blead=$inst/bin/perl

case "$1" in
    "launch")
        shift
        if [ -z "$1" ]; then
            echo "uasge: $0 launch your_test"
            exit 1
        fi
        test="$1"
        shift
        cd $perl
        git checkout blead
        # $bisect/Porting/bisect.pl -Dnoextensions=Encode "$@" -- $dc/$0 "$test"
        $bisect/Porting/bisect.pl -Dusedevel -Uversiononly -Dprefix=$inst "$@" -- $dc/$0 "$test"
        ;;
    "test")
        $blead -v
        ret=$?
        [ $ret -gt 127 ] && ret=127
        exit $ret
        ;;
    "bug_and")
        rm -rf $inst
        cd $perl
        make install
        # ./perl installperl -v
        cd $dc
        $blead Makefile.PL
        make
        make
        make out TEST=uncoverable
        grep -F '0     -0      1   $x and $y' uncoverable.out
        ret=$?
        [ $ret -gt 127 ] && ret=127
        exit $ret
        [ $ret -eq 0 ] && exit 1
        exit 0
        ;;
    *)
        echo cd $perl
        echo git clean -dxf
        echo cp -a $perl $bisect
        echo cd $dc
        echo edit $0 and add your_test
        echo $0 launch your_test [--start v5.14.0 --end v5.15.0]
        ;;
esac

exit

# if you need to invert the exit code, replace the exit in your test with:
[ $ret -eq 0 ] && exit 1
exit 0
