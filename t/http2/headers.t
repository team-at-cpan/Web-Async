use strict;
use warnings;

use Test::More;
use Test::Fatal;
use Test::HexString;

{
	my $frame = Frame::HEADERS->new(
	);
	ok(!($frame->flags & PADDED), 'no padding by default');
}
{
	my $frame = Frame::HEADERS->new(
		padding => 0,
		headers => [
			'xyz' => 'abc'
		],
	);
	ok(!($frame->flags & PADDED), 'padded flag is off with no padding');
	is($frame->flags & END_STREAM, 0, 'END_STREAM not set');
	is($frame->data, 'xyz', 'data is correct');
	is_hexstr($frame->payload, 'xyz', 'payload is correct');
}

done_testing;

