#!/usr/bin/env perl
package WS {
use Myriad::Class extends => 'IO::Async::Notifier';

use IO::Async::Listener;

use Compress::Zlib;

field $srv;

field $http_version : reader : param = 'HTTP/1.1';
field $status : reader : param = '101';
field $msg : reader : param = 'Switching Protocols';

method deflate ($data) {
    my $x = deflateInit(
        -WindowBits => -MAX_WBITS
    ) or die "Cannot create a deflation stream\n" ;

    my ($block, $status) = $x->deflate($data);
    die "deflation failed\n" unless $status == Z_OK;
    my $output = $block;
    ($block, $status) = $x->flush(Z_SYNC_FLUSH);
    die "deflation failed at flush stage\n" unless $status == Z_OK;

    return $output . $block;
}

method inflate ($data) {
    my $x = deflateInit(
        -WindowBits => -MAX_WBITS
    ) or die "Cannot create a deflation stream\n" ;

    my ($block, $status) = $x->inflate($data);
    die "deflation failed\n" unless $status == Z_OK;
    return $block;
}

method _add_to_loop ($loop) {
    warn "add to loop";
    $self->add_child(
        $srv = IO::Async::Listener->new(
            on_stream => $self->curry::weak::on_stream,
        )
    );
    $self->adopt_future(
        $srv->listen(
            service  => 7777,
            socktype => 'stream',
        )
    );
}

method on_stream ($listener, $conn, @other) {
    $log->infof('Connection %s for listener %s', "$conn", "$listener");
    $conn->configure(
        on_read => sub { 0 }
    );
    $self->add_child($conn);
    $self->adopt_future(
        $conn->write("$http_version $status $msg\x0D\x0A\x0D\x0A")
    );
}

}

package main {
use Myriad::Class;
use Log::Any::Adapter 'Stderr', log_level => 'debug';
use IO::Async::Loop;
my $loop = IO::Async::Loop->new;
$loop->add(
    WS->new
);

my $sock = await $loop->connect(
    addr => {
        family   => "inet",
        socktype => "stream",
        port     => 7777,
        ip       => "127.0.0.1",
    },
);
$loop->add(
    my $conn = IO::Async::Stream->new(
        handle => $sock,
        on_read => sub { 0 },
    )
);

my $line = await $conn->read_until("\x0D\x0A");
$log->infof('Line: %s', $line);

}
