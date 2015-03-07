#!/usr/bin/env perl
use strict; use warnings;
use IO::Async::Loop;
use Web::Async;
my $loop = IO::Async::Loop->new;
$loop->add(my $web = Web::Async->new);
$web->listen(
 'localhost',
 directory => File::Temp::tempdir(),
 allow_upload => 1,
)->then(sub {
 my ($srv) = @_;
 $web->POST(
  $srv->base_uri . '/file.mp4',
  parts => [
   { type => 'file', path => 'file.mp4' },
  ],
 )
})->get;
