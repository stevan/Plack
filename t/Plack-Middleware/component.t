use strict;
use mop;

use Test::Requires qw(IO::Handle::Util);

use IO::Handle::Util qw(:io_from);
use HTTP::Request::Common;
use Test::More;
use Plack::Test;

class MyComponent extends Plack::Component {
    has $!res is rw;
    has $!cb  is rw;

    method call { $self->response_cb( $!res, $!cb ) }
}

# Various kinds of PSGI responses.
sub generate_responses {
    [200, ['Content-Type' => 'text/plain'], ['Hello']],
    [200, ['Content-Type' => 'text/plain'], io_from_array ['Hello']],
    sub { $_[0]->([ 200, ['Content-Type' => 'text/plain'], ['Hello'] ]) },
    sub {
        my $writer = $_[0]->([ 200, ['Content-Type' => 'text/plain'] ]);
        $writer->write( 'Hello' );
        $writer->close;
    },
}

# $body filters can return undef with no warnings.
for my $res ( generate_responses ) {
    my @warns;
    local $SIG{__WARN__} = sub { push @warns, @_ };

    my $app = MyComponent->new(
        res => $res, cb => sub { sub { $_[0] } },
    );
    test_psgi( $app, sub { $_[0]->(GET '/') } );

    is_deeply \@warns, [];
}

for my $res ( generate_responses ) {
    my $app = MyComponent->new(
        res => $res,
        cb  => sub {
            my $done;
            sub {
                return if $done;
                if (defined $_[0]) {
                    return $_[0];
                } else {
                    $done = 1;
                    return 'END';
                }
            },
        },
    )->to_app;
    test_psgi( $app, sub {
        my $res = $_[0]->(GET '/');
        is $res->content, 'HelloEND';
    } );
}

done_testing;
