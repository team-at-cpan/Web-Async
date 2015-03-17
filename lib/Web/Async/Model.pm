package Web::Async::Model;

use strict;
use warnings;

use Adapter::Async::Model {
	listeners => {
		collection => 'UnorderedMap',
		item       => '::Listener'
	},
	connections => {
		collection => 'UnorderedMap',
		item       => '::Connection'
	},
	requests => {
		collection => 'UnorderedMap',
		item       => '::Request'
	}
};

1;
