package Plack::Middleware;
use v5.16;
use warnings;
use mop;

class Head extends Plack::Middleware is extending_non_mop {

    method call ($env) {

        return $self->app->($env)
            unless $env->{REQUEST_METHOD} eq 'HEAD';

        $self->response_cb($self->app->($env), sub {
            my $res = shift;
            if ($res->[2]) {
                $res->[2] = [];
            } else {
                return sub {
                    return defined $_[0] ? '': undef;
                };
            }
        });
    }
}

1;

__END__

=head1 NAME

Plack::Middleware::Head - auto delete response body in HEAD requests

=head1 SYNOPSIS

  enable "Head";

=head1 DESCRIPTION

This middleware deletes response body in HEAD requests.

=head1 AUTHOR

Tatsuhiko Miyagawa

=head1 SEE ALSO

Rack::Head

=cut

