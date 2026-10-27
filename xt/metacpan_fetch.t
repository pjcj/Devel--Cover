#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# These tests run fetch_latest_releases against the real MetaCPAN::Client with
# a fake HTTP::Tiny. They live apart from xt/collection.t, which defines a
# stand-in client.

use 5.42.0;

use Test2::V0     qw( dies done_testing is like skip_all subtest warnings );
use JSON::MaybeXS qw( decode_json encode_json );

use Devel::Cover::Collection ();

eval { require MetaCPAN::Client; 1 } or skip_all "MetaCPAN::Client not found";

my $Domain = "http://metacpan.test";
my $Search = "POST $Domain/release/_search?scroll=5m&size=1000";
my $Scroll = "POST $Domain/_search/scroll?scroll=5m&size=1000";
my $Delete = "DELETE $Domain/_search/scroll?scroll=5m";
my $Broken = '{"message":"Scroll Id required"}';
my $Retry  = "Retrying the CPAN release list after: ";

my $Fetch_error  = qr/failed to fetch next scrolled batch at .+ line \d+\.$/;
my $Create_error = qr/^failed to create a scrolled search at .+ line \d+\.$/;

# This hit comes from a real release search
my $Sample = decode_json <<~JSON;
  {
    "_id" : "_k_JEYIp4pE0Vee3s_bLlJOnBDE",
    "_index" : "release_01",
    "_score" : 10.182368,
    "_source" : {
      "date" : "2026-03-07T11:38:11",
      "download_url" :
      "https://cpan.metacpan.org/authors/id/P/PJ/PJCJ/Devel-Cover-1.52.tar.gz",
      "maturity" : "released",
      "name" : "Devel-Cover-1.52",
      "stat" : { "mode" : 33188, "mtime" : 1772883491, "size" : 270639 },
      "status" : "latest",
      "version" : "1.52"
    }
  }
  JSON

our %Script;
our @Requests;
our $Timeout;

sub fake_request ($self, $method, $url, $args = {}) {
  $Timeout = $self->timeout;
  my $key  = "$method $url";
  my $body = $args->{content};
  $body = decode_json $body if $method eq "POST";
  push @Requests, { method => $method, url => $url, body => $body };
  return { status => 200, content => "{}" } if $key eq $Delete;
  my $answers = $Script{$key} or die "Unexpected request: $key\n";
  shift @$answers // die "No answer left for: $key\n"
}

sub hit ($n, %source) {
  my $hit = decode_json encode_json $Sample;
  $hit->{_source}->@{ keys %source } = values %source;
  $hit->{_source}{name} = "Dist$n-1.0";
  $hit->{_source}{download_url}
    = "https://cpan.metacpan.org/authors/id/P/PJ/PJCJ/Dist$n-1.0.tar.gz";
  $hit
}

sub search_page ($id, $total, @hits) {
  my $content
    = { _scroll_id => $id, hits => { total => $total, hits => \@hits } };
  { status => 200, content => encode_json $content }
}

sub scroll_page (@hits) {
  { status => 200, content => encode_json { hits => { hits => \@hits } } }
}

sub broken () { { status => 500, content => $Broken } }

sub releases (@ns) {
  my $stat     = $Sample->{_source}{stat};
  my $released = {};
  for my $n (@ns) {
    $released->{"Dist$n"} = {
      path => "P/PJ/PJCJ/Dist$n-1.0.tar.gz",
      time => $stat->{mtime},
      size => $stat->{size},
    };
  }
  { released => $released, developer => {} }
}

sub requests () { [map "$_->{method} $_->{url}", @Requests] }

sub collection () { Devel::Cover::Collection->new(retry_delay => 0) }

sub full_list () {
  local %Script = (
    $Search => [search_page("s1", 5, hit(1), hit(2))],
    $Scroll => [scroll_page(hit(3), hit(4)), scroll_page(hit(5))],
  );
  local @Requests;
  my $w = warnings {
    is collection->fetch_latest_releases, releases(1 .. 5),
      "a list over three pages returns every release"
  };
  is $w, [], "a full list gives no warning";
  is requests, [$Search, $Scroll, $Scroll, $Delete],
    "a full list sends one search and two scroll requests";
  is [map $_->{body}, @Requests[1, 2]],
    [{ scroll_id => "s1" }, { scroll_id => "s1" }],
    "each scroll request sends the scroll id";
}

sub timeout_used ($collection) {
  local %Script = (
    $Search => [search_page("s1", 5, hit(1), hit(2))],
    $Scroll => [scroll_page(hit(3), hit(4)), scroll_page(hit(5))],
  );
  local @Requests;
  local $Timeout;
  $collection->fetch_latest_releases;
  $Timeout
}

sub fetch_timeout () {
  is timeout_used(collection), 30, "a fetch waits 30 seconds by default";
  my $short
    = Devel::Cover::Collection->new(retry_delay => 0, fetch_timeout => 5);
  is timeout_used($short), 5, "a fetch waits for the fetch_timeout given";
}

sub failed_scroll () {
  local %Script = (
    $Search => [search_page("s1", 5, hit(1), hit(2))],
    $Scroll => [broken, scroll_page(hit(3), hit(4)), scroll_page(hit(5))],
  );
  local @Requests;
  my $w = warnings {
    is collection->fetch_latest_releases, releases(1 .. 5),
      "a failed scroll request still returns every release"
  };
  is @$w, 1, "a failed scroll request gives one warning";
  like $w->[0], qr/^\Q$Retry\E$Fetch_error/, "the warning names the failure";
  is requests, [$Search, ($Scroll) x 3, $Delete],
    "a failed scroll request is sent again";
  is $Requests[1]{body}, $Requests[2]{body},
    "the retry sends the same scroll id";
}

sub ten_failed_scrolls () {
  local %Script = (
    $Search => [search_page("s1", 5, hit(1), hit(2))],
    $Scroll => [(broken) x 10],
  );
  local @Requests;
  my $w = warnings {
    like dies { collection->fetch_latest_releases }, qr/^$Fetch_error/,
      "ten failed scroll requests in a row die"
  };
  is @$w, 9, "every failure before the last gives a warning";
}

sub ignored_query () {
  my $old = hit(9, status => "backpan");
  my $bad = "CPAN release list ignores the query: backpan released Dist9-1.0";
  local %Script = ($Search => [
    search_page("s1", 5, $old, hit(1)), search_page("s2", 2, hit(2), hit(3)),
  ]);
  local @Requests;
  my $w = warnings {
    is collection->fetch_latest_releases, releases(2, 3),
      "an answer that ignores the query returns the second answer"
  };
  is $w, ["$Retry$bad\n"], "an answer that ignores the query gives one warning";
  is requests, [$Search, $Search, $Delete, $Delete],
    "an answer that ignores the query sends the search again";
  is [map $_->{body}, @Requests[2, 3]], [qw( s1 s2 )],
    "each result set deletes its own scroll";
}

sub empty_page () {
  local %Script = (
    $Search => [search_page("s1", 5, hit(1), hit(2))],
    $Scroll => [scroll_page()],
  );
  local @Requests;
  like dies { collection->fetch_latest_releases },
    qr/^CPAN release list ended early: got 2 of 5$/,
    "an empty page before the total dies";
}

sub failed_search () {
  local %Script = ($Search => [broken]);
  local @Requests;
  like dies { collection->fetch_latest_releases }, $Create_error,
    "a failed search dies";
  is requests, [$Search], "a failed search is not sent again";
}

sub since () {
  local %Script = ($Search => [search_page("s1", 1, hit(1))]);
  local @Requests;
  is collection->fetch_latest_releases(since => 1_772_323_200), releases(1),
    "a call with since returns the releases";
  is $Requests[0]{body}{query}{bool}{must}[0],
    { range => { date => { gte => "2026-03-01T00:00:00" } } },
    "a call with since filters the search on date";
}

sub main () {
  local $ENV{METACPAN_DOMAIN} = $Domain;
  no warnings qw( once redefine );
  local *HTTP::Tiny::request = \&fake_request;
  my @tests = qw(
    full_list
    fetch_timeout
    failed_scroll
    ten_failed_scrolls
    ignored_query
    empty_page
    failed_search
    since
  );
  for my $test (@tests) {
    no strict qw( refs );
    subtest $test => \&$test;
  }
  done_testing;
}

main;
