package Web::Async::Server;

use strict;
use warnings;

use parent qw(IO::Async::Notifier);

# Usage: perl client-async.pl https://spdy-test.perlsite.co.uk/index.html

use Protocol::SPDY;
use Protocol::UWSGI;

use Web::Async::Protocol::HTTP1;
use Web::Async::Protocol::HTTP2;

use HTTP::Request;
use HTTP::Response;

use IO::Socket::SSL qw(SSL_VERIFY_NONE);
use IO::Async::SSL;
use IO::Async::Stream;

use URI;

use Variable::Disposition qw(retain_future);

sub alpn_callback {
	Net::SSLeay->set_alpn_select_cb(sub {
		my ($ctx, $client_supports) = @_;
		my %proto = map {; $_ => 1 } @$client_supports;
		return 'h2c-16' if exists $proto{'h2c-16'};
		return 'spdy/3.1' if exists $proto{'spdy/3.1'};
		return 'spdy/3' if exists $proto{'spdy/3'};
		return 'https' if exists $proto{'https'};
		return 'http' if exists $proto{'http'};
		return undef # no protocol?
	})
}

sub handler_for {
	my ($self, $proto) = @_;
	if($proto eq 'h2c-16') {
		return Web::Async::Protocol::HTTP2::Server->new
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

sub listen {
	my ($self) = @_;
	my $uri; 
	my $f = $self->loop->new_future;
	retain_future(
		$self->loop->SSL_listen(
			socktype => 'stream',
			host => 'localhost',
			service => 0,
			SSL_alpn_protocols => [ $self->alpn_protocols ],
			SSL_version => 'TLSv12',
			SSL_verify_mode => SSL_VERIFY_NONE,
			SSL_cert_file => 'examples/example.crt',
			SSL_key_file => 'examples/example.key',
			on_accept => sub {
				my $sock = shift;
				my $proto = $sock->alpn_selected;
				print "Connected to " . join(':', $sock->peerhost, $sock->peerport) . ", we're using " . $proto . "\n";
				my $handler = $self->handler_for($proto);
			},
			on_listen => sub {
				my $sock = shift;
				my $port = $sock->sockport;
				$f->done(localhost => $port);
			},
		)->on_fail(sub { $f->fail(@_) })
	);
	$f
}

1;