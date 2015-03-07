#!/usr/bin/env perl
use strict; use warnings;
use IO::Async::Loop;
use Web::Async;
my $loop = IO::Async::Loop->new;
$loop->add(my $web = Web::Async->new);
$loop->add(my $facebook = $web->spore('share/facebook.json'));
$loop->add(
 my $twitter = Net::Async::Twitter->new(web => $web)
);
$facebook->wall->latest_photo->then(sub {
 my $photo = shift;
 $twitter->post_photo->from($photo->source)
})->get;
