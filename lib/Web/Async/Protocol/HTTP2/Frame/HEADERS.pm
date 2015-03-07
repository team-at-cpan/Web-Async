package Web::Async::Protocol::HTTP2::Frame::HEADERS;

use strict;
use warnings;

use parent qw(Protocol::SPDY::Frame::Control::HEADERS);

sub xxx {
	my ($self) = @_;
	my $padding = 0;
	$padding = unpack 'C1', substr $payload, 0, 1, '' if $flags & FLAG_PADDED;
	$self->{padding} = substr $payload, -$padding, $padding, '';
	if($flags & FLAG_PRIORITY) {
		my ($depends_on_stream, $weight) = unpack 'N1C1', substr $payload, 0, 5, '';
		my $exclusive = $depends_on_stream & 0x80000000;
		$depends_on_stream &= ~0x80000000;
	}
	$self->{data} = $payload;
}

1;

