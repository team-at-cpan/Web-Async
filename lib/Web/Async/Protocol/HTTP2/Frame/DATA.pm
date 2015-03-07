package Web::Async::Protocol::HTTP2::Frame::DATA;

use strict;
use warnings;

use parent qw(Protocol::SPDY::Frame::Data);

use constant {
	PADDED => 1,
	END_STREAM => 2,
};

sub new {
	my ($class, %args) = @_;
	my $self = bless {
		flags => $args{flags} || 0,
		data  => $args{data},
		padding => '',
	}, $class;
	my $payload = '';
	my $pad_length = 0;
	$args{pad_length} = length $args{padding} if defined $args{padding};
	$self->{pad_length} = $args{pad_length};
	if($args{pad_length}) {
		$self->{flags} |= PADDED;
		$pad_length = $args{pad_length} - 1;
		die 'padding' if $pad_length > 0xFF || $pad_length < 0;
		$payload .= pack 'C1', $pad_length;
	}
	$payload .= $args{data};
	if($pad_length) {
		$payload .= "\0" x $pad_length if $pad_length;
		$payload .= "\0" x $pad_length if $pad_length;
	}
	$self->{payload} = $payload;
	$self->{flags} |= END_STREAM if $args{end_stream};
	$self
}

sub extract {
	my ($self, %args) = @_;
	my $padding = 0;
	my $payload = $self->payload;
	$padding = unpack 'C1', substr $payload, 0, 1, '' if $self->flags & PADDED;
	$self->{padding} = substr $payload, -$padding, $padding, '';
	$self->{padding_length} = $padding;
	$self->{data} = $payload;
}

sub data { shift->{data} }
sub padding { shift->{padding} }
sub pad_length { shift->{pad_length} }
sub payload { shift->{payload} }
sub flags { shift->{flags} }

1;

