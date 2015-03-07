use strict;
use warnings;

use Test::More;
use Test::Fatal;
use Test::HexString;

use Web::Async::Protocol::HTTP2::Frame::DATA;

use constant {
	PADDED => 1,
	END_STREAM => 2,
};

my @cases = ({
	label => 'no padding',
	construct => {
		pad_length => 0,
		data => 'xyz',
	},
	payload => 'xyz',
	flags => 0
}, {
	label => 'single-byte padding',
	construct => {
		pad_length => 1,
		data => 'xyz',
	},
	payload => "\0xyz",
	flags => PADDED,
});

for my $case (@cases) {
	note $case->{label};
	my $frame = new_ok('Web::Async::Protocol::HTTP2::Frame::DATA' => [
		%{$case->{construct}},
	]);
	is($frame->flags, $case->{flags}, 'flags match');
	is($frame->$_, $case->{construct}->{$_}, "$_ matches") for sort keys %{$case->{construct}};
	is_hexstr($frame->payload, $case->{payload}, 'payload is correct');
}

{
	my $frame = Web::Async::Protocol::HTTP2::Frame::DATA->new(
		padding => 0,
		data => 'xyz',
	);
	ok(!($frame->flags & PADDED), 'padded flag is off with no padding');
	is($frame->flags & END_STREAM, 0, 'END_STREAM not set');
	is($frame->data, 'xyz', 'data is correct');
	is_hexstr($frame->payload, 'xyz', 'payload is correct');
}
{
	my $frame = Web::Async::Protocol::HTTP2::Frame::DATA->new(
		padding => 1,
		data => 'xyz',
	);
	ok($frame->flags & PADDED, 'padded flag is on with non-zero padding');
	is($frame->flags & END_STREAM, 0, 'END_STREAM not set');
	is($frame->data, 'xyz', 'data is correct');
	is_hexstr($frame->payload, "\0xyz", 'payload is correct');
}
{
	my $frame = Web::Async::Protocol::HTTP2::Frame::DATA->new(
		padding => 256,
		data => 'xyz',
	);
	ok($frame->flags & PADDED, 'padded flag is on with non-zero padding');
	is($frame->flags & END_STREAM, 0, 'END_STREAM not set');
	is($frame->data, 'xyz', 'data is correct');
	is_hexstr($frame->payload, "\xFFxyz" . ("\0" x 255), 'payload is correct');
}
{
	like(exception {
		Web::Async::Protocol::HTTP2::Frame::DATA->new(
			padding => 257,
			data => 'xyz',
		);
	}, qr/padding/, 'have an exception when we try to add too much padding');
}
{
	my $frame = Web::Async::Protocol::HTTP2::Frame::DATA->new(
		padding => 0,
		data => 'xyz',
		end_stream => 1,
	);
	ok(!($frame->flags & PADDED), 'padded flag is off with no padding');
	ok($frame->flags & END_STREAM, 'END_STREAM set');
	is($frame->data, 'xyz', 'data is correct');
	is_hexstr($frame->payload, 'xyz', 'payload is correct');
}

done_testing;


