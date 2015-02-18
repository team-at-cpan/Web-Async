package Web::Async::Protocol::HTTP2::Client;

use strict;
use warnings;

use Log::Any qw($log);

use Protocol::SPDY::Client;

sub new {
	my $class = shift;
	bless { @_ }, $class
}

sub on_stream {
	my ($self, $stream) = @_;

	my $uri = URI->new('https://localhost/test/page');

	my $spdy = Protocol::SPDY::Client->new;
	# Pass all writes directly to the stream
	$spdy->{on_write} = $stream->curry::write;

	$stream->configure(
		on_read => sub {
			my ( $self, $buffref, $eof ) = @_;
			# Dump everything we have - could process in chunks if you
			# want to be fair to other active sessions
			$spdy->on_read(substr $$buffref, 0, length($$buffref), '');

			if( $eof ) {
				print "EOF\n";
			}

			return 0;
		}
	);
	my $req = $spdy->create_stream(
	);
	$req->subscribe_to_event(data => sub {
			my ($ev, $data) = @_;
			$log->debugf("Have data: %s", $data);
		});
	$req->replied->on_done(sub {
			my $hdr = $req->received_headers;
			$log->debugf("%s", join ' ', map delete $hdr->{$_}, qw(:version :status));
			for(sort keys %$hdr) {
				# Camel-Case the header names
				(my $k = $_) =~ s{(?:^|-)\K(\w)}{\U$1}g;
				$log->debugf("%s", join ': ', $k, $hdr->{$_});
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
}

1;
