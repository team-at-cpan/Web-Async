package Web::Async::Connection;

use strict;
use warnings;

sub new { my ($class) = shift; bless { @_ }, $class }
sub shutdown { Future->done }

1;

