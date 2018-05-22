#!/usr/bin/env perl

use 5.26.0;

# requires: Mojolicious Minion Minion::Backend::SQLite
use Mojolicious::Lite -signatures;
use Mojo::File;
use CPAN::DistnameInfo;
use Capture::Tiny "capture_merged";

plugin Config => {
    default => {
        minion           => { SQLite => "sqlite:queue.db" },
        # uploads_socket => "ws://api-3.cpantesters.org/v3/upload",
        uploads_socket   => "ws://localhost:3001/v3/upload",
        results_dir      => "results",
    },
};

plugin "Minion" => app->config->{minion};
plugin "Minion::Admin";

my $Debug = $ENV{COVER_DEBUG};

helper results => sub { Mojo::File->new(shift->app->config->{results_dir}) };

push app->static->paths->@*,        app->results->to_string;
push app->commands->namespaces->@*, "Devel::Cover::Queue::Commands";

package Devel::Cover::Queue::Commands::monitor {
    use Mojo::Base "Mojolicious::Command";
    use Mojo::IOLoop;
    use Mojo::UserAgent;
    use Mojo::WebSocket;
    use Scalar::Util ();
    use experimental "signatures";

    has ua => sub { Mojo::UserAgent->new->inactivity_timeout(0) };

    sub run ($command) {
        say STDERR "run" if $Debug;
        $command->connect;
        Mojo::IOLoop->start;
    }

    sub connect ($command) {
        say STDERR "connect" if $Debug;
        my $url = $command->app->config->{uploads_socket};

        Scalar::Util::weaken $command;
        $command->ua->websocket($url => sub ($, $tx) {
            unless ($tx->is_websocket) {
                $command->app->log->warn("Not a websocket");
                Mojo::IOLoop->timer(1 => sub { $command->connect });
                return;
            }

            say STDERR "CONNECTED" if $Debug;
            my $waiting;

            $tx->on(json => sub ($, $data) {
                print STDERR Mojo::Util::dumper $data if $Debug;
                $command->app->minion->enqueue(run_cover => [ $data ]);
            });

            $tx->on(frame => sub ($, $frame) {
                return unless $frame->[4] eq Mojo::WebSocket::WS_PONG;
                say STDERR "PONG" if $Debug;
                $waiting = 0;
            });

            my $pinger = Mojo::IOLoop->recurring(30 => sub {
                say STDERR "PING" if $Debug;
                return $tx->finish if $waiting;
                $waiting = 1;
                $tx->send([ 1, 0, 0, 0, Mojo::WebSocket::WS_PING, "" ])
            });

            $tx->on(finish => sub {
                Mojo::IOLoop->remove($pinger);
                say STDERR "FINISH" if $Debug;
                Mojo::IOLoop->timer(1 => sub { $command->connect });
            });
        });
    }
}

helper release_covered => sub ($c, $release) {
    my $check = $c->results->child($release)->to_abs;
    -d "$check"
};

helper visit_latest_releases => sub ($c, $cb) {
    require CPAN::Releases::Latest;
    my $latest   = CPAN::Releases::Latest->new(max_age => 0);  # no caching
    my $iterator = $latest->release_iterator;
    while (my $release = $iterator->next_release) { $c->$cb($release) }
};

app->minion->add_task(generate_html => sub ($job) {
    my $results = $job->app->results->to_abs;
    my $command = "dc -v -r $results cpancover-generate-html";
    system $command;
});

app->minion->add_task(enqueue_latest => sub ($job) {
    say STDERR "run enqueue_latest" if $Debug;
    my $app    = $job->app;
    my $minion = $app->minion;
    $app->visit_latest_releases(sub ($, $r) {
        return if $app->release_covered($r->distinfo->distvname);
        $minion->enqueue(run_cover => [ $r->path ]);
    });
});

app->minion->add_task(run_cover => sub ($job, $data, $opts = undef) {
    say STDERR "run run_cover", Mojo::Util::dumper $data if $Debug;
    # say STDERR "path $ENV{PATH}" if $Debug;
    # say STDERR `which dc` if $Debug;
    # say STDERR `which perl` if $Debug;
    my $path    = "";
    my $file    = "";
    my $release = "";
    if (ref $data) {
        $path   .= substr($data->{author}, 0, 1) . "/";
        $path   .= substr($data->{author}, 0, 2) . "/";
        $path   .= "$data->{author}/$data->{filename}";
        $file    = $data->{filename};
        $release = "$data->{dist}-$data->{version}";
    } else {
        $path    = $data;
        my $d    = CPAN::DistnameInfo->new("authors/id/$path");
        $file    = $d->filename;
        $release = $d->distvname;
    }

    my $results = $job->app->results->to_abs;
    my $command = "dc -v -r $results cpancover $path";
    my $output  = capture_merged { system $command };
    say STDERR $output if $Debug;

    if ($job->app->release_covered($release)) {
        $job->finish({
            command => $command,
            message => "$file was processed",
        });
    } else {
        $job->fail({
            command => $command,
            message => "$file was not processed correctly",
            output  => $output,
        });
    }
});

app->start;
