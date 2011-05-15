# Copyright 2007-2011, Paul Johnson (pjcj@cpan.org)
# except where otherwise noted.

# This software is free.  It is licensed under the same terms as Perl itself,
# except where otherwise noted.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Web;

use strict;
use warnings;

our $VERSION = "0.77";

use Exporter;

our @ISA       = "Exporter";
our @EXPORT_OK = "write_file";

my %Files;

sub write_file
{
    my ($directory, $file) = @_;

    while (my($f, $contents) = each %Files)
    {
        next if
            $file ne "all" &&
            (($file eq "js" || $file eq "css") && $f !~ /\.$file$/) &&
            $file ne $f;
        my $path = "$directory/$f";
        open my $p, ">", $path or next;
        print $p $contents;
        close $p;
    }
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
 *              e.g. ul (no angle brackets)
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

            // alert("sorting on " + column);

            var newRows = new Array();

            for (var j = 0; j < table.tBodies[0].rows.length; j++) {
                newRows[j] = table.tBodies[0].rows[j];
                // alert("element " + j + " is " + that.getInnerText(newRows[j].cells[that.sortColumnIndex]));
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
            // alert("node " + i + " is [" + cs[i].nodeType + "] [" + cs[i].nodeValue + "] [" + cs[i].childNodes.length + "]");
            if (cs[i].childNodes.length)
            {
                str += this.getInnerText(cs[i]);
            }
            else if (1 == cs[i].nodeType) { // ELEMENT NODE
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
            if (itm.match(/^([01]?\d\d?|2[0-4]\d|25[0-5])\.([01]?\d\d?|2[0-4]\d|25[0-5])\.([01]?\d\d?|2[0-4]\d|25[0-5])\.([01]?\d\d?|2[0-4]\d|25[0-5])$/)) {
                sortfn = this.sortIP;
        }
        */

        // alert("sorting on [" + itm + "]");
        if (itm.match(/\d+\.\d+/) || itm == "n/a") {
            sortfn = this.sortNumeric;
        }

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

=head1 NAME

Devel::Cover::Web - Files for JavaScript or CSS

=head1 SYNOPSIS

 use Devel::Cover::Web "write_file";

 write_file $directory, $file;
 write_file $directory, "all";
 write_file $directory, "js";
 write_file $directory, "css";

=head1 DESCRIPTION

This module allows JavaScript and CSS files to be written to a specified
directory.

=head1 SUBROUTINES

=head2 write_file($directory, $file)

Output the specified file to the specified directory.

=head1 SEE ALSO

 Devel::Cover::Report::Html_basic
 cpancover

=head1 BUGS

Huh?

=head1 VERSION

Version 0.77 - 15th May 2011

=head1 LICENCE

Copyright 2007-2011, Paul Johnson (pjcj@cpan.org) except where otherwise noted.

This software is free.  It is licensed under the same terms as Perl itself,
except where otherwise noted.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut
