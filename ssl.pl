#!/usr/bin/env perl 
use strict;
use warnings;
package Thing;
use parent qw(IO::Async::Notifier);
use Template;
use File::Temp;
use Variable::Disposition qw(retain_future);

sub _add_to_loop {
	my ($self, $loop) = @_;
	$self->add_child(
		$self->{system} = IO::AsyncX::System->new
	);
	my $dir = File::Temp::tempdir(CLEANUP => 1);
	$self->{tls_path} = $dir;
	mkdir "$dir/certs" or die $!;
	mkdir "$dir/private" or die $!;
	{ open my $fh, '>:encoding(UTF-8)', "$dir/serial" or die $!; $fh->print("100001\n"); }
	{ open my $fh, '>:encoding(UTF-8)', "$dir/certindex.txt" or die $!; }
	{
		open my $fh, '>:encoding(UTF-8)', "$dir/openssl.cnf" or die $!;
		my $tt = Template->new;
		$tt->process(\q{
dir = [% dir %]
 
[ca]
default_ca = CA_default
 
[CA_default]
serial = $dir/serial
database = $dir/certindex.txt
new_certs_dir = $dir/certs
certificate	= $dir/certs/ca.cert.pem
private_key	= $dir/private/cakey.pem
default_days = 365
default_md = md5
preserve = no
email_in_dn = no
nameopt = default_ca
certopt	= default_ca
policy = policy_match
 
[policy_match]
countryName = match
stateOrProvinceName = match
organizationName = match
organizationalUnitName = optional
commonName = supplied
emailAddress = optional
 
[ req ]
default_bits = 2048 # Size of keys
default_keyfile = key.pem # name of generated keys
default_md = sha256 # message digest algorithm
string_mask = nombstr # permitted characters
distinguished_name = req_distinguished_name
req_extensions = v3_req
 
[ req_distinguished_name ]
# Variable name Prompt string
#------------------------- ----------------------------------
0.organizationName = Organization Name (company)
organizationalUnitName = Organizational Unit Name (department, division)
emailAddress = Email Address
emailAddress_max = 40
localityName = Locality Name (city, district)
stateOrProvinceName = State or Province Name (full name)
countryName = Country Name (2 letter code)
countryName_min = 2
countryName_max = 2
commonName = Common Name (hostname, IP, or your name)
commonName_max = 64
 
# Default values for the above, for consistency and less typing.
# Variable name Value
#------------------------ ------------------------------
0.organizationName_default = web::async
localityName_default = default
stateOrProvinceName_default = London
countryName_default = GB
 
[v3_ca]
basicConstraints = CA:TRUE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer:always
 
[v3_req]
basicConstraints = CA:FALSE
subjectKeyIdentifier = hash
}, {
			dir => $dir,
		}, $fh) or die $tt->error;
	}
	$self->{ready} = $self->prepare_certs;
}

sub system { shift->{'system'} }
sub tls_path { shift->{tls_path} }

#openssl genrsa -out server.pem 2048
# openssl req -new -x509 -nodes -sha1 -days 3650 -key server.pem > server.cert

sub prepare_certs {
	my ($self) = @_;
	my $system = $self->system;
	my $dir = $self->tls_path;
	$ENV{OPENSSL_CONF} = "$dir/openssl.cnf";
	eval {
	# First, let's make ourselves a CA
	(-r "$dir/private/ca.key.pem"
	? Future->done : (
		$system->run([
			qw(openssl genrsa -aes256),
			qw(-out),    "$dir/private/ca.key.pem",
			qw(-passout), "pass:webasync",
			4096,
		])->transform(done => sub {
			my ($code, $stdout, $stderr) = @_;
			print "Exit $code\n";
			print "E=> $_\n" for @$stderr;
			print "* $_\n" for @$stdout;
			()
		})
	))->then(sub {
		(-r "$dir/private/ca.cert.pem"
		? Future->done : (
			$system->run([
				qw(openssl req -new -x509),
				qw(-days 9125),
				qw(-batch),
				qw(-verbose),
				qw(-sha256),
				qw(-extensions v3_ca),
				qw(-subj),   "/C=GB/ST=>London/L=London/O=IT/CN=Web::Async Root CA",
				qw(-key),    "$dir/private/ca.key.pem",
				qw(-out),    "$dir/certs/ca.cert.pem",
				qw(-config), "$dir/openssl.cnf",
				qw(-passin), "pass:webasync",
				qw(-passout), "pass:webasync",
			])->transform(done => sub {
				my ($code, $stdout, $stderr) = @_;
				print "Exit $code\n";
				print "E=> $_\n" for @$stderr;
				print "* $_\n" for @$stdout;
				()
			})
		))
	})->then(sub {
		(-r "$dir/private/websign.key.pem"
		? Future->done : (
			$system->run([
				qw(openssl genrsa -aes256),
				qw(-out),    "$dir/private/websign.key.pem",
				qw(-passout), "pass:webasync",
				4096,
			])->transform(done => sub {
				my ($code, $stdout, $stderr) = @_;
				print "Exit $code\n";
				print "E=> $_\n" for @$stderr;
				print "* $_\n" for @$stdout;
				()
			})
		))
	})->then(sub {
		(-r "$dir/certs/websign.csr.pem"
		? Future->done : (
			$system->run([
				qw(openssl req -sha256 -new),
				qw(-batch),
				qw(-verbose),
				qw(-sha256),
				qw(-extensions v3_ca),
				qw(-subj),   "/C=GB/ST=>London/L=London/O=IT/CN=Web::Async websigning CA",
				qw(-key),    "$dir/private/websign.key.pem",
				qw(-out),    "$dir/certs/websign.csr.pem",
				qw(-config), "$dir/openssl.cnf",
				qw(-passin), "pass:webasync",
				qw(-passout), "pass:webasync",
			])->transform(done => sub {
				my ($code, $stdout, $stderr) = @_;
				print "Exit $code\n";
				print "E=> $_\n" for @$stderr;
				print "* $_\n" for @$stdout;
				()
			})
		))
	})->then(sub {
		(-r "$dir/certs/websign.cert.pem"
		? Future->done : (
			$system->run([
				qw(openssl ca),
				qw(-days 3650),
				qw(-keyfile), "$dir/private/ca.key.pem",
				qw(-cert),    "$dir/certs/ca.cert.pem",
				qw(-extensions v3_ca),
				qw(-notext),
				qw(-md sha256),
				qw(-in),     "$dir/certs/websign.csr.pem",
				qw(-out),    "$dir/certs/websign.cert.pem",
				qw(-batch),
				qw(-verbose),
				qw(-config), "$dir/openssl.cnf",
				qw(-passin), "pass:webasync",
			])->transform(done => sub {
				my ($code, $stdout, $stderr) = @_;
				print "Exit $code\n";
				print "E=> $_\n" for @$stderr;
				print "* $_\n" for @$stdout;
				()
			})
		))
	}) } or do { warn "failure exception  - $@"; Future->done };
}

sub sign {
	my ($self, %args) = @_;
	my $host = delete $args{host};
	my $dir = $self->tls_path;
	my $system = $self->system;
	$ENV{OPENSSL_CONF} = "$dir/openssl.cnf";
	retain_future(
		$self->ready->then(sub {
			$system->run([
				qw(openssl genrsa -aes256),
				qw(-out),    "$dir/private/" . $host . ".key.pem",
				qw(-passout), "pass:webasync",
				4096,
			])
		})->then(sub {
			my ($code, $stdout, $stderr) = @_;
#			print "Intermediate sign req gave exit $code\n";
#			print "E=> $_\n" for @$stderr;
#			print "* $_\n" for @$stdout;
			$system->run([
				qw(openssl req -new),
				qw(-batch),
				qw(-verbose),
				qw(-days 3650),
				qw(-subj),   "/C=GB/ST=>London/L=London/O=IT/CN=$host",
				qw(-key),    "$dir/private/${host}.key.pem",
				qw(-out),    "$dir/certs/${host}.csr.pem",
				qw(-config), "$dir/openssl.cnf",
				qw(-passin), "pass:webasync",
				qw(-passout), "pass:webasync",
			])
		})->then(sub {
			my ($code, $stdout, $stderr) = @_;
#			print "sign for www.wa request - exit $code\n";
#			print "E=> $_\n" for @$stderr;
#			print "* $_\n" for @$stdout;
			$system->run([
				qw(openssl ca),
				qw(-days 3650),
				qw(-keyfile), "$dir/private/websign.key.pem",
				qw(-cert),    "$dir/certs/websign.cert.pem",
				qw(-extensions v3_ca),
				qw(-notext),
				qw(-md sha256),
				qw(-in),     "$dir/certs/${host}.csr.pem",
				qw(-out),    "$dir/certs/${host}.cert.pem",
				qw(-batch),
				qw(-verbose),
				# qw(-subj),   "/C=GB/ST=>London/L=London/O=IT/CN=example.web-async",
				qw(-config), "$dir/openssl.cnf",
				qw(-passin), "pass:webasync",
			])
		})->then(sub {
			my ($code, $stdout, $stderr) = @_;
#			print "ca for www.wa request - exit $code\n";
#			print "E=> $_\n" for @$stderr;
#			print "* $_\n" for @$stdout;
			Future->done("$dir/certs/${host}.cert.pem")
		})
	)
}
sub ready { shift->{ready} }

package main;
use IO::AsyncX::System;
use IO::Async::Loop;

use Log::Any::Adapter qw(Stdout);

my $loop = IO::Async::Loop->new;
$loop->add(
	my $tls = Thing->new
);
print "Cert: $_\n" for $tls->ready->then(sub {
	Future->needs_all(
		$tls->sign(host => "some.random.host"),
		$tls->sign(host => "other.random.host"),
	)
})->get;
warn "here: \n";
<>;
