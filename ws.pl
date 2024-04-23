#!/usr/bin/env perl
package WS {
use Myriad::Class extends => 'IO::Async::Notifier';

use IO::Async::Listener;

use List::Util qw(pairmap);
use Compress::Zlib;
use POSIX ();
use Digest::SHA qw(sha1);
use MIME::Base64 qw(encode_base64);

use constant WEBSOCKET_GUID => '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

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
    $self->decode_frame("\x03\x9F");
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
        $self->handle_connection($conn)
    );
}

async method handle_connection ($conn) {
    try {
        my %hdr;
        my $first = await $conn->read_until("\x0D\x0A");
        my ($method, $url, $version) = $first =~ m{^(\S+)\s+(\S+)\s+HTTP/(\d+\.\d+)\x0D\x0A$}a;
        $log->infof('HTTP request is [%s] for [%s] version %s', $method, $url, $version);
        while(1) {
            $log->infof('read line');
            my $line = decode_utf8('' . await $conn->read_until("\x0D\x0A"));
            $line =~ s/\x0D\x0A$//;
            $log->infof('Line length %d', length $line);
            last unless length $line;
            my ($k, $v) = $line =~ /^([^:]+):\s+(.*)$/;
            $log->infof('Header [%s] => [%s]', $k, $v);
            $k = lc($k =~ tr{-}{_}r);
            $hdr{$k} = $v;
        }

        $log->infof('headers = %s', format_json_text(\%hdr));

        unless($hdr{sec_websocket_version} >= 13) {
            die sprintf "Invalid websocket version %s\n", $hdr{sec_websocket_version};
        }

        my $key = $hdr{sec_websocket_key}
            or die "No websocket key provided\n";
        my $response_key = encode_base64(sha1($key . WEBSOCKET_GUID), '');
        my %output = (
            'Upgrade'    => 'websocket',
            'Connection' => 'upgrade',
            'Server'     => 'perl',
        );
        $output{'Sec-Websocket-Extensions'} = $hdr{sec_websocket_extensions};
        $output{'Sec-WebSocket-Accept'} = $response_key;
        await $conn->write(
            join(
                "\x0D\x0A",
                "$http_version $status $msg",
                (pairmap {
                    encode_utf8("$a: $b")
                } %output),
                # Blank line at the end of the headers
                '', ''
            )
        );
    } catch ($e) {
        $log->errorf('Failed - %s', $e);
        await $conn->write("$http_version 400 $e\x0D\x0A\x0D\x0A");
    }
}

method decode_frame ($frame) {
    my ($opcode, $len) = unpack 'C1C1', substr $frame, 0, 2, '';
    my $masked = $len & 0x80;
    die 'unmasked frame' unless $masked;
    $len &= ~0x80;
    my $fin = ($opcode & 0x80) ? 1 : 0;
    my @rsv = map { ($opcode & $_) ? 1 : 0 } 0x40, 0x20, 0x10;
    if($len == 126) {
        ($len) = unpack 'n1', substr $frame, 0, 2, '';
        die 'invalid length' if $len < 126;
    } elsif($len == 127) {
        ($len) = unpack 'Q1', substr $frame, 0, 8, '';
        die 'invalid length' if $len < 0xFFFF or $len & 0x80000000;
    }
    my $mask = '';
    if($masked) {
        $mask = substr $frame, 0, 4, '';
    }
    $log->infof(
        'Frame opcode %d, length %d, fin = %s, rsv = %s %s %s, mask key %v0x',
        $opcode,
        $len,
        $fin,
        @rsv,
        $mask
    );
    exit;
    return {};
}

async method read_frame ($stream) {
    my $fin;
    my $data = '';
    my $compressed;
    do {
        my ($opcode, $len) = unpack 'C1C1', '' . await $stream->read_exactly(2);
        my $masked = $len & 0x80;
        die 'unmasked frame' unless $masked;
        $len &= ~0x80;
        my $fin = ($opcode & 0x80) ? 1 : 0;
        my @rsv = map { ($opcode & $_) ? 1 : 0 } 0x40, 0x20, 0x10;
        $compressed //= $rsv[0];
        if($len == 126) {
            ($len) = unpack 'n1', '' . await $stream->read_exactly(2);
            die 'invalid length' if $len < 126;
        } elsif($len == 127) {
            ($len) = unpack 'Q1', '' . await $stream->read_exactly(8);
            die 'invalid length' if $len < 0xFFFF or $len & 0x80000000;
        }
        my $mask = '';
        if($masked) {
            $mask = await $stream->read_exactly(4);
        }
        $log->infof(
            'Frame opcode %d, length %d, fin = %s, rsv = %s %s %s, mask key %v0x',
            $opcode,
            $len,
            $fin,
            @rsv,
            $mask
        );
        my $payload = await $stream->read_exactly($len);
        if($masked) {
            my ($frac, $int) = POSIX::modf(length($payload) / 4);
            $payload ^.= ($mask x $int) . substr($mask, 0, 4 * $frac);
        }
        $log->infof('Payload = %s', $payload);
        $data .= $payload;
    } until $fin;
    return $data unless $compressed;
    return scalar $self->deflate($payload . "\x00\x00\xFF\xFF");
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

my @lines = split /\n/, <<'HTTP';
GET wss://websocket.test/api/ HTTP/1.1
Host: websocket.test
Connection: Upgrade
Pragma: no-cache
Cache-Control: no-cache
User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36
Upgrade: websocket
Origin: https://websocket.test
Sec-WebSocket-Version: 13
Accept-Encoding: gzip, deflate, br, zstd
Accept-Language: en-GB,en-US;q=0.9,en;q=0.8
Cookie: some_key=some_value
Sec-WebSocket-Key: T+wE/RYIBSNZBSnGCYf9sQ==
Sec-WebSocket-Extensions: permessage-deflate; client_max_window_bits

HTTP

push @lines, '' if length $lines[-1];

for my $line (@lines) {
    $log->infof('>>> [%s]', $line);
    await $conn->write($line . "\x0D\x0A");
}

while(1) {
    my $line = await $conn->read_until("\x0D\x0A");
    $line =~ s{\x0D\x0A$}{};
    $log->infof('<<< %s', $line);
}

}
