# Copyright 2001-2007, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Report::Html_basic;

use strict;
use warnings;

our $VERSION = "0.61";

use Devel::Cover::DB 0.61;

use Getopt::Long;
use Template 2.00;

my ($Have_highlighter, $Have_PPI, $Have_perltidy);

BEGIN
{
    eval "use PPI; use PPI::HTML;";
    $Have_PPI = !$@;
    eval "use Perl::Tidy";
    $Have_perltidy = !$@;
    $Have_highlighter = $Have_PPI || $Have_perltidy;
}

my $Template;
my %R;
my %Files;

sub print_files
{
    while (my($file, $contents) = each %Files)
    {
        $file = "$R{options}{outputdir}/$file";
        open F, '>', $file or return;
        print F $contents;
        close F;
    }
}

sub oclass
{
    my ($o, $criterion) = @_;
    $o ? class($o->percentage, $o->error, $criterion) : ""
}

sub class
{
    my ($pc, $err, $criterion) = @_;
    return "" if $criterion eq "time";
    !$err ? "c3"
          : $pc <  75 ? "c0"
          : $pc <  90 ? "c1"
          : $pc < 100 ? "c2"
          : "c3"
}

sub get_summary
{
    my ($file, $criterion) = @_;

    my %vals;
    @vals{"pc", "class"} = ("n/a", "");

    my $part = $R{db}->summary($file);
    return \%vals unless exists $part->{$criterion};
    my $c = $part->{$criterion};
    $vals{class} = class($c->{percentage}, $c->{error}, $criterion);

    return \%vals unless defined $c->{percentage};
    $vals{pc}       = sprintf "%4.1f", $c->{percentage};
    $vals{covered}  = $c->{covered} || 0;
    $vals{total}    = $c->{total};
    $vals{details}  = "$vals{covered} / $vals{total}";

    my $cr = $criterion eq "pod" ? "subroutine" : $criterion;
    return \%vals
      if $cr !~ /^branch|condition|subroutine$/ || !exists $R{filenames}{$file};
    $vals{link} = "$R{filenames}{$file}--$cr.html";

    \%vals
};

sub print_summary
{
    my $vars =
    {
        R     => \%R,
        files => [ "Total", grep $R{db}->summary($_), @{$R{options}{file}} ],
    };

    my $html = "$R{options}{outputdir}/$R{options}{option}{outputfile}";
    $Template->process("summary", $vars, $html) or die $Template->error();

    $html
}

sub _highlight_ppi {
    my @all_lines = @_;
    my $code = join "", @all_lines;
    my $document = PPI::Document->new(\$code);
    my $highlight = PPI::HTML->new(line_numbers => 1);
    my $pretty =  $highlight->html($document);

    my $split = '<span class="line_number">';

    # turn significant whitespace into &nbsp;
    @all_lines = map {
        $_ =~ s{</span>( +)}{"</span>" . ("&nbsp;" x length($1))}e;
        "$split$_";
    } split /$split/, $pretty;

    # remove the line number
    @all_lines = map {
        s{<span class="line_number">.*?</span>}{}; $_;
    } @all_lines;
    @all_lines = map {
        s{<span class="line_number">}{}; $_;
    } @all_lines;

    # remove the BR
    @all_lines = map {
        s{<br>$}{}; $_;
    } @all_lines;
    @all_lines = map {
        s{<br>\n</span>}{</span>}; $_;
    } @all_lines;

    shift @all_lines if $all_lines[0] eq "";
    return @all_lines;
}

sub _highlight_perltidy {
    my @all_lines = @_;
    my @coloured = ();

    Perl::Tidy::perltidy(
        source      => \@all_lines, 
        destination => \@coloured, 
        argv        => '-html -pre -nopod2html', 
        stderr      => '-',
        errorfile   => '-',
    );

    # remove the PRE
    shift @coloured;
    pop @coloured;
    @coloured = grep { !/<a name=/ } @coloured;

    return @coloured
}

*_highlight = $Have_PPI      ? \&_highlight_ppi
            : $Have_perltidy ? \&_highlight_perltidy
            : sub {};

sub print_file
{
    my @lines;
    my $f = $R{db}->cover->file($R{file});

    open F, $R{file} or warn("Unable to open $R{file}: $!\n"), return;
    my @all_lines = <F>;

    @all_lines = _highlight(@all_lines) if $Have_highlighter;

    my $linen = 1;
    LINE: while (defined(my $l = shift @all_lines))
    {
        my $n  = $linen++;
        chomp $l;

        my %criteria;
        for my $c (@{$R{showing}})
        {
            my $criterion = $f->$c();
            if ($criterion)
            {
                my $l = $criterion->location($n);
                $criteria{$c} = $l ? [@$l] : undef;
            }
        }

        my $count = 0;
        my $more  = 1;
        while ($more)
        {
            my %line;

            $count++;
            $line{number} = length $n ? $n : "&nbsp;";
            $line{text}   = length $l ? $l : "&nbsp;";

            my $error = 0;
            $more = 0;
            for my $ann (@{$R{options}{annotations}})
            {
                for my $a (0 .. $ann->count - 1)
                {
                    my $text = $ann->text ($R{file}, $n, $a);
                    $text = "&nbsp;" unless $text && length $text;
                    push @{$line{criteria}},
                    {
                        text  => $text,
                        class => $ann->class($R{file}, $n, $a),
                    };
                    $error ||= $ann->error($R{file}, $n, $a);
                }
            }
            for my $c (@{$R{showing}})
            {
                my $o = shift @{$criteria{$c}};
                $more ||= @{$criteria{$c}};
                my $link = $c !~ /statement|time/;
                my $pc = $link && $c !~ /subroutine|pod/;
                my $text = $o ? $pc ? $o->percentage : $o->covered : "&nbsp;";
                my %criterion = ( text => $text, class => oclass($o, $c) );
                my $cr = $c eq "pod" ? "subroutine" : $c;
                $criterion{link} = "$R{filenames}{$R{file}}--$cr.html#$n-$count"
                    if $o && $link;
                push @{$line{criteria}}, \%criterion;
                $error ||= $o->error if $o;
            }

            push @lines, \%line;

            last LINE if $l =~ /^__(END|DATA)__/;
            $n = $l = "";
        }
    }
    close F or die "Unable to close $R{file}: $!";

    my $vars =
    {
        R     => \%R,
        lines => \@lines,
    };

    my $html = "$R{options}{outputdir}/$R{filenames}{$R{file}}.html";
    $Template->process("file", $vars, $html) or die $Template->error();
}

sub print_branches
{
    my $branches = $R{db}->cover->file($R{file})->branch;
    return unless $branches;

    my @branches;
    for my $location (sort { $a <=> $b } $branches->items)
    {
        my $count = 0;
        for my $b (@{$branches->location($location)})
        {
            $count++;
            my $text = $b->text;
            ($text) = _highlight($text) if $Have_highlighter;

            push @branches,
                {
                    number     => $count == 1 ? $location : "",
                    parts      =>
                    [
                        map { text  => $b->value($_),
                              class => class($b->value($_), $b->error($_),
                                             "branch") },
                            0 .. $b->total - 1
                    ],
                    text       => $text,
                };
        }
    }

    my $vars =
    {
        R        => \%R,
        branches => \@branches,
    };

    my $html = "$R{options}{outputdir}/$R{filenames}{$R{file}}--branch.html";
    $Template->process("branches", $vars, $html) or die $Template->error();
}

sub print_conditions
{
    my $conditions = $R{db}->cover->file($R{file})->condition;
    return unless $conditions;

    my %r;
    for my $location (sort { $a <=> $b } $conditions->items)
    {
        my %count;
        for my $c (@{$conditions->location($location)})
        {
            $count{$c->type}++;
            # print "-- [$count{$c->type}][@{[$c->text]}]}]\n";
            my $text = $c->text;
            ($text) = _highlight($text) if $Have_highlighter;

            push @{$r{$c->type}},
                {
                    number     => $count{$c->type} == 1 ? $location : "",
                    condition  => $c,
                    parts      =>
                    [
                        map { text  => $c->value($_),
                              class => class($c->value($_), $c->error($_),
                                             "condition") },
                            0 .. $c->total - 1
                    ],
                    text       => $text,
                };
        }
    }

    my @types = map
               {
                   name       => do { my $n = $_; $n =~ s/_/ /g; $n },
                   headers    => $r{$_}[0]{condition}->headers,
                   conditions => $r{$_},
               }, sort keys %r;

    my $vars =
    {
        R     => \%R,
        types => \@types,
    };

    # use Data::Dumper; print Dumper \@types;

    my $html = "$R{options}{outputdir}/$R{filenames}{$R{file}}--condition.html";
    $Template->process("conditions", $vars, $html) or die $Template->error();
}

sub print_subroutines
{
    my $subroutines = $R{db}->cover->file($R{file})->subroutine;
    return unless $subroutines;
    my $s = $R{options}{show}{subroutine};

    my $pods;
    $pods = $R{db}->cover->file($R{file})->pod if $R{options}{show}{pod};

    my $subs;
    for my $line (sort { $a <=> $b } $subroutines->items)
    {
        my @p;
        if ($pods)
        {
            my $l = $pods->location($line);
            @p = @$l if $l;
        }
        for my $o (@{$subroutines->location($line)})
        {
            my $p = shift @p;
            push @$subs,
            {
                line   => $line,
                name   => $o->name,
                count  => $s ? $o->covered : "",
                class  => $s ? oclass($o, "subroutine") : "",
                pod    => $p ? $p->covered ? "Yes" : "No" : "n/a",
                pclass => $p ? oclass($p, "pod") : "",
            };
        }
    }

    my $vars =
    {
        R    => \%R,
        subs => $subs,
    };

    my $html =
        "$R{options}{outputdir}/$R{filenames}{$R{file}}--subroutine.html";
    $Template->process("subroutines", $vars, $html) or die $Template->error();
}

sub get_options
{
    my ($self, $opt) = @_;
    $opt->{option}{outputfile} = "coverage.html";
    die "Invalid command line options" unless
        GetOptions($opt->{option},
                   qw(
                       outputfile=s
                     ));
}

sub report
{
    my ($pkg, $db, $options) = @_;

    $Template = Template->new
    ({
        LOAD_TEMPLATES =>
        [
            Devel::Cover::Report::Html_basic::Template::Provider->new({}),
        ],
    });

    %R =
    (
        db      => $db,
        date    => do
        {
            my ($sec, $min, $hour, $mday, $mon, $year) = localtime;
            sprintf "%04d-%02d-%02d %02d:%02d:%02d",
                    $year + 1900, $mon + 1, $mday, $hour, $min, $sec
        },
        options => $options,
        showing => [ grep $options->{show}{$_}, $db->criteria ],
        headers =>
        [
            map { ($db->criteria_short)[$_] }
                grep { $options->{show}{($db->criteria)[$_]} }
                     (0 .. $db->criteria - 1)
        ],
        annotations =>
        [
            map { my $a = $_; map $a->header($_), 0 .. $a->count - 1 }
                @{$options->{annotations}}
        ],
        filenames =>
        {
            map { $_ => do { (my $f = $_) =~ s/\W/-/g; $f } }
                @{$options->{file}}
        },
        exists      => { map { $_ => -e } @{$options->{file}} },
        get_summary => \&get_summary,
    );

    print_files;
    my $html = print_summary;

    for (@{$options->{file}})
    {
        $R{file} = $_;
        my $show = $options->{show};
        print_file;
        print_branches    if $show->{branch};
        print_conditions  if $show->{condition};
        print_subroutines if $show->{subroutine} || $show->{pod};
    }

    print "HTML output sent to $html\n";
}

$Files{"cover.css"} = <<'EOF';
/* Stylesheet for Devel::Cover HTML reports */

/* You may modify this file to alter the appearance of your coverage
 * reports. If you do, you should probably flag it read-only to prevent
 * future runs from overwriting it.
 */

/* Note: default values use the color-safe web palette. */

body {
    font-family: sans-serif;
}

h1 {
    text-align         : center;
    background-color   : #cc99ff;
    border             : solid 1px #999999;
    padding            : 0.2em;
    -moz-border-radius : 10px;
}

a {
    color: #000000;
}

a:visited {
    color: #333333;
}

table {
    border-spacing: 0px;
}

tr {
    text-align     : center;
    vertical-align : top;
}

th,.h,.hh,.sh,.sv {
    background-color   : #cccccc;
    border             : solid 1px #333333;
    padding            : 0em 0.2em;
    width              : 2.5em;
    -moz-border-radius : 4px;
}

.hh {
    width: 25%;
}

.sh {
    width       : 0;
    color       : #CD5555;
    font-weight : bold;
    padding     : 0.2em;
}

.sv {
    padding     : 0.2em;
}

td {
    border             : solid 1px #cccccc;
    border-top         : none;
    border-left        : none;
    -moz-border-radius : 4px;
}

.hblank {
    height: 0.5em;
}

.dblank {
    border: none;
}

table.sortable a.sortheader {
  text-decoration: none;
}

/* source code */
pre,.s {
    text-align  : left;
    font-family : monospace;
    white-space : pre;
    padding     : 0.2em 0.5em 0em 0.5em;
}

/* Classes for color-coding coverage information:
 *   c0  : path not covered or coverage < 75%
 *   c1  : coverage >= 75%
 *   c2  : coverage >= 90%
 *   c3  : path covered or coverage = 100%
 */
.c0 {
background-color :           #ff9999;
border           : solid 1px #cc0000;
}
.c1 {
background-color :           #ffcc99;
border           : solid 1px #ff9933;
}
.c2 {
background-color :           #ffff99;
border           : solid 1px #cccc66;
}
.c3 {
background-color :           #99ff99;
border           : solid 1px #009900;
}

/* For syntax highlighting with PPI::HTML */
.line_number     { color: #aaaaaa;                   }
.comment         { color: #228B22;                   }
.symbol          { color: #00688B;                   }
.word            { color: #8B008B; font-weight:bold; }
.pragma          { color: #8B008B; font-weight:bold; }
.structure       { color: #000000;                   }
.number          { color: #B452CD;                   }
.single          { color: #CD5555;                   }
.double          { color: #CD5555;                   }
.match           { color: #CD5555;                   }
.substitute      { color: #CD5555;                   }
.heredoc_content { color: #CD5555;                   }
.interpolate     { color: #CD5555;                   }
.words           { color: #CD5555;                   }

/* for syntax highlighting with Perl::Tidy */
.c  { color: #228B22;                    } /* comment         */
.cm { color: #000000;                    } /* comma           */
.co { color: #000000;                    } /* colon           */
.h  { color: #CD5555; font-weight:bold;  } /* here-doc-target */
.hh { color: #CD5555; font-style:italic; } /* here-doc-text   */
.i  { color: #00688B;                    } /* identifier      */
.j  { color: #000000; font-weight:bold;  } /* label           */
.k  { color: #8B4513; font-weight:bold;  } /* keyword         */
.m  { color: #FF0000; font-weight:bold;  } /* subroutine      */
.n  { color: #B452CD;                    } /* numeric         */
.p  { color: #000000;                    } /* paren           */
.pd { color: #228B22; font-style:italic; } /* pod-text        */
.pu { color: #000000;                    } /* punctuation     */
.q  { color: #CD5555;                    } /* quote           */
.s  { color: #000000;                    } /* structure       */
.sc { color: #000000;                    } /* semicolon       */
.v  { color: #B452CD;                    } /* v-string        */
.w  { color: #000000;                    } /* bareword        */
EOF

$Files{"common.js"} = <<'EOF';
/**
 * addEvent written by Dean Edwards, 2005
 * with input from Tino Zijdel
 *
 * http://dean.edwards.name/weblog/2005/10/add-event/
 * licensed under http://creativecommons.org/licenses/by/2.5/
 **/
function addEvent(element, type, handler) {
	// assign each event handler a unique ID
	if (!handler.$$guid) handler.$$guid = addEvent.guid++;
	// create a hash table of event types for the element
	if (!element.events) element.events = {};
	// create a hash table of event handlers for each element/event pair
	var handlers = element.events[type];
	if (!handlers) {
		handlers = element.events[type] = {};
		// store the existing event handler (if there is one)
		if (element["on" + type]) {
			handlers[0] = element["on" + type];
		}
	}
	// store the event handler in the hash table
	handlers[handler.$$guid] = handler;
	// assign a global event handler to do all the work
	element["on" + type] = handleEvent;
};
// a counter used to create unique IDs
addEvent.guid = 1;

function removeEvent(element, type, handler) {
	// delete the event handler from the hash table
	if (element.events && element.events[type]) {
		delete element.events[type][handler.$$guid];
	}
};

function handleEvent(event) {
	var returnValue = true;
	// grab the event object (IE uses a global event object)
	event = event || fixEvent(window.event);
	// get a reference to the hash table of event handlers
	var handlers = this.events[event.type];
	// execute each event handler
	for (var i in handlers) {
		this.$$handleEvent = handlers[i];
		if (this.$$handleEvent(event) === false) {
			returnValue = false;
		}
	}
	return returnValue;
};

function fixEvent(event) {
	// add W3C standard event methods
	event.preventDefault = fixEvent.preventDefault;
	event.stopPropagation = fixEvent.stopPropagation;
	return event;
};
fixEvent.preventDefault = function() {
	this.returnValue = false;
};
fixEvent.stopPropagation = function() {
	this.cancelBubble = true;
};

// end from Dean Edwards


/**
 * Creates an Element for insertion into the DOM tree.
 * From http://simon.incutio.com/archive/2003/06/15/javascriptWithXML
 *
 * @param element the element type to be created.
 *				e.g. ul (no angle brackets)
 **/
function createElement(element) {
	if (typeof document.createElementNS != 'undefined') {
		return document.createElementNS('http://www.w3.org/1999/xhtml', element);
	}
	if (typeof document.createElement != 'undefined') {
		return document.createElement(element);
	}
	return false;
}

/**
 * "targ" is the element which caused this function to be called
 * from http://www.quirksmode.org/js/events_properties.html
 * see http://www.quirksmode.org/about/copyright.html
 **/
function getEventTarget(e) {
	var targ;
	if (!e) {
		e = window.event;
	}
	if (e.target) {
		targ = e.target;
	} else if (e.srcElement) {
		targ = e.srcElement;
	}
	if (targ.nodeType == 3) { // defeat Safari bug
		targ = targ.parentNode;
	}

	return targ;
}
EOF

$Files{"css.js"} = <<'EOF';
/**
 * Written by Neil Crosby. 
 * http://www.workingwith.me.uk/
 *
 * Use this wherever you want, but please keep this comment at the top of this file.
 *
 * Copyright (c) 2006 Neil Crosby
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy 
 * of this software and associated documentation files (the "Software"), to deal 
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell 
 * copies of the Software, and to permit persons to whom the Software is 
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in 
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE 
 * SOFTWARE.
 **/
var css = {
	/**
	 * Returns an array containing references to all elements
	 * of a given tag type within a certain node which have a given class
	 *
	 * @param node		the node to start from 
	 *					(e.g. document, 
	 *						  getElementById('whateverStartpointYouWant')
	 *					)
	 * @param searchClass the class we're wanting
	 *					(e.g. 'some_class')
	 * @param tag		 the tag that the found elements are allowed to be
	 *					(e.g. '*', 'div', 'li')
	 **/
	getElementsByClass : function(node, searchClass, tag) {
		var classElements = new Array();
		var els = node.getElementsByTagName(tag);
		var elsLen = els.length;
		var pattern = new RegExp("(^|\\s)"+searchClass+"(\\s|$)");
		
		
		for (var i = 0, j = 0; i < elsLen; i++) {
			if (this.elementHasClass(els[i], searchClass) ) {
				classElements[j] = els[i];
				j++;
			}
		}
		return classElements;
	},


	/**
	 * PRIVATE.  Returns an array containing all the classes applied to this
	 * element.
	 *
	 * Used internally by elementHasClass(), addClassToElement() and 
	 * removeClassFromElement().
	 **/
	privateGetClassArray: function(el) {
		return el.className.split(' '); 
	},

	/**
	 * PRIVATE.  Creates a string from an array of class names which can be used 
	 * by the className function.
	 *
	 * Used internally by addClassToElement().
	 **/
	privateCreateClassString: function(classArray) {
		return classArray.join(' ');
	},

	/**
	 * Returns true if the given element has been assigned the given class.
	 **/
	elementHasClass: function(el, classString) {
		if (!el) {
			return false;
		}
		
		var regex = new RegExp('\\b'+classString+'\\b');
		if (el.className.match(regex)) {
			return true;
		}

		return false;
	},

	/**
	 * Adds classString to the classes assigned to the element with id equal to
	 * idString.
	 **/
	addClassToId: function(idString, classString) {
		this.addClassToElement(document.getElementById(idString), classString);
	},

	/**
	 * Adds classString to the classes assigned to the given element.
	 * If the element already has the class which was to be added, then
	 * it is not added again.
	 **/
	addClassToElement: function(el, classString) {
		var classArray = this.privateGetClassArray(el);

		if (this.elementHasClass(el, classString)) {
			return; // already has element so don't need to add it
		}

		classArray.push(classString);

		el.className = this.privateCreateClassString(classArray);
	},

	/**
	 * Removes the given classString from the list of classes assigned to the
	 * element with id equal to idString
	 **/
	removeClassFromId: function(idString, classString) {
		this.removeClassFromElement(document.getElementById(idString), classString);
	},

	/**
	 * Removes the given classString from the list of classes assigned to the
	 * given element.  If the element has the same class assigned to it twice, 
	 * then only the first instance of that class is removed.
	 **/
	removeClassFromElement: function(el, classString) {
		var classArray = this.privateGetClassArray(el);

		for (x in classArray) {
			if (classString == classArray[x]) {
				classArray[x] = '';
				break;
			}
		}

		el.className = this.privateCreateClassString(classArray);
	}
}
EOF

$Files{"standardista-table-sorting.js"} = <<'EOF';
/**
 * Written by Neil Crosby. 
 * http://www.workingwith.me.uk/articles/scripting/standardista_table_sorting
 *
 * This module is based on Stuart Langridge's "sorttable" code.  Specifically, 
 * the determineSortFunction, sortCaseInsensitive, sortDate, sortNumeric, and
 * sortCurrency functions are heavily based on his code.  This module would not
 * have been possible without Stuart's earlier outstanding work.
 *
 * Use this wherever you want, but please keep this comment at the top of this file.
 *
 * Copyright (c) 2006 Neil Crosby
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy 
 * of this software and associated documentation files (the "Software"), to deal 
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell 
 * copies of the Software, and to permit persons to whom the Software is 
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in 
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE 
 * SOFTWARE.
 **/
var standardistaTableSorting = {

	that: false,
	isOdd: false,

	sortColumnIndex : -1,
	lastAssignedId : 0,
	newRows: -1,
	lastSortedTable: -1,

	/**
	 * Initialises the Standardista Table Sorting module
	 **/
	init : function() {
		// first, check whether this web browser is capable of running this script
		if (!document.getElementsByTagName) {
			return;
		}
		
		this.that = this;
		
		this.run();
		
	},
	
	/**
	 * Runs over each table in the document, making it sortable if it has a class
	 * assigned named "sortable" and an id assigned.
	 **/
	run : function() {
		var tables = document.getElementsByTagName("table");
		
		for (var i=0; i < tables.length; i++) {
			var thisTable = tables[i];
			
			if (css.elementHasClass(thisTable, 'sortable')) {
				this.makeSortable(thisTable);
			}
		}
	},
	
	/**
	 * Makes the given table sortable.
	 **/
	makeSortable : function(table) {
	
		// first, check if the table has an id.  if it doesn't, give it one
		if (!table.id) {
			table.id = 'sortableTable'+this.lastAssignedId++;
		}
		
		// if this table does not have a thead, we don't want to know about it
		if (!table.tHead || !table.tHead.rows || 0 == table.tHead.rows.length) {
			return;
		}
		
		// we'll assume that the last row of headings in the thead is the row that 
		// wants to become clickable
		var row = table.tHead.rows[table.tHead.rows.length - 1];
		
		for (var i=0; i < row.cells.length; i++) {
		
			// create a link with an onClick event which will 
			// control the sorting of the table
			var linkEl = createElement('a');
			linkEl.href = '#';
			linkEl.onclick = this.headingClicked;
			linkEl.setAttribute('columnId', i);
			linkEl.title = 'Click to sort';
			// add class - pjcj
			linkEl.className = 'sortheader';
			
			// move the current contents of the cell that we're 
			// hyperlinking into the hyperlink
			var innerEls = row.cells[i].childNodes;
			for (var j = 0; j < innerEls.length; j++) {
				linkEl.appendChild(innerEls[j]);
			}
			
			// and finally add the new link back into the cell
			row.cells[i].appendChild(linkEl);
			
			// Don't add space for arrow until we sort - pjcj
			// var spanEl = createElement('span');
			// spanEl.className = 'tableSortArrow';
			// spanEl.appendChild(document.createTextNode('\u00A0\u00A0'));
			// row.cells[i].appendChild(spanEl);

		}
	
		if (css.elementHasClass(table, 'autostripe')) {
			this.isOdd = false;
			var rows = table.tBodies[0].rows;
		
			// We appendChild rows that already exist to the tbody, so it moves them rather than creating new ones
			for (var i=0;i<rows.length;i++) { 
				this.doStripe(rows[i]);
			}
		}
	},
	
	headingClicked: function(e) {
		
		var that = standardistaTableSorting.that;
		
		// linkEl is the hyperlink that was clicked on which caused
		// this method to be called
		var linkEl = getEventTarget(e);
		
		// directly outside it is a td, tr, thead and table
		var td     = linkEl.parentNode;
		var tr     = td.parentNode;
		var thead  = tr.parentNode;
		var table  = thead.parentNode;
		
		// if the table we're looking at doesn't have any rows
		// (or only has one) then there's no point trying to sort it
		if (!table.tBodies || table.tBodies[0].rows.length <= 1) {
			return false;
		}

		// the column we want is indicated by td.cellIndex
		var column = linkEl.getAttribute('columnId') || td.cellIndex;
		//var column = td.cellIndex;
		
		// find out what the current sort order of this column is
		var arrows = css.getElementsByClass(td, 'tableSortArrow', 'span');
		var previousSortOrder = '';
		if (arrows.length > 0) {
			previousSortOrder = arrows[0].getAttribute('sortOrder');
		}
		
		// work out how we want to sort this column using the data in the first cell
		// but just getting the first cell is no good if it contains no data
		// so if the first cell just contains white space then we need to track
		// down until we find a cell which does contain some actual data
		var itm = ''
		var rowNum = 0;
		while ('' == itm && rowNum < table.tBodies[0].rows.length) {
			itm = that.getInnerText(table.tBodies[0].rows[rowNum].cells[column]);
			rowNum++;
		}
		var sortfn = that.determineSortFunction(itm);

		// if the last column that was sorted was this one, then all we need to 
		// do is reverse the sorting on this column
		if (table.id == that.lastSortedTable && column == that.sortColumnIndex) {
			newRows = that.newRows;
			newRows.reverse();
		// otherwise, we have to do the full sort
		} else {
			that.sortColumnIndex = column;
			var newRows = new Array();

			for (var j = 0; j < table.tBodies[0].rows.length; j++) { 
				newRows[j] = table.tBodies[0].rows[j]; 
			}

			newRows.sort(sortfn);
		}

		that.moveRows(table, newRows);
		that.newRows = newRows;
		that.lastSortedTable = table.id;
		
		// now, give the user some feedback about which way the column is sorted
		
		// first, get rid of any arrows in any heading cells
		var arrows = css.getElementsByClass(tr, 'tableSortArrow', 'span');
		for (var j = 0; j < arrows.length; j++) {
			var arrowParent = arrows[j].parentNode;
			arrowParent.removeChild(arrows[j]);

			if (arrowParent != td) {
				spanEl = createElement('span');
				spanEl.className = 'tableSortArrow';
				spanEl.appendChild(document.createTextNode('\u00A0\u00A0'));
				arrowParent.appendChild(spanEl);
			}
		}
		
		// now, add back in some feedback 
		var spanEl = createElement('span');
		spanEl.className = 'tableSortArrow';
		if (null == previousSortOrder || '' == previousSortOrder || 'DESC' == previousSortOrder) {
			spanEl.appendChild(document.createTextNode(' \u2191'));
			spanEl.setAttribute('sortOrder', 'ASC');
		} else {
			spanEl.appendChild(document.createTextNode(' \u2193'));
			spanEl.setAttribute('sortOrder', 'DESC');
		}
		
		td.appendChild(spanEl);
		
		return false;
	},

	getInnerText : function(el) {
		
		if ('string' == typeof el || 'undefined' == typeof el) {
			return el;
		}
		
		if (el.innerText) {
			return el.innerText;  // Not needed but it is faster
		}

		var str = el.getAttribute('standardistaTableSortingInnerText');
		if (null != str && '' != str) {
			return str;
		}
		str = '';

		var cs = el.childNodes;
		var l = cs.length;
		for (var i = 0; i < l; i++) {
			// 'if' is considerably quicker than a 'switch' statement, 
			// in Internet Explorer which translates up to a good time 
			// reduction since this is a very often called recursive function
			if (1 == cs[i].nodeType) { // ELEMENT NODE
				str += this.getInnerText(cs[i]);
				break;
			} else if (3 == cs[i].nodeType) { //TEXT_NODE
				str += cs[i].nodeValue;
				break;
			}
		}
		
		// set the innertext for this element directly on the element
		// so that it can be retrieved early next time the innertext
		// is requested
		el.setAttribute('standardistaTableSortingInnerText', str);
		
		return str;
	},

	determineSortFunction : function(itm) {
		
		var sortfn = this.sortCaseInsensitive;
		
		/*
		
		Only need the modified numeric column
		
		if (itm.match(/^\d\d[\/-]\d\d[\/-]\d\d\d\d$/)) {
			sortfn = this.sortDate;
		}
		if (itm.match(/^\d\d[\/-]\d\d[\/-]\d\d$/)) {
			sortfn = this.sortDate;
		}
		if (itm.match(/^[£$]/)) {
			sortfn = this.sortCurrency;
		}
		if (itm.match(/^\d?\.?\d+$/)) {
			sortfn = this.sortNumeric;
		}
		if (itm.match(/^[+-]?\d*\.?\d+([eE]-?\d+)?$/)) {
			sortfn = this.sortNumeric;
		}
    		if (itm.match(/^([01]?\d\d?|2[0-4]\d|25[0-5])\.([01]?\d\d?|2[0-4]\d|25[0-5])\.([01]?\d\d?|2[0-4]\d|25[0-5])\.([01]?\d\d?|2[0-4]\d|25[0-5])$/)) {
        		sortfn = this.sortIP;
   		}
		*/
		
		sortfn = this.sortNumeric;
		return sortfn;
	},
	
	sortCaseInsensitive : function(a, b) {
		var that = standardistaTableSorting.that;
		
		var aa = that.getInnerText(a.cells[that.sortColumnIndex]).toLowerCase();
		var bb = that.getInnerText(b.cells[that.sortColumnIndex]).toLowerCase();
		if (aa==bb) {
			return 0;
		} else if (aa<bb) {
			return -1;
		} else {
			return 1;
		}
	},
	
	sortDate : function(a,b) {
		var that = standardistaTableSorting.that;

		// y2k notes: two digit years less than 50 are treated as 20XX, greater than 50 are treated as 19XX
		var aa = that.getInnerText(a.cells[that.sortColumnIndex]);
		var bb = that.getInnerText(b.cells[that.sortColumnIndex]);
		
		var dt1, dt2, yr = -1;
		
		if (aa.length == 10) {
			dt1 = aa.substr(6,4)+aa.substr(3,2)+aa.substr(0,2);
		} else {
			yr = aa.substr(6,2);
			if (parseInt(yr) < 50) { 
				yr = '20'+yr; 
			} else { 
				yr = '19'+yr; 
			}
			dt1 = yr+aa.substr(3,2)+aa.substr(0,2);
		}
		
		if (bb.length == 10) {
			dt2 = bb.substr(6,4)+bb.substr(3,2)+bb.substr(0,2);
		} else {
			yr = bb.substr(6,2);
			if (parseInt(yr) < 50) { 
				yr = '20'+yr; 
			} else { 
				yr = '19'+yr; 
			}
			dt2 = yr+bb.substr(3,2)+bb.substr(0,2);
		}
		
		if (dt1==dt2) {
			return 0;
		} else if (dt1<dt2) {
			return -1;
		}
		return 1;
	},

	sortCurrency : function(a,b) { 
		var that = standardistaTableSorting.that;

		var aa = that.getInnerText(a.cells[that.sortColumnIndex]).replace(/[^0-9.]/g,'');
		var bb = that.getInnerText(b.cells[that.sortColumnIndex]).replace(/[^0-9.]/g,'');
		return parseFloat(aa) - parseFloat(bb);
	},

	sortNumeric : function(a,b) { 
		var that = standardistaTableSorting.that;
		if ( that.getInnerText(a.cells[that.sortColumnIndex]) == 'n/a' ) return -1;
		if ( that.getInnerText(b.cells[that.sortColumnIndex]) == 'n/a' ) return 1;
		
		var aa = parseFloat(that.getInnerText(a.cells[that.sortColumnIndex]));
		if (isNaN(aa)) { 
			aa = 0;
		}
		var bb = parseFloat(that.getInnerText(b.cells[that.sortColumnIndex])); 
		if (isNaN(bb)) { 
			bb = 0;
		}
		return aa-bb;
	},

	makeStandardIPAddress : function(val) {
		var vals = val.split('.');

		for (x in vals) {
			val = vals[x];

			while (3 > val.length) {
				val = '0'+val;
			}
			vals[x] = val;
		}

		val = vals.join('.');

		return val;
	},

	sortIP : function(a,b) { 
		var that = standardistaTableSorting.that;

		var aa = that.makeStandardIPAddress(that.getInnerText(a.cells[that.sortColumnIndex]).toLowerCase());
		var bb = that.makeStandardIPAddress(that.getInnerText(b.cells[that.sortColumnIndex]).toLowerCase());
		if (aa==bb) {
			return 0;
		} else if (aa<bb) {
			return -1;
		} else {
			return 1;
		}
	},

	moveRows : function(table, newRows) {
		this.isOdd = false;

		// We appendChild rows that already exist to the tbody, so it moves them rather than creating new ones
		for (var i=0;i<newRows.length;i++) { 
			var rowItem = newRows[i];

			this.doStripe(rowItem);

			table.tBodies[0].appendChild(rowItem); 
		}
	},
	
	doStripe : function(rowItem) {
		if (this.isOdd) {
			css.addClassToElement(rowItem, 'odd');
		} else {
			css.removeClassFromElement(rowItem, 'odd');
		}
		
		this.isOdd = !this.isOdd;
	}

}

function standardistaTableSortingInit() {
	standardistaTableSorting.init();
}

addEvent(window, 'load', standardistaTableSortingInit)
EOF

1;

package Devel::Cover::Report::Html_basic::Template::Provider;

use strict;
use warnings;

our $VERSION = "0.61";

use base "Template::Provider";

my %Templates;

sub fetch
{
    my $self = shift;
    my ($name) = @_;
    # print "Looking for <$name>\n";
    $self->SUPER::fetch(exists $Templates{$name} ? \$Templates{$name} : $name)
}

$Templates{html} = <<'EOT';
<!DOCTYPE html
     PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
     "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<!--
This file was generated by Devel::Cover Version 0.61
Devel::Cover is copyright 2001-2007, Paul Johnson (pjcj@cpan.org)
Devel::Cover is free. It is licensed under the same terms as Perl itself.
The latest version of Devel::Cover should be available from my homepage:
http://www.pjcj.net
-->
<head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"></meta>
    <meta http-equiv="Content-Language" content="en-us"></meta>
    <link rel="stylesheet" type="text/css" href="cover.css"></link>
    <script type="text/javascript" src="common.js"></script>
    <script type="text/javascript" src="css.js"></script>
    <script type="text/javascript" src="standardista-table-sorting.js"></script>
    <title> [% title || "Coverage Summary" %] </title>
</head>
<body>
    [% content %]
</body>
</html>
EOT

$Templates{header} = <<'EOT';
<table>
    <tr>
        <th colspan="4">[% R.file %]</th>
    </tr>
    <tr class="hblank"><td class="dblank"></td></tr>
    <tr>
        <th class="hh">Criterion</th>
        <th class="hh">Covered</th>
        <th class="hh">Total</th>
        <th class="hh">%</th>
    </tr>
    [% FOREACH criterion = criteria %]
        [% vals = R.get_summary(R.file, criterion) %]
        <tr>
            <td class="h">[% criterion %]</td>
            <td>[% vals.covered %]</td>
            <td>[% vals.total %]</td>
            <td [% IF vals.class %]class="[% vals.class %]" [% END %]title="[% vals.details %]">
                [% IF vals.link.defined %]
                    <a href="[% vals.link %]"> [% vals.pc %] </a>
                [% ELSE %]
                    [% vals.pc %]
                [% END %]
            </td>
        </tr>
    [% END %]
</table>
<div><br></br></div>
EOT

$Templates{summary} = <<'EOT';
[% WRAPPER html %]

<h1> Coverage Summary </h1>
<table>
    <tr>
        <td class="sh" align="right">Database:</td>
        <td class="sv" align="left">[% R.db.db %]</td>
    </tr>
    <tr>
        <td class="sh" align="right">Report date:</td>
        <td class="sv" align="left">[% R.date %]</td>
    </tr>
</table>
<div><br></br></div>
<table class="sortable" id="coverage_table">
    <thead>
        <tr>
            <th> file </th>
            [% FOREACH header = R.headers %]
                <th> [% header %] </th>
            [% END %]
            <th> total </th>
        </tr>
    </thead>

    <tfoot>
    [% FOREACH file = files %]
        <tr align="center" valign="top">
            <td align="left">
                [% IF R.exists.$file %]
                   <a href="[% R.filenames.$file %].html"> [% file %] </a>
                [% ELSE %]
                    [% file %]
                [% END %]
            </td>

            [% FOREACH criterion = R.showing %]
                [% vals = R.get_summary(file, criterion) %]
                [% IF vals.class %]
                    <td class="[% vals.class %]" title="[% vals.details %]">
                [% ELSE %]
                    <td>
                [% END %]
                [% IF vals.link.defined %]
                    <a href="[% vals.link %]"> [% vals.pc %] </a>
                [% ELSE %]
                    [% vals.pc %]
                [% END %]
                </td>
            [% END %]

            [% vals = R.get_summary(file, "total") %]
            <td class="[% vals.class %]" title="[% vals.details %]">
                [% vals.pc %]
            </td>
        </tr>

        [% IF file == "Total" %]
            </tfoot>
            <tbody>
        [% END %]
    [% END %]
    </tbody>
</table>

[% END %]
EOT

$Templates{file} = <<'EOT';
[% WRAPPER html %]

<h1> File Coverage </h1>

[%
   crit = [];
   FOREACH criterion = R.showing;
       crit.push(criterion) UNLESS criterion == "time";
   END;
   crit.push("total");
   PROCESS header criteria = crit;
%]

<table>
    <tr>
        <th> line </th>
        [% FOREACH header = R.annotations.merge(R.headers) %]
            <th> [% header %] </th>
        [% END %]
        <th> code </th>
    </tr>

    [% FOREACH line = lines %]
        <tr>
            <td [% IF line.number %] class="h" [% END %]>
                <a [% IF line.number != '&nbsp;' %]name="[% line.number %]"[% END %]>[% line.number %]</a>
            </td>
            [% FOREACH cr = line.criteria %]
                <td [% IF cr.class %] class="[% cr.class %]" [% END %]>
                    [% IF cr.link.defined %] <a href="[% cr.link %]"> [% END %]
                    [% cr.text %]
                    [% IF cr.link.defined %] </a> [% END %]
                </td>
            [% END %]
            <td class="s"> [% line.text %] </td>
        </tr>
    [% END %]
</table>

[% END %]
EOT

$Templates{branches} = <<'EOT';
[% WRAPPER html %]

<h1> Branch Coverage </h1>

[% PROCESS header criteria = [ "branch" ] %]

<table>
    <tr>
        <th> line </th>
        <th> true </th>
        <th> false </th>
        <th> branch </th>
    </tr>

    [% FOREACH branch = branches %]
        <a name="[% branch.ref %]"> </a>
        <tr>
            <td class="h"> [% branch.number %] </td>
            [% FOREACH part = branch.parts %]
                <td class="[% part.class %]"> [% part.text %] </td>
            [% END %]
            <td class="s"> [% branch.text %] </td>
        </tr>
    [% END %]
</table>

[% END %]
EOT

$Templates{conditions} = <<'EOT';
[% WRAPPER html %]

<h1> Condition Coverage </h1>

[% PROCESS header criteria = [ "condition" ] %]

[% FOREACH type = types %]
    <h2> [% type.name %] conditions </h2>

    <table>
        <tr>
            <th> line </th>
            [% FOREACH header = type.headers %]
                <th> [% header %] </th>
            [% END %]
            <th> condition </th>
        </tr>

        [% FOREACH condition = type.conditions %]
            <a name="[% condition.ref %]"> </a>
            <tr>
                <td class="h"> [% condition.number %] </td>
                [% FOREACH part = condition.parts %]
                    <td class="[% part.class %]"> [% part.text %] </td>
                [% END %]
                <td class="s"> [% condition.text %] </td>
            </tr>
        [% END %]
    </table>
[% END %]

[% END %]
EOT

$Templates{subroutines} = <<'EOT';
[% WRAPPER html %]

<h1> Subroutine Coverage </h1>

[%
   crit = [];
   crit.push("subroutine") IF R.options.show.subroutine;
   crit.push("pod")        IF R.options.show.pod;
   PROCESS header criteria = crit;
%]

<table>
    <tr>
        <th> line </th>
        [% IF R.options.show.subroutine %]
            <th> count </th>
        [% END %]
        [% IF R.options.show.pod %]
            <th> pod </th>
        [% END %]
        <th> subroutine </th>
    </tr>
    [% FOREACH sub = subs %]
        <tr>
            <td class="h"> [% sub.line %] </td>
            [% IF R.options.show.subroutine %]
                <td class="[% sub.class %]"> [% sub.count %] </td>
            [% END %]
            [% IF R.options.show.pod %]
                <td class="[% sub.pclass %]"> [% sub.pod %] </td>
            [% END %]
            <td> [% sub.name %] </td>
        </tr>
    [% END %]
</table>

[% END %]
EOT

# remove some whitespace from templates
s/^\s+//gm for values %Templates;

1;

=head1 NAME

Devel::Cover::Report::Html_basic - Backend for HTML reporting of coverage
statistics

=head1 SYNOPSIS

 use Devel::Cover::Report::Html_basic;

 Devel::Cover::Report::Html_basic->report($db, $options);

=head1 DESCRIPTION

This module provides a HTML reporting mechanism for coverage data.  It
is designed to be called from the C<cover> program. It will add syntax
highlighting if C<PPI::HTML> or C<Perl::Tidy> is installed.

=head1 SEE ALSO

 Devel::Cover

=head1 BUGS

Huh?

=head1 VERSION

Version 0.61 - 10th January 2007

=head1 LICENCE

Copyright 2001-2007, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut
