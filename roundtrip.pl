#!/usr/bin/env perl;
use strict;
use warnings;

use Test::More;

use Web::Async;

my $loop = IO::Async::Loop->new;
$loop->add(
	my $srv = new_ok('Web::Async::Server')
);
$loop->add(
	my $cli = new_ok('Web::Async::Client')
);
my ($host, $port) = $srv->listen->get;
note "Listen on host $host:$port";

my $resp = $cli->GET(
	'https://' . $host . ':' . $port
)->get;

done_testing;
