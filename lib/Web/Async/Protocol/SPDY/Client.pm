package Web::Async::Protocol::SPDY::Client;

use strict;
use warnings;

use Log::Any qw($log);

use Protocol::SPDY::Client;

=pod

This class represents a single (TCP) connection to a server. Due to the
multiplexed nature of the protocol, we could be dealing with multiple
active requests at any given moment.

=cut

sub new {
	my $class = shift;
	bless { @_ }, $class
}

sub spdy { shift->{spdy} }

=head2 on_stream

Called when we have an L<IO::Async::Stream> instance.

Instantiates a L<Protocol::SPDY> object for dealing with the protocol framing,
and attaches read/write handlers to pass through traffic accordingly.

=cut

sub on_stream {
	my ($self, $stream) = @_;

	$self->{spdy} = Protocol::SPDY::Client->new;
	# Pass all writes directly to the stream
	$self->{spdy}->{on_write} = $stream->curry::write;

	$stream->configure(
		on_read => $self->curry::weak::on_read
	);
}

sub on_read {
	my ($self, $stream, $buffref, $eof) = @_;
	# Dump everything we have - could process in chunks if you
	# want to be fair to other active sessions
	$log->debug("on_read in client");
	$self->spdy->on_read(substr $$buffref, 0, length($$buffref), '');

	if($eof) {
		$log->debugf("EOF detected");
		# ... then, er, what? raise an event maybe?
	}

	return 0;
}

=head2 request

Initiates a new request.

=cut

sub request {
	my ($self, $req) = @_;

	my $uri = $req->uri;
	$log->debugf("Request for great justice: %s", "$uri");

	my $spdy = $self->spdy;
	my $stream = $spdy->create_stream;

	my $body = '';
	$stream->subscribe_to_event(
		data => sub {
			my ($ev, $data) = @_;
			$log->debugf("Have data: %s", $data);
			$req->bus->invoke_event(data => $data);
		}
	);
	$stream->remote_finished->on_done(sub {
		$log->debug("Stream finished");
		$req->bus->invoke_event(finished => );
		$req->completion->done;
		Scalar::Util::weaken($stream);
	});
	$stream->replied->on_done(sub {
		my $hdr = $stream->received_headers;
		my ($version, $status) = map delete $hdr->{$_}, qw(:version :status);
		$log->debugf("Version %s, status [%s]", $version, $status);
		$req->bus->invoke_event(http_version => $version);
		for(sort keys %$hdr) {
			# Camel-Case the header names
			(my $k = $_) =~ s{(?:^|-)\K(\w)}{\U$1}g;
			$log->debugf("Header %s: %s", $k, $hdr->{$_});
		}
		$req->bus->invoke_event(headers => [ %$hdr ]);
		{
			my ($code, $msg) = $status =~ /(\d{3})(?: (.*))?/;
			$req->bus->invoke_event(status_code => $code => $msg);
		}
		# We may get extra headers, stash them until after data
		$stream->subscribe_to_event(headers => sub {
			my ($ev, $headers) = @_;
			$req->bus->invoke_event(headers => $headers);
		});
	});

	# $stream->remote_finished->on_done(sub { $loop->stop });
	$stream->start(
		fin     => 1,
		headers => {
			':method'  => 'GET',
			':path'    => '/' . $uri->path,
			':scheme'  => $uri->scheme,
			':host'    => $uri->host . ($uri->port ? ':' . $uri->port : ''),
			':version' => 'HTTP/1.1',
		}
	);
	Future->done
}

1;
