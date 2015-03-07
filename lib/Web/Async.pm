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

=head2 Features

=over 4

=item * Protocol selection - client/server will autonegotiate a suitable transport protocol (HTTP2, SPDY, HTTP1.1)

 $web->listen('*')->then(sub {
  $web->GET('https://localhost')->protocol->then(sub {
   my ($proto) = @_;
   print "Protocol: " . $proto . "\n";
   Future->done
  });
 })->get;

=item * TLS - client/server cert, ALPN

 $web->listen('https://some.example.com')->then(sub {
  $web->GET('https://localhost')->tls->then(sub {
   my ($tls) = @_;
   print "Domain:      " . $tls->sni . "\n";
   print "Server cert: " . $tls->server_cert . "\n";
   print "Client cert: " . $tls->client_cert . "\n";
   print "ALPN:        " . join(',', $tls->alpn_protocols) . "\n";
   Future->done
  });
 })->get;

=item * DANE - certs from DNS

 $loop->add(
  my $dns = Net::Async::DNS->new
 );
 $loop->add(
  my $web = Web::Async->new
 );
 my $uri = URI->new('https://dane-test.example.com');
 Future->needs_all(
  $web->listen($uri),
  $dns->listen('udp://*:0')
 )->then(sub {
  my ($http_srv, $dns_srv) = @_;
  $loop->set_resolver($dns_srv->resolver);
  $dns_srv->add_server($http_srv)
 })->then(sub {
  $web->GET($uri)->tls->on_done(sub {
   my ($tls) = @_;
   print "Domain:      " . $tls->sni . "\n";
   print "Server cert: " . $tls->server_cert . "\n";
   print "Client cert: " . $tls->client_cert . "\n";
   print "ALPN:        " . join(',', $tls->alpn_protocols) . "\n";
  });
 })->get;

=item * Timeout - per-request timeout configuration

=item * Encoding - gzip/zlib compression will be applied by default if the other side understands it

=item * Bandwidth/usage limiting - request accounting and rules support limits per host/key with various
restriction and backoff policies

=item * Retry - automatically retry requests with backoff

=item * Streaming - support sink/source and stream types (sendfile/coderef/handle) and multipart requests

=item * Concurrency - Per-host, domain, key limits for active requests

=back

Transport-layer protocol implementations are from the following modules:

=over 4

=item * L<Protocol::HTTP::V1_1> - implements the protocol as described in RFC2616 and subsequently updated in RFC7230-RFC7236

=item * L<Protocol::HTTP::V2_0> - implements SPDY/4 / HTTP2

=item * L<Protocol::HTTP::SPDY3_1> - implements SPDY/3.1

=item * L<Protocol::UWSGI> - implements UWSGI

=item * L<Protocol::CGI> - implements CGI

=back

=head2 Motivation

This module mainly exists to provide seamless support for HTTP2/SPDY alongside existing protocols such as HTTP1, UWSGI and FastCGI.
The SPDY and HTTP2 protocols add some concepts (priority, server push) which are not yet exposed in most existing HTTP modules.

Simple to start a server for a PSGI coderef and later extend to a more flexible object.

Ability to replace nginx/apache2 and gain full SPDY/HTTP2 while still supporting legacy backends via CGI/FastCGI/HTTP proxy.

Act as a proxy and integrate with existing proxies (HTTP, SOCKS, tor).

=head2 Listening for requests

These can be given as paths (for files and Unix-domain sockets) or URIs. Some examples of valid entries:

=over 4

=item * https://localhost:3089

=item * tcp://host:port or just tcp/port

=item * udp://host:port or just udp/port

=item * unix:///path

=item * file:///path

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

Missing files will present a 404 error, basic directory listing (+read-only DAV methods such as PROPFIND) supported.
Full write access is enabled with the C< dav > option:

 $web->listen(
  'http://static.example.com',
  directory => '/var/www/example.com/writable',
  dav => 1,
 );

=head2 Listening as a tor service

Exposing a service via Tor:

Add these lines to /etc/torrc:

 HiddenServiceDir /opt/tor/hidden_service/
 HiddenServicePort 80 127.0.0.1:8080

Once tor has restarted with the new config and generated a key for the hidden service:

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
  'http://perlwebhpaqrgtzi.onion',
  proxy => 'socks5://127.0.0.1:9050',
 )->get;

=head2 Sending requests

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
 })->get;

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

Blindly accept incoming requests, acting as proxy for http1/http2 on ports :80 and :443:

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

=head2 PUT from file

On some platforms, using a file name or handle to send data can be optimised by the sendfile()
operation. Other platforms will just use the standard read/write pair.

 $web->listen(
  'localhost',
  directory => File::Temp::tempdir(),
  allow_upload => 1,
 )->then(sub {
  my ($srv) = @_;
  $web->PUT(
   $srv->base_uri . '/file.mp4'
  )->from_file('file.mp4')
 })->get;

=head2 Form upload

File uploads via POST typically use the multipart/formdata MIME type.

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

=head2 Stream between servers

Transfer files between two servers - copy a Facebook photo to a Twitter post, for example:

 $web->GET(
  $facebook_wall->photo_url('...')
 )->send_to(
  $web->PUT(
   $twitter->post_photo,
   parts => [],
  )
 )->get;

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

=head2 Upload files recursively

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

=head3 Database wrappers

There's a few helper modules for common tasks - UI and REST interface for
accessing data in an SQLite database:

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

 use Net::Async::IMAP::Server;
 use Net::Async::SMTP::Server;
 use Net::Async::AMQP::Server;
 use WebService::Amazon::DynamoDB::Server;
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
  imap     => Net::Async::IMAP::Server->new(%args),
  webmail  => Net::Async::IMAP::Client->new(%args),
  smtp     => Net::Async::SMTP::Server->new(%args),
  amqp     => Net::Async::AMQP::Server->new(%args),
  dns      => Net::Async::DNS::Server->new(%args),
  files    => FS::Async::Server->new(%args, path => File::Temp::tempdir()),
  dynamodb => WebService::Amazon::DynamoDB::Server->new(%args),
 );
 Future->needs_all(
  $web->auth->create_admin->then(sub {
   my $admin = shift;
   warn "Admin user is " . $admin->user . " with password " . $admin->password;
  }),
  map $web->listen($_ . '.localhost')->then(sub {
   my ($srv) = @_;
   $srv_wrap->($srv, $srv{$_})
  }), keys %srv
 )->get;
 $loop->run;

=head2 

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

=over 4

=item * L<Net::Async::HTTP> - client support for HTTP1 requests

=item * L<Net::Async::HTTP::Server> - server support for HTTP1 (+PSGI wrapper)

=item * L<Mojolicious> - a popular web framework, also with async support

=back

=head1 AUTHOR

Tom Molesworth <cpan@perlsite.co.uk>

=head1 LICENSE

Copyright Tom Molesworth 2015. Licensed under the same terms as Perl itself.

