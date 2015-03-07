#!/usr/bin/env perl
use strict; use warnings;
use IO::Async::Loop;
use Web::Async;
my $loop = IO::Async::Loop->new;
$loop->add(my $web = Web::Async->new);
$web->listen('*')->then(sub {
 $web->GET('https://localhost')->protocol->on_done(sub {
  my ($proto) = @_;
  print "Protocol: " . $proto . "\n";
 });
})->get;
