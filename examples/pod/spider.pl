#!/usr/bin/env perl
use strict; use warnings;
use IO::Async::Loop;
use Web::Async;
my $loop = IO::Async::Loop->new;
$loop->add(my $web = Web::Async->new);
my ($dst) = ('/tmp/webserver-source', '/tmp/webserver-copy');
mkdir $_ for $dst;
$web->listen(
 '*',
 directory => $dst,
 dav => 1,
)->then(sub {
 my ($srv) = @_;
 my @pending;
 my $retrieve = sub {
  my ($info) = @_;
  my $file = $info->{file};
  my $path = $srv->base_uri . '/' . $file;
  if($info->{type} eq 'file') {
   $web->GET(
    $path,
   )->to_file("$dst/$file")
  } else {
   $web->dav_ls(
    $path,
   )->each(sub {
    my $item = shift;
    push @pending, {
     type => $item->type,
     file => $file . '/' . $item->file
    };
   })
 };
 push @pending, { type => 'collection', file => '' };
 fmap0 {
  $retrieve->(my $file = shift)->then(sub {
   print "Downloaded $file\n";
   Future->done
  }, sub {
   warn "Download for $file failed: @_\n";
   Future->done
  })
 } from => \@pending, concurrent => 4;
})->get

