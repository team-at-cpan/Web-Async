package Web::Async;
# ABSTRACT: IO::Async support for common web protocols (http1/http2/spdy/psgi/uwsgi)
use strict;
use warnings;

use parent qw(IO::Async::Notifier);

our $VERSION = '0.001';

=head1 NAME

Web::Async - provides server/client support for some typical web-related activities

=head1 SYNOPSIS

 # Create object and add to event loop
 use IO::Async::Loop;
 use Web::Async;
 my $loop = IO::Async::Loop->new;
 $loop->add(my $web = Web::Async->new);

 # Serve static files (in response to HTTP1/2/SPDY requests)
 binmode STDOUT, ':encoding(UTF-8)';
 $web->listen(
  'https://*:8086',
  directory => '/var/www/html'
 )->then(sub {
  $web->GET(
   'https://localhost:8086/somefile.txt'
  )->response
 })->then(sub {
  my $resp = shift;
  warn "Bad status: " . $resp->code unless $resp->is_2xx;
  print "Content: " . $resp->body . "\n";
 })->get;

 # PSGI
 $web->listen(
  'https://*:8086',
  directory => '/var/www/html'
 );

 # Attempt graceful shutdown before exit, allowing up to 5s to complete
 $web->shutdown(timeout => 5)->get;

=head1 DESCRIPTION

=head2 Listening for requests

These can be given as paths (for files and Unix-domain sockets) or URIs. Some examples of valid entries:

=over 4

=item * tcp://host:port

=item * unix:///path

=item * /path

=back

=head3 CGI

Forward all requests to a single CGI script:

 $web->listen(
  'http://*',
  cgi => '/var/www/cgi-bin/somescript.cgi',
 );

Use the last part of the path for the CGI script name:

 $web->listen(
  'http://*',
  cgi => {
   path   => '/var/www/cgi-bin',
   script => qr{([/]+\.cgi)},
  }
 );

=head3 PSGI

Forward requests to a simple PSGI coderef:

 $web->listen(
  'http://*',
  psgi => sub {
   [ 200, [], [ 'OK' ] ]
  }
 );

Streaming PSGI:

 $web->listen(
  'http://*',
  psgi => sub {
   my ($env) = @_;
   die "no streaming' unless $env->{'psgi.streaming'};
   sub { [ 200, [], [ 'OK' ] ] }
  }
 );

=head3 HTTP proxy

Proxy all requests to a backend HTTP server:

 $web->listen(
  'http://*',
  http => 'http://127.0.0.1:3086',
 );

This is similar to the "reverse proxy" behaviour in webservers such as Apache.

Pass all requests to two backend servers simultaneously:

 $web->listen(
  'http://*',
  http => [
   'http://10.1.0.2:8080',
   'http://10.1.0.3:8080',
  ],
 );

The first server to start returning output will be used as the reponse, but the request will
be delivered in full to both servers (unless the client bails out early).

=head3 UWSGI

Send each request to a UWSGI endpoint:

 $web->listen(
  'http://static.example.com',
  uwsgi => 'unix:///tmp/uwsgi.sock',
 );

=head3 FastCGI

Send each request to a FastCGI server:

 $web->listen(
  'http://static.example.com',
  fastcgi => 'unix:///tmp/fastcgi.sock',
 );

=head3 Directory

Static files can be served from a directory:

 $web->listen(
  'http://static.example.com',
  directory => '/var/www/example.com/htdocs',
 );

Missing files will present a 404 error, basic directory listing (+DAV) supported.

=head2 Sending requests

HTTP client methods mostly correspond to the HTTP verb:

=over 4

=item * L</GET>

=item * L</HEAD>

=item * L</OPTIONS>

=item * L</POST>

=item * L</PUT>

=item * L</DELETE>

=item * L</TRACE>

=item * L</PATCH>

=item * L</PROPFIND>

=item * L</PROPPATCH>

=item * L</MKCOL>

=item * L</COPY>

=item * L</MOVE>

=item * L</LOCK>

=item * L</UNLOCK>

=item * L</VERSIONCONTROL> - for VERSION-CONTROL

=item * L</REPORT>

=item * L</CHECKOUT>

=item * L</UNCHECKOUT>

=item * L</CHECKIN>

=item * L</MKWORKSPACE>

=item * L</UPDATE>

=item * L</LABEL>

=item * L</MERGE>

=item * L</BASELINECONTROL> - for BASELINE-CONTROL

=item * L</MKACTIVITY>

=item * L</ORDERPATCH>

=item * L</ACL>

=item * L</SEARCH>

=item * L</CONNECT>

=back

The basic API is the same for each of these - examples will use GET/POST, but any of the above verbs can be used interchangeably here.

A simple request using default headers and no body:

 $web->GET(
  'http://localhost'
 )

This will return a L<Web::Async::Request> instance - methods on that class can be used to query the exact request sent, with L<Future>s
and events which will trigger when the connection is established, request is sent, and server responds.

Sending basic content - text is treated as a Unicode string and sent encoded via most suitable encoding (typically UTF-8):

 $web->POST(
  'http://localhost',
  text => 'some text',
 )

You can also send bytes:

 $web->POST(
  'http://localhost',
  bytes => $image->as_png,
  content_type => 'image/png',
 )

Or JSON:

 $web->POST(
  'http://localhost',
  json => $some_hashref
 )

Technically there's XML as well:

 $web->POST(
  'http://localhost',
  xml => $something
 )

but this works better with a L<LibXML::DOM> instance than a plain Perl datastructure.

It is also possible for requests to have deferred content:

 # Stream data from a local file, given by name
 $web->PUT(
  'http://localhost/some/path/and/file.img',
 )->from_file('/local/file.img');

 # Stream a fixed number of random-ish bytes
 use List::Util qw(min);
 my $count = 1048576;
 $web->PUT(
  'http://localhost/random-1M.img',
 )->body(sub {
  return unless $count;
  my $data = join '', map chr(256 * rand), 1..min($count, 4096);
  $count -= length $data;
  $data
 })

The L<Web::Async::Request> object provides a L<Web::Async::Request/response> method for accessing the current response state.

 my $req = $web->GET(
  'http://localhost/random-1M.img',
 );
 my $resp = $req->response;
 $resp->complete->on_done(sub {
  print "Response finished\n";
 });
 $resp->headers->on_done(sub {
  print "Received headers\n";
 });
 $loop->await($resp->complete);

=cut

use Web::Async::Client;
use Web::Async::Server;

=head1 METHODS

=cut

=head2 request

Takes the following named parameters:

=over 4

=item * version - the HTTP version string, defaults to HTTP/1.1

=item *  ...

=back

=cut

=head2 listen

=over 4

=item * cgi - a CGI script to invoke on each request

=item * psgi - a PSGI coderef to invoke for each request

=item * uwsgi - a UWSGI endpoint to invoke for each request

=item * fastcgi - a UWSGI endpoint to invoke for each request

=item * http - send request to a backend HTTP proxy

=item * http2 - send request to a backend HTTP2 proxy

=item * directory - serve files from a directory

=back

=cut

sub listen {
	my ($self, $uri, %args) = @_;
	$uri = URI->new($uri) unless ref $uri;
	$self->loop->new_future;
}

sub request {
	my ($self, %args) = @_;
	$args{uri} = URI->new($args{uri}) unless ref $args{uri};
	$self->loop->new_future;
}

sub listeners {
	@{ shift->{listeners} }
}

sub connections {
	@{ shift->{connections} }
}

our @HTTP_METHODS = qw(
	CONNECT
	GET HEAD OPTIONS POST PUT
	DELETE TRACE PATCH
	PROPFIND PROPPATCH
	MKCOL
	COPY MOVE
	LOCK UNLOCK
	BASELINECONTROL
	VERSIONCONTROL
	REPORT
	CHECKOUT UNCHECKOUT CHECKIN
	MKWORKSPACE
	UPDATE
	LABEL
	MERGE
	MKACTIVITY
	ORDERPATCH
	ACL
	SEARCH
);

BEGIN {
	*$_ = sub {
		my $self = shift;
		$self->request(method => $_, uri => @_)
	} for @HTTP_METHODS
}

1;

__END__

=head1 SEE ALSO

=head1 AUTHOR

Tom Molesworth <cpan@perlsite.co.uk>

=head1 LICENSE

Copyright Tom Molesworth 2015. Licensed under the same terms as Perl itself.

