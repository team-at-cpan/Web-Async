package Web::Async::Client;

use strict;
use warnings;

use parent qw(IO::Async::Notifier);

# Usage: perl client-async.pl https://spdy-test.perlsite.co.uk/index.html

=pod

=head2 Request limits

max_connections_per_ip - total number of active TCP connections allowed to the same resolved IP address

max_connections_per_host - total number of active TCP connections allowed to the same host:port combination

max_requests_per_host - total number of active HTTP requests allowed for a host:port combination

The connection limits restrict how many active TCP connections we will maintain. Since protocols often
have the ability to have multiple active requests on the same connection, the request limits may be more
useful if the intention is to limit the load on the target server.

To ensure that we only ever have 4 unfinished requests in progress for any given host, use:

 max_requests_per_host => 4

This will queue any additional requests in first-in, first-out order. You can examine the current queue
status using:

 $client->request_queue

to retrieve all requests that have not yet been started, and

 $client->request_queue_for(host => 'www.example.com')

to limit this to a specific server.

Global limits are also available:

 max_total_requests => 32

This will restrict to 32 total requests across all servers.

=head2 Queue policy

There is some degree of control over how requests will be added to the queue:

 queue_policy => 'fifo'|'lifo'|'fair'|sub { ... }

The default is 'fifo', which means that it's possible to have a large number of requests in
the queue for one host that will need to be processed before requests for other hosts are entertained.

=head2 Bandwidth limits

Per-host rates apply to data sent/received from a host:port combination.

Per-request rates affect requests - for multiplexed requests such as HTTP2, these can be used to distribute
the traffic within a single TCP connection.

Bytes-on-wire

Body without encoding - this looks at the data we see after any encoding layers have been removed, so for
gzip this would be decompressed

Body after encoding - this represents the body bytes on the wire, but without any framing overhead

=head2 Accounting

One side effect of the bandwidth controls is that we are able to track and report usage.

=cut

use Log::Any qw($log);
use Variable::Disposition qw(retain_future);

use Protocol::SPDY;
use Protocol::UWSGI;

use Web::Async::Protocol::HTTP1;
use Web::Async::Protocol::HTTP2;
use Web::Async::Protocol::HTTP2::Client;
use Web::Async::Protocol::SPDY::Client;

use Web::Async::Request;

use HTTP::Request;
use HTTP::Response;

use IO::Socket::SSL qw(SSL_VERIFY_NONE);
use IO::Async::SSL;
use IO::Async::Stream;

use URI;

sub handler_for {
	my ($self, $proto) = @_;
	if($proto eq 'h2c-16') {
		return Web::Async::Protocol::HTTP2::Client->new
	} elsif($proto eq 'spdy/3.1') {
		return Web::Async::Protocol::SPDY::Client->new
	} elsif($proto eq 'http') {
		return Web::Async::Protocol::HTTP1::Client->new
	}
	...
}

=head2 alpn_protocols

Returns a list of the protocols we will attempt to negotiate via ALPN.

=cut

sub alpn_protocols {
	my ($self) = shift;
	$self->{alpn_protocols} //= [
		Web::Async::Protocol::HTTP2->alpn_identifiers,
		Protocol::SPDY->alpn_identifiers,
		'http'
	];
	@{$self->{alpn_protocols}}
}

=head2 expand_args

Extrapolate information from common parameters.

=cut

sub expand_args {
	my ($self, $args) = @_;
	$args->{uri} = URI->new($args->{uri}) unless ref $args->{uri};
	$args->{host} //= $args->{uri}->host;
	$args->{port} //= $args->{uri}->port // ($args->{uri}->scheme eq 'http' ? 80 : 443);
	$args
}

sub connection_key {
	my ($self, %args) = @_;
	$self->expand_args(\%args);
	join "\0", $args{host}, $args{port};
}

sub connection {
	my ($self, %args) = @_;
	$self->expand_args(\%args);

	my $f = $self->loop->new_future;
	retain_future(
		$self->loop->SSL_connect(
			socktype => "stream",
			host     => $args{host},
			service  => $args{port},
			SSL_alpn_protocols => [ $self->alpn_protocols ],
			SSL_version => 'TLSv12',
			SSL_verify_mode => SSL_VERIFY_NONE,
			on_connected => sub {
				my $sock = shift;
				my $proto = $sock->alpn_selected;
				my $connection_key = join(':', (map { $sock->$_ } qw(peerhost peerport sockhost sockport)), Scalar::Util::refaddr($sock));
				$log->debugf("Connected to %s:%d using protocol %s", $sock->peerhost, $sock->peerport, $proto);
				my $handler = $self->handler_for($proto);
				$handler->on_stream(
					my $stream = IO::Async::Stream->new(
						handle => $sock
					)
				);
				$self->{handler_for_connection}{$connection_key} = $handler;
				$self->add_child($stream);
				$f->done($handler);
			},
		)->on_fail(sub { $f->fail(@_) })
	);
	$f
}

=head2 GET

Starts a GET request for the given URL.

Returns a L<Web::Async::Request>.

=cut

sub GET {
	my ($self, $uri, %args) = @_;

	$uri = URI->new($uri) unless ref $uri;
	$args{uri} = $uri;

	my $req = Web::Async::Request->new(
		new_future => sub { $self->loop->new_future },
		%args,
	);

	retain_future(
		$self->connection(%args)->then(sub {
			my ($conn) = @_;
			eval {
				$log->debugf("Connection [%s]", "$conn");
				$conn->request($req);
			} or do {
				$log->errorf("Exception - %s", $@);
				$req->fail($@)
			}
		})
	);

	$req
}

1;
