package Plack::Middleware;
use v5.16;
use warnings;
use mop;

use Plack::Util;
use Time::HiRes;

class Runtime extends Plack::Middleware is overload('inherited') {
    has $header_name is rw = 'X-Runtime';

    method call ($env) {

        my $start = [ Time::HiRes::gettimeofday ];
        my $res = $self->app->($env);

        $self->response_cb($res, sub {
            my $res = shift;
            my $req_time = sprintf '%.6f', Time::HiRes::tv_interval($start);
            Plack::Util::header_set($res->[1], $header_name, $req_time);
        });
    }
}

1;

__END__

=head1 NAME

Plack::Middleware::Runtime - Sets an X-Runtime response header

=head1 SYNOPSIS

  enable "Runtime";

=head1 DESCRIPTION

Plack::Middleware::Runtime is a Plack middleware component that sets
the application's response time (in seconds) in the I<X-Runtime> HTTP response
header.

=head1 OPTIONS

=over 4

=item header_name

Name of the header. Defaults to I<X-Runtime>.

=back

=head1 AUTHOR

Tatsuhiko Miyagawa

=head1 SEE ALSO

L<Time::HiRes> Rack::Runtime

=cut
