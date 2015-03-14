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
  my ($srv) = @_;
  print "Listening on " . $srv->base_uri . "\n";
  $web->GET(
   $srv->base_uri . '/somefile.txt'
  )->response_ready
 })->then(sub {
  my $resp = shift;
  warn "Bad status: " . $resp->code unless $resp->is_2xx;
  print "Content: " . $resp->body . "\n";
 })->get;

 # Attempt graceful shutdown before exit, allowing up to 5s to complete
 $web->shutdown(timeout => 5)->get;

=head1 DESCRIPTION

This is an L<IO::Async> client/server implementation for HTTP-related protocols. It provides
support for plaintext or TLS-encrypted requests using HTTP/1.1, HTTP/2, SPDY/3.1
or other gateway protocols such as PSGI, CGI, FastCGI or UWSGI.
It provides much of the functionality typically found in L<LWP::UserAgent> or C< curl >, but
using an async API based mainly on L<Future>s.

=head2 Features

=over 4

=item * Protocol selection - client/server will autonegotiate a suitable transport protocol (HTTP2, SPDY, HTTP1.1)

# EXAMPLE: examples/pod/01-protocol-selection.pl

=item * TLS - client/server cert, ALPN

# EXAMPLE: examples/pod/02-tls-alpn.pl

=item * DANE - certs from DNS

# EXAMPLE: examples/pod/03-dane.pl

=item * Timeout - per-request timeout configuration

# EXAMPLE: examples/pod/04-timeout.pl

=item * Encoding - gzip/zlib compression will be applied by default if the other side understands it

# EXAMPLE: examples/pod/05-encoding.pl

=item * Bandwidth/usage limiting - request accounting and rules support limits per host/key with various
restriction and backoff policies

=item * Retry - automatically retry requests with backoff

=item * Streaming - support sink/source and stream types (sendfile/coderef/handle) and multipart requests

=item * Concurrency - Per-host, domain, key limits for active requests

=back

Transport-layer protocol implementations are from the following modules:

=over 4

=item * L<Protocol::HTTP::HTTP1> - implements HTTP/1.1 as described in RFC2616 and subsequently updated in RFC7230-RFC7236

=item * L<Protocol::HTTP::HTTP2> - implements HTTP/2.0 (or "SPDY/4" if you're using Chrome)

=item * L<Protocol::HTTP::SPDY3> - implements SPDY/3.1

=item * L<Protocol::UWSGI> - implements UWSGI, as seen in some online docs somewhere

=item * L<Protocol::CGI> - implements CGI as described in RFC3875

=back

=head2 Motivation

This module mainly exists to provide seamless support for HTTP2/SPDY alongside existing protocols such as HTTP1, UWSGI and FastCGI.
The SPDY and HTTP2 protocols add some concepts (priority, server push) which are not yet exposed in most existing HTTP modules.

Simple to start a server for a PSGI coderef and later extend to a more flexible object.

Ability to replace nginx/apache2 and gain full SPDY/HTTP2 while still supporting legacy backends via CGI/FastCGI/HTTP proxy.

Act as a proxy and integrate with existing proxies (HTTP, SOCKS, tor).

=head1 API Examples

=head2 Listening for requests

The listen endpoint can be given as a path (for files and Unix-domain sockets), tcp/port or udp/port shortcut, or URI. Some examples of valid entries:

=over 4

=item * https://localhost:3089

=item * tcp://host:port or just tcp/port

=item * udp://host:port or just udp/port

=item * unix:///path

=item * file:///path

=item * /path

=item * domain.example.com

=item * domain.example.com:8080

=back

When no port is specified, will attempt plaintext on 80 and TLS on 443, retrying
with server-assigned ports if those requests fail.

A listener needs a handler to do anything useful with incoming requests. See
the next sections for examples of some existing handlers.

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

 my $input = $loop->new_from_stdin;
 $web->listen(
  'http://*',
  psgi => sub {
   my ($env) = @_;
   die "no streaming' unless $env->{'psgi.streaming'};
   my $file = '...';
   sub {
    my ($responder) = @_;
    my $writer = $responder->([ 200, [ 'Content-Type' => 'video/mpeg4' ]]);
    $input->configure(
     on_read => sub {
      my ($buf, $eof) = @_;
      $writer->write(substr $$buf, 0, min(length $$buf, 4096), '');
      if($eof) {
       $writer->write($$buf);
       $writer->close;
      }
     }
    );
   }
  }
 )->get;

which could also be written as:

 my $input = $loop->new_from_stdin;
 $web->listen(
  'http://*',
  psgi => $web->psgi_from_stream($input),
 );

=head3 HTTP

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
  'uwsgi.example.com',
  uwsgi => 'unix:///tmp/uwsgi.sock',
 );

=head3 FastCGI

Send each request to a FastCGI server:

 $web->listen(
  'fastcgi.example.com',
  fastcgi => 'unix:///tmp/fastcgi.sock',
 );

=head3 Directory

Static files can be served from a directory:

 $web->listen(
  'static.example.com',
  directory => '/var/www/example.com/htdocs',
 );

Missing files will present a 404 error, basic directory listing (+read-only DAV methods such as PROPFIND) supported.
Full write access is enabled with the C< dav > option:

 $web->listen(
  'webdav.example.com',
  directory => '/var/www/example.com/writable',
  dav => 1,
 );

=head3 Serving static content

You can provide content on specific paths using L<Web::Async::Listener/attach>:

 $web->listen(
  'static.example.com',
 )->then(sub {
  my ($srv) = @_;
  Future->needs_all(
   $srv->attach('/example.txt'  => text => 'a text file'),
   $srv->attach('/example.json' => json => { id => 1, success => JSON->true }),
  )
 })->get;

=head2 Listening as a tor service

Exposing a service via Tor:

Add these lines to /etc/torrc:

 HiddenServiceDir /opt/tor/hidden_service/
 HiddenServicePort 80 127.0.0.1:8080

Once tor has restarted with the new config (and generated a key if necessary) for the hidden service:

 chomp(
  my $host = do { local (@ARGV, $/) = '/opt/tor/hidden_service/hostname'; <> }
 );
 $web->listen(
  'http://$host',
  port => 8080,
 );

Note that all requests are proxied to localhost:8080, which means that any user on that host is likely to be able to monitor traffic.

See L<https://github.com/lachesis/scallion> or L<https://github.com/katmagic/Shallot> if you want to customize the hidden service name (the .onion address).

Example tor site:

 $web->GET(
  'https://perlwebhpaqrgtzi.onion',
  proxy => 'socks5://127.0.0.1:9050',
 )->get;

=head2 Sending requests

A typical request takes the form

 $web->METHOD($uri)

as in:

 $web->GET('https://www.google.com')->response->to_stream($loop->new_for_stdout)->get;

HTTP client methods mostly correspond to the HTTP verb:

=over 4

=item * L</GET>

=item * L</HEAD>

=item * L</OPTIONS>

=item * L</POST>

=item * L</PUT>

=item * L</DELETE>

=item * L</CONNECT>

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
 )->from_file('/local/file.img')->get;

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
 })->complete->get;

The L<Web::Async::Request> object provides a L<Web::Async::Request/response> method. This can be used for accessing
the current response state:

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

=head1 Usage examples

Some more cases:

=head2 Proxy

Blindly accept incoming requests, acting as proxy for http1/http2 on ports 80 and 443:

# EXAMPLE: examples/pod/http-proxy.pl

=head2 PUT from file

On some platforms, using a file name or handle to send data can be optimised by the sendfile()
operation. Other platforms will just use the standard read/write pair.

# EXAMPLE: examples/pod/put-from-file.pl

=head2 Form upload

File uploads via POST typically use the multipart/formdata MIME type.

# EXAMPLE: examples/pod/form-upload.pl

=head2 Stream between servers

Transfer files between two servers - copy a Facebook photo to a Twitter post, for example:

# EXAMPLE: examples/pod/facebook-to-twitter.pl

=head2 Video streaming

Default streaming options should already provide enough support for pre-encoded MPEG-DASH or HLS content,
although MIME types may need updating:

 $web->listen(
  '*',
  directory => '/var/www/video',
  mime_types => {
   m3u => 'application/vnd.apple.mpegurl',
  }
 )->get

=head2 Spider website

# EXAMPLE: examples/pod/spider.pl

=head2 Upload files recursively

# EXAMPLE: examples/pod/recursive-put.pl

=head2 Sync local and remote paths

With a remote server supporting WebDAV extensions, you can achieve a very basic form of rsync with code such as:

 my ($src, $dst) = ('/tmp/source', '/tmp/destination');
 mkdir $_ for $src, $dst;
 $web->listen(
  '*',
  directory => $dst,
  dav => 1,
 )->then(sub {
  my ($srv) = @_;
  $web->sync_paths($src . '/' => $srv->base_uri . '/')
 })->get

Note that this requires at least PROPFIND, PUT, HEAD and DELETE support on the server.

=head2 REST request

A trivial REST server:

 {
  package Some::Model;
  use Adapter::Async::Model {
   name => 'string',
   things => {
    collection => 'OrderedList',
    type => 'string',
   }
  }
 }
 my $model = Some::Model->new;
 $web->listen(
  'localhost',
 )->then(sub {
  my ($srv) = @_;
  $srv->attach('/api' => Web::Async::REST::Model->new(model => $model));
  $model->name('model name');
  Future->done;
 })->get;

With the above, you could query the API manually like this:

  $web->GET(
   $srv->base_uri . '/api/name',
  )->response->json->then(sub {
   my ($resp) = @_;
   warn "Name was " . $resp->{'name'};
   $web->POST(
    $srv->base_uri . '/api/things',
	text => 'test',
   )
  })->response->json->on_done(sub {
    my $resp = @_;
    my ($success, $index) = map $resp->{$_}, qw(success index);
	if($success) {
	 printf "Valid request, index generated %d\n", $index;
	} else {
	 warn "Request failed: $resp->{reason}" unless $success;
	}
  })->then(sub {
   $web->GET(
    $srv->base_uri . '/api/things',
   )->response->json
  })->on_done(sub {
   my ($resp) = @_;
   printf " * $_\n" for @$resp;
  })
 })->get;

Or use L<Web::Async::REST::Client>:

 my $rest = Web::Async::REST::Client->new($srv->base_uri . '/api');
 $rest->attr('name')->on_done(sub {
  my $name = shift;
  printf "REST API reports ->name as %s\n", $name;
 })->then(sub {
  $rest->clear('things')
 })->then(sub {
  $rest->push(things => 'a thing')
 })->then(sub {
  $rest->each(things => sub {
   printf " * $_\n", shift;
  })
 })->get

=head3 SPORE

The "Specification for Portable Object REST Environment" provides definitions for services.

 $web->spore('spore/githubv3.json')->then(sub {
  my ($spore) = @_;
  $spore->list_issues('...')
 })->get;

=head3 Database wrappers

There's a few helper modules for common tasks. Here's one way to get a web UI and REST interface for accessing data in an SQLite database:

 $web->listen('*')->then(sub {
  my ($srv) = @_;
  my $orm = DBIx::Async::ORM::SQLite->new('somedb.sqlite');
  Future->needs_all(
   $srv->attach('/api/v1' => Web::Async::REST::Model->new(model => $orm->model)),
   $srv->attach('/' => $orm->web),
  )
 })->get;
 $loop->run;

or PostgreSQL:

 use DBIx::Async::ORM;
 use Web::Async::REST::Model;
 $web->listen('*')->then(sub {
  my ($srv) = @_;
  $loop->add(my $orm = DBIx::Async::ORM->new('pg:version=9.4'));
  Future->needs_all(
   $srv->attach('/api/v1' => Web::Async::REST::Model->new(model => $orm->model)),
   $srv->attach('/' => $orm->web),
  )
 })->get;
 $loop->run;

=head3 Server wrappers

With a server implementation that provides the C<web> and C<model> interface methods, you can expose a UI and/or REST interface
by attaching them to the server.

# EXAMPLE: examples/pod/server-wrappers.pl

=cut

use Web::Async::Client;
use Web::Async::Server;

use Web::Async::Model;
use Mixin::Event::Dispatch::Bus;

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

=item * fastcgi - a FastCGI endpoint

=item * http - send request to a backend HTTP/1.1 proxy

=item * spdy - send request to a backend SPDY/3.1 proxy

=item * http2 - send request to a backend HTTP/2.0 proxy

=item * directory - serve files from a directory

=back

=cut

sub listen {
	my ($self, $uri, %args) = @_;
	$uri = $self->upgrade_uri($uri, \%args);
	$self->check_listener(\%args);
	my $srv = Web::Async::Listener->new(
		%args,
		uri => $uri,
	);
	$self->add_child($srv);
	$self->model->listeners->set_key(
		Scalar::Util::refaddr($srv) => $srv
	)->transform(done => sub { $srv });
}

sub upgrade_uri {
	my ($self, $uri, $args) = @_;
	unless(ref $uri) {
		$uri = URI->new($uri);
		$uri->host('0.0.0.0') if $uri->host eq '*';
	}
	$args->{host} //= $uri->host;
	$args->{port} //= $uri->port;
	$args->{port} //= 0;
	$args->{tls} //= $uri->is_secure ? 1 : 0;
	$uri
}

sub check_listener {
	my ($self, $args) = @_;
	require Web::Async::CGI if exists $args->{cgi};
	require Web::Async::FastCGI if exists $args->{fastcgi};
	require Web::Async::PSGI if exists $args->{psgi};
	require Web::Async::UWSGI if exists $args->{uwsgi};
	require Web::Async::SPDY if exists $args->{spdy};
	require Web::Async::HTTP if exists $args->{http};
	require Web::Async::HTTP2 if exists $args->{http2};
	require Web::Async::Directory if exists $args->{directory};
	$self
}

=head2 request

Retry using current policy:

* Make connection
* If SSL:
** Try ALPN
** Try NPN
** Use https

Protocol negotiated through ALPN/NPN will be used to select handler class.

Connection allocation:

* Generate connkey using %args (anything TLS-related, host, port)
* Check if we have a free active connection - http2 means "can still allocate streams", http1 is "connected but not currently processing a request"
* Connect
* SSL if we have it

Apply request to connection. On ready, remove from active requests. Connection should update its own state automatically.

HTTP2 connections are added to the free active list as soon as possible, since they can queue and deliver requests once connection is established.

We don't know whether to favour a single or multiple connections until after the first request to a given host:port:TLS endpoint has been initiated.

* In HTTP2/SPDY-over-TLS mode, a single connection is typical - ALPN negotiation tells us when this is the case.

* In plain HTTP2 mode, again a single connection is used - we get this information from the HTTP Upgrade negotiation.

* In HTTP mode, multiple connections are probably a better default - no ALPN or 'http' as ALPN, or plaintext HTTP

So as soon as we assign the protocol, we can use a method on that protocol class to determine whether to upgrade this to a multi-connection key or
leave at a single connection.

 $self->{connection_limit}{$connkey} = $proto->suggested_parallel_connections;



=cut

sub request {
	my ($self, %args) = @_;
	$args{uri} = $self->upgrade_uri($args{uri}, \%args);
	my $req = Web::Async::Request->new(%args);
	my $f = $self->retry_policy(sub {
		$self->connection(%args)->then(sub {
			my ($conn) = @_;
			$conn->request($req)
		})
	}, %args)->set_label($req->method . ' ' . $req->uri);
	$self->model->requests->set_key(
		Scalar::Util::refaddr($f) => $f
	);
	$req
}

sub model { $_[0]->{model} //= Web::Async::Model->new }

sub bus { $_[0]->{bus} //= Mixin::Event::Dispatch::Bus->new }

sub retry_policy { my ($self, $code, %args) = @_; $code->() }

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

=over 4

=item * L<Net::Async::HTTP> - client support for HTTP1 requests

=item * L<Net::Async::HTTP::Server> - server support for HTTP1 (+PSGI wrapper)

=item * L<Mojolicious> - a popular web framework, also with async support

=back

=head1 AUTHOR

Tom Molesworth <cpan@perlsite.co.uk>

=head1 LICENSE

Copyright Tom Molesworth 2015. Licensed under the same terms as Perl itself.

