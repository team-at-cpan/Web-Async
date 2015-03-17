#!/usr/bin/env perl
use strict;
use warnings;

{
	package Example::Model;
	use Adapter::Async::Model {
		name => 'string',
		items => {
			collection => 'OrderedList',
			type => 'string'
		},
	};
}
my $model = Example::Model->new;
widget_add item_list => sub {
	my ($parent, $items) = @_;
	widget list => $items;
};

app 'example' => sub {
	page 'index' => sub {
		title "Index page for " . $model->name;
		layout {
			input $model->name;
			submit 'OK';
			panel {
				widget item_list => $model->items;
			} id => 'items',
			  label => 'Items';
		}
	};
	form 'model' => sub {
		my ($form) = @_;
		$form->add_field('name' => 'string');
		$form->receive(sub {
			my ($form) = @_;
			if($form->exists_name('name')) {
				my $old = '' . $model->name;
				$model->name($form->by_name('name'));
				if($resp->is_html) {
					$resp->p
				}
			}
		});
	};
};

