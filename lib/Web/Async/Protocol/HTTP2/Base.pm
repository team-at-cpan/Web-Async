package Web::Async::Protocol::HTTP2::Base;

use strict;
use warnings;

use parent qw(Protocol::SPDY::Base);

sub HEADER_LENGTH() { 9 }

sub parse_frame {
	my $self = shift;
	my $pkt = shift;
	return Web::Async::Protocol::HTTP2::Frame->parse(
		\$pkt,
		zlib => $self->receiver_zlib
	);
}

1;
