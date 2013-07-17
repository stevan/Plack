package Plack::Middleware;
use v5.16;
use warnings;
use mop;

use Plack::Util;

class XFramework extends Plack::Middleware is overload('inherited') {
    has $framework is rw;
    
    method call ($env) {
        my $res = $self->app->( $env );
        $self->response_cb($res, sub {
            my $res = shift;
            if ($self->framework) {
                Plack::Util::header_set $res->[1], 'X-Framework' => $framework;
            }
        });
    }
}
1;

__END__

=head1 NAME

Plack::Middleware::XFramework - Sample middleware to add X-Framework

=head1 SYNOPSIS

  enable "Plack::Middleware::XFramework", framework => "Catalyst";

=head1 DESCRIPTION

This middleware adds C<X-Framework> header to the HTTP response.

=head1 CONFIGURATION

=over 4

=item framework

Sets the string value of C<X-Framework> header. If not set, the header is not set to the response.

=back

=head1 SEE ALSO

L<Plack::Middleware>

=cut

