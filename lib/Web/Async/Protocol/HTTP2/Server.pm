package Web::Async::Protocol::HTTP2::Server;

use strict;
use warnings;

use Log::Any qw($log);

sub new {
	my ($class) = shift;
	bless { @_ }, $class
}

1;

