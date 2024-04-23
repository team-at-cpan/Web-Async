#!/usr/bin/env perl
use Myriad::Class;
use Log::Any::Adapter 'Stderr', log_level => 'debug';
use IO::Async::Loop;

use Web::Async::WebSocket::Server;

binmode STDERR, ':encoding(UTF-8)';

my $loop = IO::Async::Loop->new;
$loop->add(
    my $srv = Web::Async::WebSocket::Server->new(
        port => 7777
    )
);
$srv->incoming_client->each(sub ($client, @) {
    $log->infof('Client: %s', "$client");
    $client->incoming_frame->map(async sub ($frame, @) {
        $log->infof('Frame: %s', $frame->payload);
        await $client->write_frame(
            type    => 'text',
            payload => $frame->payload
        );
    })->resolve->retain;
});
$loop->run;
