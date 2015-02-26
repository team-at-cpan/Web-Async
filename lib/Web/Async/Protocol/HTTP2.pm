package Web::Async::Protocol::HTTP2;

use strict;
use warnings;

use Web::Async::Protocol::HTTP2::Server;

sub alpn_identifiers { 'h2-16', 'h2-14' }

1;
