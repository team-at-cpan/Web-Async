package Web::Async::Protocol::HTTP2::Frame;

use strict;
use warnings;

use parent qw(Protocol::SPDY::Frame);

sub parse {
	shift;
	my $pkt = shift;
	# 2.2 Frames always have a common header which is 8 bytes in length
	return undef unless length $$pkt >= $self->HEADER_LENGTH;

	my ($len, $flags, $stream_id) = unpack "N1C1N1", $$pkt;

	# Length is a 24-bit value followed by type
	my $type = $len & 0xFF;
	$len >>= 8;

	return undef unless length $$pkt >= $self->HEADER_LENGTH + $len;

	# 31-bit stream ID
	$stream_id &= 0x7FFFFFFF;

	my $class = $self->class_for_type($type) or return undef;

	$class->from_data(
		data => $$pkt
	);
}

my %types = (
	0 => 'Web::Async::Protocol::HTTP2::Frame::DATA',
	1 => 'Web::Async::Protocol::HTTP2::Frame::HEADERS',
	2 => 'Web::Async::Protocol::HTTP2::Frame::PRIORITY',
	3 => 'Web::Async::Protocol::HTTP2::Frame::RST_STREAM',
	4 => 'Web::Async::Protocol::HTTP2::Frame::SETTINGS',
	5 => 'Web::Async::Protocol::HTTP2::Frame::PUSH_PROMISE',
	6 => 'Web::Async::Protocol::HTTP2::Frame::PING',
	7 => 'Web::Async::Protocol::HTTP2::Frame::GOAWAY',
	8 => 'Web::Async::Protocol::HTTP2::Frame::WINDOW_UPDATE',
	9 => 'Web::Async::Protocol::HTTP2::Frame::CONTINUATION',
);
sub class_for_type { $types{$_[1]} }

1;
