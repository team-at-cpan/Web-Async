package Web::Async::Client;

use strict;
use warnings;

use parent qw(IO::Async::Notifier);

# Usage: perl client-async.pl https://spdy-test.perlsite.co.uk/index.html

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
