#!/usr/bin/env perl
use strict; use warnings;
use IO::Async::Loop;
use Web::Async;
my $loop = IO::Async::Loop->new;
$loop->add(my $web = Web::Async->new);
$web->listen('https://some.example.com')->then(sub {
 my ($srv) = @_;
 my $cert = $srv->tls->server_cert;
 $web->GET('https://some.example.com', host => 'localhost')->tls->on_done(sub {
  my ($tls) = @_;
  print "Domain:             " . $tls->sni . "\n";
  print "Server cert:        " . $tls->server_cert . "\n";
  print "Actual server cert: " . $cert . "\n";
  print "Client cert:        " . $tls->client_cert . "\n";
  print "ALPN:               " . join(',', $tls->alpn_protocols) . "\n";
 });
})->get;
