package Web::Async::WebSocket::Server;
use Myriad::Class extends => 'IO::Async::Notifier';

use IO::Async::Listener;

use Web::Async::WebSocket::Server::Connection;

field $srv;
field $ryu;

method _add_to_loop ($loop) {
    $self->add_child(
        $ryu = Ryu::Async->new
    );
    $self->add_child(
        $srv = IO::Async::Listener->new(
            on_stream => $self->curry::weak::on_stream,
        )
    );
    $self->adopt_future(
        $srv->listen(
            service  => 7777,
            socktype => 'stream',
        )
    );
}

method on_stream ($listener, $conn, @) {
    $log->tracef('Connection %s for listener %s', "$conn", "$listener");
    $conn->configure(
        on_read => sub { 0 }
    );
    $self->add_child($conn);
    $self->adopt_future(
        $self->handle_connection($conn)
    );
}

async method handle_connection ($conn) {
}

1;
