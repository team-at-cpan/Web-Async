#!/usr/bin/env perl
use strict;
use warnings;

use Log::Any qw($log);
use Log::Any::Adapter qw(TAP);

use Test::More;
use Test::Fatal;

use Web::Async;

my $loop = IO::Async::Loop->new;

# Set up a server first
$loop->add(
	my $srv = new_ok('Web::Async::Server', [
		($ENV{WEB_ASYNC_PORT} ? (port => $ENV{WEB_ASYNC_PORT}) : ()),
		protocols => [
#			'h2-16', 'h2-14',
'spdy/3.1', 
		]
	])
);
my ($host, $port) = $srv->listen->get;
note "Listen on host $host:$port";

# Make a simple GET request with a new client instance
$loop->add(
	my $cli = new_ok('Web::Async::Client')
);
eval {
	my $resp = $cli->GET(
		'https://' . $host . ':' . $port . '/some/page.html?x=123&y=abcd'
	)->http_response->get;
	isa_ok($resp, 'HTTP::Response');
	ok($resp->is_success, 'had success');
	is($resp->code, 200, 'status code 200');
	is($resp->protocol, 'HTTP/1.1', 'correct protocol');
	note $resp->as_string("\n");
};
$loop->run;

done_testing;
