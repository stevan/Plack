package Plack::Middleware;
use v5.16;
use warnings;
use mop;

use Plack::Util;

class SimpleContentFilter extends Plack::Middleware is overload('inherited') {
    has $!filter is rw;

    method call ($env) {

        my $res = $self->app->($env);
        $self->response_cb($res, sub {
            my $res = shift;
            my $h = Plack::Util::headers($res->[1]);
            return unless $h->get('Content-Type');
            if ($h->get('Content-Type') =~ m!^text/!) {
                return sub {
                    my $chunk = shift;
                    return unless defined $chunk;
                    local $_ = $chunk;
                    $!filter->();
                    return $_;
                };
            }
        });
    }
}

1;

__END__

=head1 NAME

Plack::Middleware::SimpleContentFilter - Filters response content

=head1 SYNOPSIS

  use Plack::Builder;

  my $app = sub {
      return [ 200, [ 'Content-Type' => 'text/plain' ], [ 'Hello Foo' ] ];
  };

  builder {
      enable "Plack::Middleware::SimpleContentFilter",
          filter => sub { s/Foo/Bar/g; };
      $app;
  };

=head1 DESCRIPTION

B<This middleware should be considered as a demo. Running this against
your application might break your HTML unless you code the filter
callback carefully>.

Plack::Middleware::SimpleContentFilter is a simple content text filter
to run against response body. This middleware is only enabled against
responses with C<text/*> Content-Type.

=head1 AUTHOR

Tatsuhiko Miyagawa

=cut
