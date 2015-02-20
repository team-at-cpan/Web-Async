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

=head2 Accounting

One side effect of the bandwidth controls is that we are able to track and report usage.

=cut

use Log::Any qw($log);

use Protocol::SPDY;
use Protocol::UWSGI;

use Web::Async::Protocol::HTTP1;
use Web::Async::Protocol::HTTP2;
use Web::Async::Protocol::HTTP2::Client;

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
	}
	...
}

=head2 alpn_protocols

Returns a list of the protocols we will attempt to negotiate via ALPN.

=cut

sub alpn_protocols {
	Web::Async::Protocol::HTTP2->alpn_identifiers,
	Protocol::SPDY->alpn_identifiers,
	'http'
}

sub connect {
	my ($self, $uri) = @_;

	$self->loop->SSL_connect(
		socktype => "stream",
		host     => $uri->host,
		service     => $uri->port || 'https',
		SSL_alpn_protocols => [ $self->alpn_protocols ],
		SSL_version => 'TLSv12',
		SSL_verify_mode => SSL_VERIFY_NONE,
		on_connected => sub {
			my $sock = shift;
			my $proto = $sock->alpn_selected;
			print "Connected to " . join(':', $sock->peerhost, $sock->peerport) . ", we're using " . $proto . "\n";
			my $handler = $self->handler_for($proto);
			$handler->on_stream(
				my $stream = IO::Async::Stream->new(
					handle => $sock
				)
			);
			$self->add_child($stream);
		},
		on_ssl_error => sub { die "ssl error: @_"; },
		on_connect_error => sub { die "conn error: @_"; },
		on_resolve_error => sub { die "resolve error: @_"; },
		on_listen => sub {
			my $sock = shift;
			my $port = $sock->sockport;
			print "Listening on port $port\n";
		},
	);
}

sub GET {
	my ($self, $uri, %args) = @_;
	$uri = URI->new($uri) unless ref $uri;
	$self->connect(
		$uri
	);
}

1;
