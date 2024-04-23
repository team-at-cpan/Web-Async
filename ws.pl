#!/usr/bin/env perl
package WS {
use Myriad::Class extends => 'IO::Async::Notifier';

use IO::Async::Listener;

use Web::Async::WebSocket::Frame;

use List::Util qw(pairmap);
use Compress::Zlib;
use POSIX ();
use Time::Moment;
use Digest::SHA qw(sha1);
use MIME::Base64 qw(encode_base64);

# As defined in the RFC - it's used as part of the hashing for the security header in the response
use constant WEBSOCKET_GUID => '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

field $srv;
field $ryu;

# Given the state of websockets in general, this is unlikely to change from `HTTP/1.1` anytime soon
field $http_version : reader : param = 'HTTP/1.1';
# 101 Upgrade is defined by the RFC, but if you have special requirements you can override via the constructor
field $status : reader : param = '101';
# The message is probably ignored by everything
field $msg : reader : param = 'Switching Protocols';
# There aren't a vast number of extensions, at the time of writing https://www.iana.org/assignments/websocket/websocket.xhtml#extension-name
# lists just two of 'em
field $supported_extension : reader : param {
    +{
        'permessage-deflate' => 1
    }
}
field $server_name : reader : param = 'perl';

# Opcodes have a registry here: https://www.iana.org/assignments/websocket/websocket.xhtml#opcode
my %OPCODE_BY_CODE = (
    1 => 'text',
    2 => 'binary',
    8 => 'close',
    9 => 'ping',
    10 => 'pong',
);
my %OPCODE_BY_NAME = reverse %OPCODE_BY_CODE;

field $deflation;
field $inflation;

method deflate ($data) {
    $deflation //= deflateInit(
        -WindowBits => -MAX_WBITS
    ) or die "Cannot create a deflation stream\n" ;

    my ($output, $status) = $deflation->deflate($data);
    die "deflation failed\n" unless $status == Z_OK;
    (my $block, $status) = $deflation->flush(Z_SYNC_FLUSH);
    die "deflation failed at flush stage\n" unless $status == Z_OK;

    return $output . $block;
}

method inflate ($data) {
    $inflation //= inflateInit(
        -WindowBits => -MAX_WBITS
    ) or die "Cannot create a deflation stream\n" ;

    my ($block, $status) = $inflation->inflate($data);
    die "deflation failed\n" unless $status == Z_STREAM_END or $status == Z_OK;
    return $block;
}

method _add_to_loop ($loop) {
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

        $log->infof('url = %s, headers = %s', $url, format_json_text(\%hdr));

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
            'Date'       => Time::Moment->now_utc->strftime("%a, %d %b %Y %H:%M:%S GMT"),
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
        # await $conn->write("$http_version 400 $e\x0D\x0A\x0D\x0A");
        my $txt = <<'HTML';
<!DOCTYPE html>
<html>
 <body>
  ws test
  <script type="module">
            const ws = new WebSocket('ws://localhost:7777/api');
            ws.binaryType = 'blob';
            ws.addEventListener('message', async (msg) => {
                console.debug(msg);
                try {
                    if(msg.data instanceof Blob) {
                        // await this.handle_binary(msg);
                    } else {
                        // await this.handle_json(msg);
                    }
                } catch(e) {
                    console.log('failure on message handling - ', e);
                }
            });
            ws.addEventListener('error', async (msg) => {
                console.error('Websocket error received: ', msg);
            });

            ws.addEventListener('open', async (evt) => {
                console.log(`Opened connection`);
                const data = { };
                setInterval(async () => {
                    const len = 3 + parseInt(Math.random() * 100);
                    let str = '';
                    for(let i = 0; i < len; ++i) {
                        str = str + String.fromCodePoint(parseInt(Math.random() * 65535));
                    }
                    data[str] = Math.random();
                    await ws.send(JSON.stringify(data));
                }, 300);
            });
            ws.addEventListener('closed', async (evt) => {
                console.log('Closed connection: ', evt);
            });

  </script>
 </body>
</html>
HTML
        my $encoded = encode_utf8 $txt;
        my $length = length($encoded);
        await $conn->write("$http_version 200 OK\x0D\x0AConnection: close\x0D\x0AContent-Length: $length\x0D\x0AContent-Type: text/html\x0D\x0A\x0D\x0A" . $encoded . "\x0D\x0A");
        $conn->close;
        return;
    }

    # Body processing
    try {
        while(1) {
            $log->infof('Start reading frames');
            my $payload = await $self->read_frame($conn);
            $log->infof('Had frame: %s', $payload);
            await $self->write_frame(
                $conn,
                type    => 'text',
                payload => $payload
            );
        }
    } catch ($e) {
        $log->errorf('Problem, %s', $e);
        $conn->close;
    }
}

async method read_frame ($stream) {
    $log->infof('Reading frames from %s', "$stream");
    my $fin;
    my $data = '';
    my $compressed;
    my $type;
    do {
        my ($opcode, $len) = unpack 'C1C1', '' . await $stream->read_exactly(2);
        my $masked = $len & 0x80;
        die 'unmasked frame' unless $masked;
        $len &= ~0x80;
        $fin = ($opcode & 0x80) ? 1 : 0;
        my @rsv = map { ($opcode & $_) ? 1 : 0 } 0x40, 0x20, 0x10;
        $compressed //= $rsv[0];
        $type //= $opcode & 0x0F;
        if($len == 126) {
            ($len) = unpack 'n1', '' . await $stream->read_exactly(2);
            die 'invalid length' if $len < 126;
        } elsif($len == 127) {
            ($len) = unpack 'Q>1', '' . await $stream->read_exactly(8);
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
            $log->infof('Masked payload = %v0x', $payload);
            my ($frac, $int) = POSIX::modf(length($payload) / 4);
            $payload ^.= ($mask x $int) . substr($mask, 0, 4 * $frac);
        }
        $log->infof('Payload = %v0x', $payload);
        $data .= $payload;
    } until $fin;
    $data = $self->inflate($data . "\x00\x00\xFF\xFF") if $compressed;
    $log->infof('Frame opcode is %s', $OPCODE_BY_CODE{$type});
    $data = decode_utf8($data) if $type == $OPCODE_BY_NAME{text};
    $log->infof('Finished, data is now %s', $data);
    return $data;
}

async method write_frame ($stream, %args) {
    my $compressed = $args{compress} // 1;
    $log->infof('Write frame with %s', \%args);
    # FIN
    my $opcode = $OPCODE_BY_NAME{$args{type}};
    my $payload = $args{payload};
    $payload = encode_utf8($payload) if $opcode == $OPCODE_BY_NAME{text};

    $opcode |= 0x80;
    if($compressed) {
        $opcode |= 0x40;
        my $original = length $payload;
        $payload = $self->deflate($payload);
        # Strip terminator if we have one
        $payload =~ s{\x00\x00\xFF\xFF$}{};
        $log->infof(
            'Size after deflation is %d/%d, ratio of %4.1f%%',
            length($payload),
            $original,
            100.0 * (length($payload) / $original),
        );
    }
    my $len = length $payload;
    my $msg = pack('C1', $opcode);
    if($len < 126) {
        $msg .= pack('C1', $len);
    } elsif($len < 0xFFFF) {
        $msg .= pack('C1n1', 126, $len);
    } else {
        $msg .= pack('C1Q>1', 127, $len);
    }
    $msg .= $payload;
    await $stream->write($msg);
    return;
}

}

package main {
use Myriad::Class;
use Log::Any::Adapter 'Stderr', log_level => 'debug';
use IO::Async::Loop;

binmode STDERR, ':encoding(UTF-8)';

my $loop = IO::Async::Loop->new;
$loop->add(
    WS->new
);
$loop->run;

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
