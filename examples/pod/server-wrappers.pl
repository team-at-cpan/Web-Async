#!/usr/bin/env perl
use strict; use warnings;
use IO::Async::Loop;
use Web::Async;
use Net::Async::IMAP::Server;
use Net::Async::SMTP::Server;
use Net::Async::AMQP::Server;
use WebService::Amazon::DynamoDB::Server;
my $loop = IO::Async::Loop->new;
$loop->add(my $web = Web::Async->new);
my $srv_wrap = sub {
 my ($http, $service) = @_;
 die "$service needs ->$_" for grep !$service->can($_), qw(model web);
 $loop->add($service);
 $service->auth($http->auth);
 Future->needs_all(
  $http->attach('/api/v1' => Web::Async::REST::Model->new(model => $service->model)),
  $http->attach('/'       => $service->web),
 )
};
my %args = (
 storage => 'pg:version=9.4',
);
my %srv = (
 auth     => $web->auth->service(%args),
 imap     => Net::Async::IMAP::Server->new(%args),
 webmail  => Net::Async::IMAP::Client->new(%args),
 smtp     => Net::Async::SMTP::Server->new(%args),
 amqp     => Net::Async::AMQP::Server->new(%args),
 dns      => Net::Async::DNS::Server->new(%args),
 dynamodbserver => WebService::Amazon::DynamoDB::Server->new(%args),
 dynamodbclient  => WebService::Amazon::DynamoDB::Client->new(%args),
);
Future->needs_all(
 $web->auth->create_admin->then(sub {
  my $admin = shift;
  warn "Admin user is " . $admin->user . " with password " . $admin->password;
 }),
 $web->listen(
  'files.localhost',
  directory => File::Temp::tempdir,
  dav => 1,
 ),
 map $web->listen($_ . '.localhost')->then(sub {
  my ($srv) = @_;
  $srv_wrap->($srv, $srv{$_})
 }), keys %srv
)->get;
$loop->run;
