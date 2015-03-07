package Web::Async::PSGI;

use strict;
use warnings;

use JSON::MaybeXS;

use PSGI;

sub run {
	my ($self) = @_;
	my $env = 
}
sub env {
	my ($self, $req) = @_;
	return {
		# The basics...
		REQUEST_METHOD  => $req->method,
		SCRIPT_NAME     => '',
		PATH_INFO           => $req->path,
		REQUEST_URI         => $req->uri,
		QUERY_STRING        => $req->query_string,
		SERVER_NAME         => $req->server_name,
		SERVER_PORT         => $req->port,
		SERVER_PROTOCOL     => uc($req->protocol),
		CONTENT_LENGTH      => $req->content_length,
		CONTENT_TYPE        => $req->content_type,
		# ... PSGI-specific
		'psgi.version'      => [1, 1],
		'psgi.url_scheme'   => $req->scheme,
		'psgi.input'        => undef,
		'psgi.errors'       => \*STDERR,
		'psgi.multithread'  => JSON->false,
		'psgi.multiprocess' => JSON->true,
		'psgi.nonblocking'  => JSON->true,
		'psgi.streaming'    => JSON->true,
		# ... other headers
		(
			map {; 'HTTP_' . uc($_) => ''.join(',', $req->header_values($_)) } $req->headers,
		),
	};
}

1;
