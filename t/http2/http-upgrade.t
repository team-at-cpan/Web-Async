use strict;
use warnings;

use Test::More;

use Web::Async::Request;

use MIME::Base64::URLSafe;

# Initial connect to http:// attempts Upgrade+HTTP2 headers
my $req = new_ok('Web::Async::Request' => [
	method => 'GET',
	uri => 'http://example.com/',
]);
is($req->uri, 'http://example.com/', 'URI matches');
is($req->header('Connection'), 'Upgrade, HTTP2-Settings', 'we have upgrade+HTTP2-settings in connection field');
is($req->header('Upgrade'), 'h2c', 'we have upgrade+HTTP2-settings in connection field');
ok(my $http2_settings = $req->header('HTTP2-Settings'), 'have HTTP2-Settings field');
ok(my $settings_bytes = urlsafe_b64decode($http2_settings), 'can decode HTTP2-Settings field');
ok(my $frame = Web::Async::Protocol::HTTP2::Frame::SETTINGS->from_payload($settings_bytes), 'can get frame from bytes');
isa_ok($frame, 'Web::Async::Protocol::HTTP2::Frame::SETTINGS');

done_testing;

