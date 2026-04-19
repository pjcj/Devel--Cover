# Copyright 2007-2026, Paul Johnson (paul@pjcj.net)
# except where otherwise noted.

# This software is free.  It is licensed under the same terms as Perl itself,
# except where otherwise noted.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Web;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use Exporter qw( import );

our @EXPORT_OK = qw( write_file $Cov $Crisp_base_css $Crisp_theme_js );

our $Cov = {
  light => {
    none => { bg => "#ffcccc", border => "#dd0000", fg => "#990000" },
    low  => { bg => "#fce8c8", border => "#c08820", fg => "#7a5810" },
    good => { bg => "#c8e4f0", border => "#2080a8", fg => "#104860" },
    full => { bg => "#b0f0b0", border => "#008800", fg => "#005500" },
  },
  dark => {
    none => { bg => "#5c2020", border => "#ff4444", fg => "#ffcccc" },
    low  => { bg => "#523c14", border => "#e0a830", fg => "#f0d888" },
    good => { bg => "#1a4858", border => "#48c0e0", fg => "#98d8f0" },
    full => { bg => "#1a5a1a", border => "#44dd44", fg => "#bbffbb" },
  },
};

sub _hex_rgb ($hex) {
  map { hex } $hex =~ /[0-9a-f]{2}/gi
}

sub _rgb_hex (@rgb) {
  sprintf "#%02x%02x%02x", @rgb
}

sub _mix ($c1, $c2, $ratio) {
  my @a = _hex_rgb($c1);
  my @b = _hex_rgb($c2);
  _rgb_hex(map { int($a[$_] * $ratio + $b[$_] * (1 - $ratio) + 0.5) } 0 .. 2)
}

sub _cov_vars ($theme, $indent) {
  my $c  = $Cov->{$theme};
  my $bg = $theme eq "light" ? "#ffffff" : "#000000";
  my $r  = $theme eq "light" ? 0.45      : 0.35;
  join "", (
    map {
      my $n = $_;
      map "$indent--cov-$n-$_: $c->{$n}{$_};\n", qw( bg border fg )
    } qw( none low good full )
    ),
    "\n", "${indent}--exec-none: " . _mix($c->{none}{border}, $bg, $r) . ";\n",
    "${indent}--exec-partial: " . _mix($c->{low}{border},  $bg, $r) . ";\n",
    "${indent}--exec-covered: " . _mix($c->{full}{border}, $bg, $r) . ";\n",
}

my %Files;

sub write_file ($directory, $file) {
  my @files = $file eq "all" ? keys %Files : $file eq "js" ? grep /\.js$/,
    keys %Files : $file eq "css" ? grep /\.css$/, keys %Files : ($file);
  for my $f (@files) {
    my $contents = $Files{$f} // next;
    my $path     = "$directory/$f";
    open my $fh, ">", $path or die "Can't open $path: $!\n";
    print $fh $contents;
    close $fh or die "Can't close $path: $!\n";
  }
}

my $Common_css = <<'EOF';
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

th,.h,.hh {
  background-color   : #cccccc;
  border             : solid 1px #333333;
  padding            : 0em 0.2em;
  -moz-border-radius : 4px;
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
EOF

my $Extra_css = <<'EOF';

.sh,.sv {
  background-color   : #cccccc;
  border             : solid 1px #333333;
  padding            : 0em 0.2em;
  -moz-border-radius : 4px;
}

.sh {
  color       : #CD5555;
  font-weight : bold;
  padding     : 0.2em;
}

.sv {
  padding : 0.2em;
}

table.sortable a.sortheader {
  text-decoration: none;
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

our $Crisp_base_css = <<'CSS';
/* Devel::Cover shared stylesheet */

:root {
  --prefix-bg: #e4edf6;
  --prefix-border: #a0bcd8;
  --prefix-label: #4a6f96;

  /*COV:light:  */

  --untested-bar: #bbb;
  --untested-badge-bg: #e0eaf4;
  --untested-badge-fg: #3060a0;
  --untested-badge-border: #90b0d0;
  --untested-worst-bg: #e8e8e8;
  --untested-worst-fg: #666;

  --tip-glass-bg: rgba(255, 255, 255, 0.92);
  --tip-glass-fg: #1a1a1a;
  --tip-glass-border: rgba(0, 0, 0, 0.12);
  --tip-glass-sep: rgba(0, 0, 0, 0.2);
  --tip-c0: #dd0000;
  --tip-c1: #c08820;
  --tip-c2: #2080a8;
  --tip-c3: #008800;

  --bg: #ffffff;
  --bg-alt: #e8ecf0;
  --fg: #1a1a1a;
  --fg-muted: #6c757d;
  --border: #dee2e6;
  --link: #1565c0;
  --link-visited: #4a148c;
  --header-bg: #f5f5f5;

  --syn-comment: #7c8a94;
  --syn-keyword: #7b6daa;
  --syn-string: #4a8a52;
  --syn-number: #b8893a;
  --syn-symbol: #4a5568;
  --syn-operator: #5a9991;
  --syn-structure: #7b6daa;
  --syn-core: #5a87ab;
  --syn-pragma: #9a8a3a;
  --syn-magic: #b87a4a;

  --font-body: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
               "Helvetica Neue", Arial, sans-serif;
  --font-code: "SFMono-Regular", Menlo, Monaco, Consolas, "Liberation Mono",
               monospace;
  --font-size-base: 14px;
  --font-size-code: 13px;
  --font-size-small: 12px;
}

@media (prefers-color-scheme: dark) {
  :root {
    --prefix-bg: #1a2a3d;
    --prefix-border: #3a6090;
    --prefix-label: #80b0e0;

    /*COV:dark:    */

    --untested-bar: #555;
    --untested-badge-bg: #1a2a3d;
    --untested-badge-fg: #90c0f0;
    --untested-badge-border: #4080c0;
    --untested-worst-bg: #333;
    --untested-worst-fg: #bbb;

    --tip-glass-bg: rgba(20, 20, 20, 0.92);
    --tip-glass-fg: #e0e0e0;
    --tip-glass-border: rgba(255, 255, 255, 0.12);
    --tip-glass-sep: rgba(255, 255, 255, 0.2);
    --tip-c0: #ff4444;
    --tip-c1: #e0a830;
    --tip-c2: #48c0e0;
    --tip-c3: #44dd44;

    --bg: #1a1a1a;
    --bg-alt: #242424;
    --fg: #e0e0e0;
    --fg-muted: #9e9e9e;
    --border: #424242;
    --link: #64b5f6;
    --link-visited: #ce93d8;
    --header-bg: #2a2a2a;

    --syn-comment: #6a7a84;
    --syn-keyword: #8a84b0;
    --syn-string: #7ab882;
    --syn-number: #cca86a;
    --syn-symbol: #b0b8c0;
    --syn-operator: #8abab4;
    --syn-structure: #8a84b0;
    --syn-core: #8aa8c4;
    --syn-pragma: #ccbe6a;
    --syn-magic: #c89a6a;
  }
}

html[data-theme="dark"] {
  --prefix-bg: #1a2a3d;
  --prefix-border: #3a6090;
  --prefix-label: #80b0e0;

  /*COV:dark:  */

  --untested-bar: #555;
  --untested-badge-bg: #1a2a3d;
  --untested-badge-fg: #90c0f0;
  --untested-badge-border: #4080c0;
  --untested-worst-bg: #333;
  --untested-worst-fg: #bbb;

  --tip-glass-bg: rgba(20, 20, 20, 0.92);
  --tip-glass-fg: #e0e0e0;
  --tip-glass-border: rgba(255, 255, 255, 0.12);
  --tip-glass-sep: rgba(255, 255, 255, 0.2);
  --tip-c0: #ff4444;
  --tip-c1: #e0a830;
  --tip-c2: #48c0e0;
  --tip-c3: #44dd44;

  --bg: #1a1a1a;
  --bg-alt: #242424;
  --fg: #e0e0e0;
  --fg-muted: #9e9e9e;
  --border: #424242;
  --link: #64b5f6;
  --link-visited: #ce93d8;
  --header-bg: #2a2a2a;

  --syn-comment: #6a7a84;
  --syn-keyword: #8a84b0;
  --syn-string: #7ab882;
  --syn-number: #cca86a;
  --syn-symbol: #b0b8c0;
  --syn-operator: #8abab4;
  --syn-structure: #8a84b0;
  --syn-core: #8aa8c4;
  --syn-pragma: #ccbe6a;
  --syn-magic: #c89a6a;
}

html[data-theme="light"] {
  --prefix-bg: #e4edf6;
  --prefix-border: #a0bcd8;
  --prefix-label: #4a6f96;

  /*COV:light:  */

  --untested-bar: #bbb;
  --untested-badge-bg: #e0eaf4;
  --untested-badge-fg: #3060a0;
  --untested-badge-border: #90b0d0;
  --untested-worst-bg: #e8e8e8;
  --untested-worst-fg: #666;

  --tip-glass-bg: rgba(255, 255, 255, 0.92);
  --tip-glass-fg: #1a1a1a;
  --tip-glass-border: rgba(0, 0, 0, 0.12);
  --tip-glass-sep: rgba(0, 0, 0, 0.2);
  --tip-c0: #dd0000;
  --tip-c1: #c08820;
  --tip-c2: #2080a8;
  --tip-c3: #008800;

  --bg: #ffffff;
  --bg-alt: #e8ecf0;
  --fg: #1a1a1a;
  --fg-muted: #6c757d;
  --border: #dee2e6;
  --link: #1565c0;
  --link-visited: #4a148c;
  --header-bg: #f5f5f5;

  --syn-comment: #7c8a94;
  --syn-keyword: #7b6daa;
  --syn-string: #4a8a52;
  --syn-number: #b8893a;
  --syn-symbol: #4a5568;
  --syn-operator: #5a9991;
  --syn-structure: #7b6daa;
  --syn-core: #5a87ab;
  --syn-pragma: #9a8a3a;
  --syn-magic: #b87a4a;
}

*, *::before, *::after { box-sizing: border-box; }

body {
  margin: 0;
  padding: 0;
  font-family: var(--font-body);
  font-size: var(--font-size-base);
  color: var(--fg);
  background:
    radial-gradient(
      ellipse at 50% 0%, var(--bg-alt) 0%, var(--bg) 70%)
    no-repeat var(--bg);
  line-height: 1.5;
}

a { color: var(--link); text-decoration: none; }
a:hover { text-decoration: underline; }
a:visited { color: var(--link-visited); }

/* Header bar */

.header {
  background: var(--header-bg);
  border-bottom: 1px solid var(--border);
  padding: 12px 24px;
  position: sticky;
  top: 0;
  z-index: 10;
}

.header-inner {
  max-width: 1400px;
  margin: 0 auto;
  display: flex;
  align-items: center;
  gap: 24px;
  flex-wrap: wrap;
}

.header h1 {
  margin: 0;
  font-size: 18px;
  font-weight: 700;
  letter-spacing: -0.02em;
  background: none;
  border: none;
  padding: 0;
  text-align: left;
  flex-shrink: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.header-stats {
  display: flex;
  gap: 16px;
  align-items: center;
  flex-wrap: nowrap;
  flex-shrink: 0;
  margin-left: auto;
}

.theme-toggle, .help-toggle {
  background: none;
  border: 1px solid var(--border);
  border-radius: 4px;
  padding: 4px 8px;
  cursor: pointer;
  color: var(--fg);
  font-size: var(--font-size-small);
  transition: background 0.15s ease, border-color 0.15s ease;
}

.theme-toggle:hover, .help-toggle:hover { background: var(--bg-alt); }

/* Coverage classes */

.c0 {
  background: var(--cov-none-bg);
  border-color: var(--cov-none-border);
  color: var(--cov-none-fg);
}
.c1 {
  background: var(--cov-low-bg);
  border-color: var(--cov-low-border);
  color: var(--cov-low-fg);
}
.c2 {
  background: var(--cov-good-bg);
  border-color: var(--cov-good-border);
  color: var(--cov-good-fg);
}
.c3 {
  background: var(--cov-full-bg);
  border-color: var(--cov-full-border);
  color: var(--cov-full-fg);
}
.na {
  background: var(--bg);
  border-color: var(--border);
  color: var(--fg-muted);
}

/* Main content */

.content {
  max-width: 1400px;
  margin: 0 auto;
  padding: 16px 24px;
}

.footer {
  text-align: center;
  padding: 24px;
  font-size: var(--font-size-small);
  color: var(--fg-muted);
  border-top: 1px solid var(--border);
  margin-top: 24px;
}

/* Glass tooltips */

.tip-hover {
  position: relative;
  cursor: default;
}
.tip-hover:hover { z-index: 30; }

.glass-tip {
  display: none;
  position: absolute;
  bottom: 100%;
  left: 50%;
  transform: translateX(-50%);
  padding: 4px 10px;
  border-radius: 4px;
  font-size: 13px;
  font-weight: 600;
  white-space: nowrap;
  background: var(--tip-glass-bg);
  color: var(--tip-glass-fg);
  border: 1px solid var(--tip-glass-border);
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  z-index: 30;
  pointer-events: none;
}

.tip-hover:hover > .glass-tip { display: block; }

/* Coverage bar */

.cov-bar {
  display: inline-block;
  width: 40px;
  height: 8px;
  background: var(--cov-none-border);
  border-radius: 4px;
  vertical-align: middle;
  margin-left: 4px;
  overflow: hidden;
  box-shadow: inset 0 1px 2px rgba(0,0,0,0.15);
}

.cov-bar-fill {
  display: block;
  height: 100%;
  background: var(--cov-full-border);
  border-radius: 4px;
}

.name-short { display: none; }
CSS

$Crisp_base_css =~ s{/\*COV:(\w+):(\s+)\*/}{_cov_vars($1, $2)}ge;

our $Crisp_theme_js = <<'JS';
/* Devel::Cover theme toggle */
(function() {
  var toggle = document.querySelector(".theme-toggle");
  if (!toggle) return;
  var stored = localStorage.getItem("dc-theme");
  if (stored) document.documentElement.setAttribute("data-theme", stored);
  toggle.addEventListener("click", function() {
    var current = document.documentElement.getAttribute("data-theme");
    var isDark = current === "dark" ||
      (!current && window.matchMedia("(prefers-color-scheme: dark)").matches);
    var next = isDark ? "light" : "dark";
    document.documentElement.setAttribute("data-theme", next);
    localStorage.setItem("dc-theme", next);
    toggle.textContent = next === "dark" ? "\u2600" : "\u263e";
  });
  var isDark = stored === "dark" ||
    (!stored && window.matchMedia("(prefers-color-scheme: dark)").matches);
  toggle.textContent = isDark ? "\u2600" : "\u263e";
})();
JS

my $Collection_extra_css = <<'CSS';
/* Collection page styles */

table {
  border-collapse: collapse;
  margin: 0 0 24px;
  font-size: var(--font-size-small);
  table-layout: fixed;
  width: 100%;
}

th, td {
  padding: 6px 12px;
  border: 1px solid var(--border);
  text-align: right;
}

th {
  background: var(--header-bg);
  font-weight: 600;
  color: var(--fg);
  text-align: center;
  overflow: hidden;
  text-overflow: ellipsis;
}

td {
  color: var(--fg);
}

td:first-child, th:first-child {
  text-align: left;
}

tr:hover td:not(.c0):not(.c1):not(.c2):not(.c3) {
  background: var(--bg-alt);
}

td.c0, td.c1, td.c2, td.c3 {
  border-color: var(--border);
  white-space: nowrap;
  text-align: center;
}

@media (max-width: 850px) {
  td.c0, td.c1, td.c2, td.c3 {
    white-space: normal;
  }
  td .cov-bar {
    display: block;
    width: 100%;
    margin-left: 0;
    margin-top: 2px;
  }
}

@media (max-width: 900px) {
  .name-full  { display: none; }
  .name-short { display: inline; }
}

h2 {
  font-size: 16px;
  font-weight: 600;
  margin: 24px 0 12px;
  color: var(--fg);
  border-bottom: 1px solid var(--border);
  padding-bottom: 8px;
}

h3 {
  font-size: 13px;
  font-weight: 600;
  margin: 20px 0 8px;
  color: var(--fg-muted);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

p {
  color: var(--fg);
  margin: 0 0 12px;
}

ul {
  color: var(--fg);
  padding-left: 20px;
  margin: 0 0 16px;
  line-height: 1.8;
}

.az-nav {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin: 12px 0 24px;
}

.az-nav a {
  padding: 4px 10px;
  border: 1px solid var(--border);
  border-radius: 4px;
  background: var(--bg-alt);
  font-weight: 600;
  font-size: var(--font-size-small);
}

.az-nav a:hover {
  background: var(--header-bg);
  text-decoration: none;
}

/* About page */

.about-key {
  width: auto;
  table-layout: auto;
}

.about-key td:first-child {
  text-align: center;
  min-width: 120px;
}

.about-key td:last-child {
  text-align: left;
}
CSS

$Files{"collection.css"} = $Crisp_base_css . $Collection_extra_css;
$Files{"collection.js"}  = $Crisp_theme_js;
$Files{"cover.css"}      = $Common_css . $Extra_css;

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
 *              e.g. ul (no angle brackets)
 **/
function createElement(element) {
  if (typeof document.createElementNS != 'undefined') {
    return document.createElementNS(
      'https://www.w3.org/1999/xhtml', element);
  }
  if (typeof document.createElement != 'undefined') {
    return document.createElement(element);
  }
  return false;
}

/**
 * "targ" is the element which caused this function to be called
 * from https://www.quirksmode.org/js/events_properties.html
 * see https://www.quirksmode.org/about/copyright.html
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
 * Use this wherever you want, but please keep this comment at the top of
 * this file.
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
   * @param node      the node to start from
   *                  (e.g. document,
   *                        getElementById('whateverStartpointYouWant')
   *                  )
   * @param searchClass the class we're wanting
   *                  (e.g. 'some_class')
   * @param tag        the tag that the found elements are allowed to be
   *                  (e.g. '*', 'div', 'li')
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
   * PRIVATE.  Creates a string from an array of class names which can be
   * used by the className function.
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
   * Adds classString to the classes assigned to the element with id equal
   * to idString.
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
    this.removeClassFromElement(
      document.getElementById(idString), classString);
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
 * Use this wherever you want, but please keep this comment at the top of
 * this file.
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
    // first, check whether this web browser is capable of running this
    // script
    if (!document.getElementsByTagName) {
      return;
    }

    this.that = this;

    this.run();
  },

  /**
   * Runs over each table in the document, making it sortable if it has a
   * class assigned named "sortable" and an id assigned.
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

    // we'll assume that the last row of headings in the thead is the row
    // that wants to become clickable
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

      // We appendChild rows that already exist to the tbody, so it moves
      // them rather than creating new ones
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

    // work out how we want to sort this column using the data in the
    // first cell but just getting the first cell is no good if it
    // contains no data so if the first cell just contains white space
    // then we need to track
    // down until we find a cell which does contain some actual data
    var itm = ''
    var rowNum = 0;
    while ('' == itm && rowNum < table.tBodies[0].rows.length) {
      itm = that.getInnerText(
        table.tBodies[0].rows[rowNum].cells[column]);
      rowNum++;
    }
    var sortfn = that.determineSortFunction(itm);
    // if the last column that was sorted was this one, then all we need
    // to do is reverse the sorting on this column
    if (table.id == that.lastSortedTable &&
        column == that.sortColumnIndex) {
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

    // now, give the user some feedback about which way the column is
    // sorted

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
    if (null == previousSortOrder || '' == previousSortOrder ||
        'DESC' == previousSortOrder) {
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
      if (cs[i].childNodes.length) {
        str += this.getInnerText(cs[i]);
      } else if (1 == cs[i].nodeType) { // ELEMENT NODE
        str += this.getInnerText(cs[i]);
      } else if (3 == cs[i].nodeType) { //TEXT_NODE
        str += cs[i].nodeValue;
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
    var defined = '([01]?\\d\\d?|2[0-4]\\d|25[0-5])';
    var ipRegex = new RegExp(
      '^' + defined + '\\.' + defined + '\\.' +
        defined + '\\.' + defined + '$');
    if (itm.match(ipRegex)) {
      sortfn = this.sortIP;
    }
    */

    if (itm.match(/\d+\.\d+/) || itm == "n/a") {
      sortfn = this.sortNumeric;
    }

    return sortfn;
  },

  sortCaseInsensitive : function(a, b) {
    var that = standardistaTableSorting.that;

    var aa = that.getInnerText(
      a.cells[that.sortColumnIndex]).toLowerCase();
    var bb = that.getInnerText(
      b.cells[that.sortColumnIndex]).toLowerCase();
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

    // y2k notes: two digit years less than 50 are treated as 20XX,
    // greater than 50 are treated as 19XX
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

    var aa = that.getInnerText(a.cells[that.sortColumnIndex])
      .replace(/[^0-9.]/g,'');
    var bb = that.getInnerText(b.cells[that.sortColumnIndex])
      .replace(/[^0-9.]/g,'');
    return parseFloat(aa) - parseFloat(bb);
  },

  get_val : function(x) {
    var that = standardistaTableSorting.that;

    var val = that.getInnerText(x.cells[that.sortColumnIndex]);
    var v   = val == "n/a" ? -1 : parseFloat(val);
    return isNaN(v) ? 0 : v;
  },

  sortNumeric : function(a, b) {
    var that = standardistaTableSorting.that;

    var aval = that.get_val(a);
    var bval = that.get_val(b);

    return aval - bval;
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

    var aa = that.makeStandardIPAddress(
      that.getInnerText(a.cells[that.sortColumnIndex]).toLowerCase());
    var bb = that.makeStandardIPAddress(
      that.getInnerText(b.cells[that.sortColumnIndex]).toLowerCase());
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

    // We appendChild rows that already exist to the tbody, so it moves
    // them rather than creating new ones
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

1

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Web - Static web assets (CSS and JavaScript) for coverage reports

=head1 SYNOPSIS

 use Devel::Cover::Web qw( write_file $Crisp_base_css $Crisp_theme_js );

 write_file $directory, "cover.css";
 write_file $directory, "all";
 write_file $directory, "js";
 write_file $directory, "css";

 # Inline the shared Crisp stylesheet into a custom report
 my $css = $Crisp_base_css . $my_extra_css;

 # Inline the theme-toggle script into a custom report
 my $js = $Crisp_theme_js . $my_extra_js;

=head1 DESCRIPTION

This module stores and writes the static CSS and JavaScript assets used by
Devel::Cover's HTML reports.  Assets are embedded directly in the module so that
reports remain self-contained without requiring a separate installation step.

The following named files are available:

=over 4

=item C<cover.css>

Styles for the classic HTML reports (C<Html_basic>, C<Html_minimal>,
C<Html_subtle>).  Includes base layout rules, coverage colour classes
(C<c0>-C<c3>), and optional syntax-highlighting classes for C<PPI::HTML> and
C<Perl::Tidy>.

=item C<common.js>

Cross-browser event-handling utilities: C<addEvent>, C<removeEvent>,
C<handleEvent>, C<createElement>, and C<getEventTarget>.

=item C<css.js>

CSS class manipulation helpers: C<getElementsByClass>, C<elementHasClass>,
C<addClassToElement>, and C<removeClassFromElement>.

=item C<standardista-table-sorting.js>

Client-side table sorting.  Attach the C<sortable> class to any table to make
its columns clickable for ascending/descending sort.

=item C<collection.css>

Styles for the cpancover collection index page.  Combines C<$Crisp_base_css>
with collection-specific layout rules including an alphabetic navigation bar and
responsive column hiding.

=item C<collection.js>

Theme-toggle script for the collection index page (same content as
C<$Crisp_theme_js>).

=back

=head1 SUBROUTINES

=head2 write_file ($directory, $file)

Write one or more asset files to C<$directory>.

C<$file> may be a specific filename (e.g. C<"cover.css">) or one of the
following special values:

=over 4

=item C<"all">

Write every available file.

=item C<"js">

Write all C<.js> files.

=item C<"css">

Write all C<.css> files.

=back

=head1 VARIABLES

=head2 $Crisp_base_css

The shared base stylesheet for the Crisp theme.  Defines CSS custom properties
(variables) for colours, typography, and coverage classes, including full
dark-mode support via C<prefers-color-scheme> and an explicit C<data-theme>
attribute.  Used by C<Html_crisp> and C<Collection> to inline styles directly
into generated pages.

=head2 $Crisp_theme_js

A small self-contained script that wires up the light/dark theme-toggle
button. Reads and writes C<localStorage> so the user's preference persists
across page loads.  Used by C<Html_crisp> and C<Collection>.

=head1 SEE ALSO

 Devel::Cover::Report::Html_basic
 Devel::Cover::Report::Html_crisp
 Devel::Cover::Collection
 cpancover

=head1 LICENCE

Copyright 2007-2026, Paul Johnson (paul@pjcj.net) except where otherwise noted.

This software is free.  It is licensed under the same terms as Perl itself,
except where otherwise noted.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut
