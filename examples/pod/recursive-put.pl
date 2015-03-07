#!/usr/bin/env perl
use strict; use warnings;
use IO::Async::Loop;
use Web::Async;
use Future::Utils qw(fmap0);
my $loop = IO::Async::Loop->new;
$loop->add(my $web = Web::Async->new);
my ($src, $dst) = ('/tmp/upload_from', '/tmp/webserver');
mkdir $_ for $src, $dst;
$web->listen(
 '*',
 directory => $dst,
 dav => 1,
)->then(sub {
 my ($srv) = @_;
 my @pending;
 my $upload = sub {
  my ($file) = @_;
  my $path = $srv->base_uri . '/' . $file;
  push @pending, map "$file/$_", glob "$src/$file/*" if -d $file;
  return -d "$src/$file"
   ? $web->MKCOL($path)
   : $web->PUT($path)
         ->from_file($file)
 };
 push @pending, '';
 fmap0 {
  $upload->(my $file = shift)->then(sub {
   print "Uploaded $file\n";
   Future->done
  }, sub {
   warn "Upload for $file failed: @_\n";
   Future->done
  })
 } from => \@pending, concurrent => 4;
})->get
