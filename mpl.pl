#!/usr/bin/env perl
use strict;
use warnings;

package Web::Async::Model;

use Adapter::Async::Model {
	# 
	outgoing_requests => {

	},
	# Requests we've received but have not yet completed
	incoming_requests => {
	},
	# Established TCP/Unix connections to remotes
	connections => {

	},
	# IaNotifiers awaiting new incoming requests
	listeners => {

	},
	total_bytes_recv => 'bigint',
	total_bytes_sent => 'bigint',
};
