package Plack::Handler::HTTP::Server;
use v5.16;
use warnings;
use mop;

class Simple {

    has $port;
    has $host;
    has $_server_ready;

    method run ($app) {

        my $server = Plack::Handler::HTTP::Server::Simple::PSGIServer->new($port);
        $server->host($host) if $host;
        $server->app($app);
        $server->{_server_ready} = $_server_ready || sub {};

        $server->run;
    }

}

class Simple::PSGIServer extends HTTP::Server::Simple::PSGI {

    method print_banner {
        $self->{_server_ready}->({
            host => $self->host,
            port => $self->port,
            server_software => 'HTTP::Server::Simple::PSGI',
        });
    }

}


1;

__END__

=head1 NAME

Plack::Handler::HTTP::Server::Simple - Adapter for HTTP::Server::Simple

=head1 SYNOPSIS

  plackup -s HTTP::Server::Simple --port 9090

=head1 DESCRIPTION

Plack::Handler::HTTP::Server::Simple is an adapter to run PSGI
applications on L<HTTP::Server::Simple>.

=head1 SEE ALSO

L<Plack>, L<HTTP::Server::Simple::PSGI>

=head1 AUTHOR

Tatsuhiko Miyagawa


=cut
