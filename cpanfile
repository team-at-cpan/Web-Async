requires 'parent', 0;
requires 'curry', 0;
requires 'Future', '>= 0.30';
requires 'Mixin::Event::Dispatch', '>= 1.006';

requires 'Log::Any', 0;

requires 'IO::Async', '>= 0.65';
requires 'IO::Async::SSL', '>= 0.14';
requires 'IO::Socket::SSL', '>= 2.010';

requires 'Protocol::SPDY', '>= 2.000';
requires 'Protocol::UWSGI', '>= 1.000';

on 'test' => sub {
	requires 'Test::More', '>= 0.98';
	requires 'Test::Fatal', '>= 0.010';
	requires 'Test::Refcount', '>= 0.07';
	requires 'Test::HexString', '>= 0.03';
};

