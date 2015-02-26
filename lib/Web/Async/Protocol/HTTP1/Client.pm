package Web::Async::Protocol::HTTP1::Client;

use strict;
use warnings;

use Log::Any qw($log);

sub new {
	my $class = shift;
	bless { @_ }, $class
}

sub on_stream {
	my ($self, $stream) = @_;

	my $uri = URI->new('https://localhost/test/page');

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
	}

	return 0;
}

sub request {
	my ($self, %args) = @_;

	# Generate an HTTP::Response object with all body data
	$args{make_response} = 1;

	my $uri = $args{uri};
	$log->debugf("Request for great justice: %s", "$uri");

	my $spdy = $self->spdy;
	my $req = $spdy->create_stream;
	my $body = '';
	$req->subscribe_to_event(
		data => sub {
			my ($ev, $data) = @_;
			$log->debugf("Have data: %s", $data);
			$body .= $data if $args{make_response};
		}
	);
	my $resp;
	$req->remote_finished->on_done(sub {
		$log->debug("Stream finished");
		$resp->content($body);
		$args{http_response}->done($resp);
	});
	$req->replied->on_done(sub {
		my $hdr = $req->received_headers;
		my ($version, $status) = map delete $hdr->{$_}, qw(:version :status);
		$log->debugf("Version %s, status [%s]", $version, $status);
		for(sort keys %$hdr) {
			# Camel-Case the header names
			(my $k = $_) =~ s{(?:^|-)\K(\w)}{\U$1}g;
			$log->debugf("Header %s: %s", $k, $hdr->{$_});
		}
		{
			my ($code, $msg) = $status =~ /(\d{3}) (.*)/;
			$resp = HTTP::Response->new(
				$code => $msg, [ %$hdr ]
			);
			$resp->protocol('HTTP/1.1');
		}
		# We may get extra headers, stash them until after data
		$req->subscribe_to_event(headers => sub {
			my ($ev, $headers) = @_;
			# ...
		});
	});
	# $req->remote_finished->on_done(sub { $loop->stop });
	$req->start(
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

