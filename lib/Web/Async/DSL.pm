package Web::Async::DSL;

use strict;
use warnings;

=pod

Serve current directory on :80 and :443, using a generated cert on startup:

 perl -MWeb::Async::DSL -e'server { root "." }'

Just http:

 perl -MWeb::Async::DSL -e'server { http { root "." } }'

Just https, on port 1443:

 perl -MWeb::Async::DSL -e'server { https { port 1443; root "." } }'

Upload a file to a server:

 perl -MWeb::Async::DSL -e'PUT "somefile.tar.gz" => "http://example.com/upload"'

Show contents of a file:

 perl -MWeb::Async::DSL -e'GET "http://example.com/readme.txt" => \*STDOUT'

All headers for a URL:

 perl -MWeb::Async::DSL -e'OPTIONS "http://example.com/somewhere" => \*STDOUT'

=cut

1;

