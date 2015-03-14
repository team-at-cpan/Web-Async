package Web::Async::Listener;

use strict;
use warnings;

use parent qw(IO::Async::Notifier);

sub on_accept {
	my ($self, $sock, $proto) = @_;
	# If other processes were also listening, we may have lost the race
	# to accept() the new request, if so there's nothing else to be done
	return unless $sock;

	# Make sure we have some sort of stream...
	my $stream = $sock->isa('IO::Async::Stream') ? $sock : do {
		my $stream = IO::Async::Stream->new(handle => $sock);
		$self->add_child($stream);
		$stream
	};

	# Detour via TLS if necessary, we'll be back later on success
	return $self->tls_upgrade($stream, $proto) if $self->needs_tls;

	# If we received some sort of protocol indicator, use it - otherwise,
	# fall back to HTTP1.
	my $http = $self->class_for_proto($proto)->new;
	$http->source->from($stream);
	$http->sink->to($stream);
}

sub class_for_proto {
	my ($self, $proto) = @_;
	if($proto) {
		return 'Protocol::HTTP::HTTP2' if $proto =~ /^h2/;
		return 'Protocol::HTTP::SPDY3' if $proto =~ /^spdy/i;
		return 'Protocol::HTTP::HTTP1' if $proto eq 'http';
		return 'Protocol::HTTP::HTTP1' if $proto eq 'https';
	}
	return 'Protocol::HTTP::HTTP1';
}

sub needs_tls {
	my ($self) = @_;
	return 0 if $self->using_tls;
	return 1 if $self->is_tls;
	return 0;
}

sub using_tls { shift->{using_tls} //= 0 }

# IO::Async::SSL
sub tls_upgrade {
	my ($self, $stream, %args) = @_;

	my $k = "$stream";
	$self->{accepting}{$k} = $self->loop->SSL_upgrade(
		handle => $stream,
		SSL_server => 1,
		$self->tls_args,
	)->on_ready(sub { delete $self->{accepting}{$k} })
	 ->then(sub {
		my ($stream) = @_;
		$self->{using_tls} = 1;
		$self->add_child($stream);
	 });
}

1;

