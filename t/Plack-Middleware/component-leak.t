use strict;
use warnings;
use mop;

use Test::More;
use Plack::Test;
use HTTP::Request::Common;

$Plack::Test::Impl = "Server";
local $ENV{PLACK_SERVER} = "HTTP::Server::PSGI";

class MyComponent extends Plack::Component {

    has $!res is weak_ref;
    has $!cb  is weak_ref;

    method call ($env) {

        if( $env->{PATH_INFO} eq '/run_response_cb' ){
            my $my;

            # Record $!res and $cb
            $!res = [200, ['Content-Type' => 'text/plain'], ['OK']];
            $!cb  = sub { $my }; # Contain $my to be regard as a closure.

            return $self->response_cb($!res, $!cb);
        }else{

            # Check if references are released.
            return [ 200, [
                'Content-Type' => 'text/plain',
                'X-Res-Freed'  => ! $!res,
                'X-Cb-Freed'   => ! $!cb,
            ], ['HELLO'] ];
        }
    }

}

my $app = MyComponent->new;
test_psgi( $app->to_app, sub {
    my $cb = shift;
    $cb->(GET '/run_response_cb');

    my $req = $cb->(GET '/check');
    ok $req->header('X-Res-Freed'), '$!res has been released.';
    ok $req->header('X-Cb-Freed') , '$cb has been released.';
} );

done_testing;
