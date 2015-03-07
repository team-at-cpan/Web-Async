#!/usr/bin/env perl
use strict; use warnings;
use IO::Async::Loop;
use Web::Async;
$web->listen(
 'localhost'
 on_request => sub {
  my ($req) = shift;
  warn $req->method . " " . $req->uri . "\n";
  (my $host = lc $req->authority) =~ s/:\s*(\d+)\s*$//;
  return $req->refuse('localhost denied') if $host eq 'localhost';
  $req->respond($web->request($req))
 }
)->then(sub {
 my ($srv) = @_;
 $loop->new_future
})->get;
