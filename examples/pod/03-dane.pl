#!/usr/bin/env perl
use strict; use warnings;
use IO::Async::Loop;
use Web::Async;
my $loop = IO::Async::Loop->new;
$loop->add(my $dns = Net::Async::DNS->new);
$loop->add(my $web = Web::Async->new);
my $uri = URI->new('https://dane-test.example.com');
Future->needs_all(
 $web->listen($uri),
 $dns->listen('udp://*:0')
)->then(sub {
 my ($http_srv, $dns_srv) = @_;
 $loop->set_resolver($dns_srv->resolver);
 $dns_srv->add_server($http_srv)
})->then(sub {
 $web->GET($uri)->tls->on_done(sub {
  my ($tls) = @_;
  print "Domain:      " . $tls->sni . "\n";
  print "Server cert: " . $tls->server_cert . "\n";
  print "Client cert: " . $tls->client_cert . "\n";
  print "ALPN:        " . join(',', $tls->alpn_protocols) . "\n";
 });
})->get;

