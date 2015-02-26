package Web::Async::Request;

use strict;
use warnings;

use Log::Any qw($log);

use Future;
use Variable::Disposition qw(retain_future);
use Mixin::Event::Dispatch::Bus;

sub new {
	my $class = shift;
	bless {
		new_future => sub { Future->new },
		@_
	}, $class
}
sub completion { $_[0]->{completion} //= $_[0]->new_future }
sub new_future { $_[0]->{new_future}->() }
sub bus { shift->{bus} //= Mixin::Event::Dispatch::Bus->new }

sub fail {
	my ($self, $exception, $source, @details) = @_;
	$self->completion->fail($exception, $source, @details)
}

sub uri { shift->{uri} }

sub http_request {
	my ($self) = @_;
	unless($self->{http_request}) {
		$self->{http_request} = HTTP::Request->new;
	}
	$self->{http_request}
}

=head2 response

Resolves to an L<HTTP::Response> instance.

=cut

sub http_response {
	my ($self) = @_;
	require HTTP::Response;

	my $f = $self->new_future;
	my $body = '';
	my ($code, $msg, $version);
	my $resp;
	my @hdr;
	$self->bus->subscribe_to_event(
		status_code => sub {
			(my $ev, $code, $msg) = @_;
		},
		version => sub {
			(my $ev, $version) = @_;
		},
		headers => sub {
			my ($ev, $headers) = @_;
			push @hdr, @$headers;
		},
		data => sub {
			my ($ev, $data) = @_;
			$log->debugf("Have data: %s", $data);
			$body .= $data;
		},
		finished => sub {
			$resp = HTTP::Response->new(
				$code => $msg, [ @hdr ]
			);
			$resp->protocol('HTTP/1.1');
			$resp->content($body);
			$resp->request($self->http_request);
			$f->done($resp);
		},
	);
	$self->completion->on_fail(sub { $f->fail(@_) });
	retain_future($f)
}

1;

