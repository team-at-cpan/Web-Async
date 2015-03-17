package Web::Async::Model::Listener;

use strict;
use warnings;

use Adapter::Async::Model {
	instance => 'Web::Async::Listener',
	requests => {
		collection => 'UnorderedMap',
		item       => '::Request'
	}
};

1;
