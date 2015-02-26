use strict;
use warnings;

use Test::More;

use Web::Async::Request;

my $req = new_ok('Web::Async::Request');
can_ok($req, qw(bus new_future));
ok(my $resp = $req->http_response, 'get response');
isa_ok($resp, 'Future');

ok($req->bus->invoke_event(
	method => 'GET'
), 'GET method');
ok(!$resp->is_ready, 'not ready yet');
ok($req->bus->invoke_event(
	path => '/some/page'
), 'path');
ok(!$resp->is_ready, 'not ready yet');
ok($req->bus->invoke_event(
	scheme => 'https'
), 'scheme');
ok(!$resp->is_ready, 'not ready yet');
ok($req->bus->invoke_event(
	authority => 'www.example.com'
), 'authority');
ok(!$resp->is_ready, 'not ready yet');
ok($req->bus->invoke_event(
	headers => [ Host => 'www.example.com' ],
), 'authority');
ok(!$resp->is_ready, 'not ready yet');
ok($req->bus->invoke_event(
	body_start => ''
), 'authority');
ok(!$resp->is_ready, 'not ready yet');

done_testing;


