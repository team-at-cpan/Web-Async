package Web::Async::Protocol::SPDY::Server;

use strict;
use warnings;

use curry;
use Protocol::SPDY::Server;
use Log::Any qw($log);
use List::Util qw(min);

sub new {
	my ($class) = shift;
	bless { @_ }, $class
}

sub on_stream {
	my ($self, $stream) = @_;

	$self->{spdy} = my $spdy = Protocol::SPDY::Server->new;

	# Pass all writes directly to the stream
	$spdy->{on_write} = $stream->curry::write;

	$spdy->subscribe_to_event(
		stream => sub {
			my $ev = shift;
			my $stream = shift;
			$log->debug("New SPDY stream incoming");
			$stream->closed->on_fail(sub {
				$log->errof("SPDY stream closed due to error: %s", shift);
			});
			my $hdr = { %{$stream->received_headers} };
			my $req = HTTP::Request->new(
				(delete $hdr->{':method'}) => (delete $hdr->{':path'})
			);
			$req->protocol(delete $hdr->{':version'});
			my $scheme = delete $hdr->{':scheme'};
			my $host = delete $hdr->{':host'};
			$req->header('Host' => $host);
			$req->header($_ => delete $hdr->{$_}) for keys %$hdr;
			$log->tracef("Request on stream: %s", $req->as_string(" | "));

			# You'd probably raise a 400 response here, but it's a conveniently
			# easy way to demonstrate our reset handling
			return $stream->reset(
				'REFUSED'
			) if $req->uri->path =~ qr{^/reset/refused};

			my $response = HTTP::Response->new(
				200 => 'OK', [
					'Content-Type' => 'text/html; charset=UTF-8',
				]
			);
			$response->protocol($req->protocol);

			my $input = $req->as_string("\n");
			my $output = <<"HTML";
<!DOCTYPE html>
<html>
<head>
<title>Example SPDY server</title>
<style type="text/css">
* { margin: 0; padding: 0 }
h1 { color: #ccc; background: #333 }
p { padding: 0.5em }
</style>
</head>
<body>
<h1>Protocol::SPDY example server</h1>
<p>
Your request was parsed as:
</p>
<pre>
$input
</pre>
</body>
</html>
HTML
			# At the protocol level we only care about bytes. Make sure that's all we have.
			$output = Encode::encode('UTF-8' => $output);
			$response->header('Content-Length' => length $output);
			my %hdr = map {; lc($_) => ''.$response->header($_) } $response->header_field_names;
			delete @hdr{qw(connection keep-alive proxy-connection transfer-encoding)};
			$log->trace("Sending response on stream");
			$stream->reply(
				fin => 0,
				headers => {
					%hdr,
					':status'  => join(' ', $response->code, $response->message),
					':version' => $response->protocol,
				}
			);
			$stream->send_data(substr $output, 0, min(64, length($output)), '') while length $output;
			$stream->send_data('', fin => 1);
		}
	);
	$log->debug("set on_read handler");
	$stream->configure(
		on_read => $self->curry::weak::on_read,
	)
}

sub spdy { shift->{spdy} }

sub on_read {
	my ($self, $stream, $buffref, $eof) = @_;
	# Dump everything we have - could process in chunks if you
	# want to be fair to other active sessions
	$log->debug("on_read");
	$self->spdy->on_read(substr $$buffref, 0, length($$buffref), '');

	if($eof) {
		$log->debugf("EOF detected");
	}

	return 0;
}

1;

