package HTTP::Server;
use v5.16;
use warnings;
use mop;

use Carp ();
use Plack;
use Plack::HTTPParser qw( parse_http_request );
use IO::Socket::INET;
use HTTP::Date;
use HTTP::Status;
use List::Util qw(max sum);
use Plack::Util;
use Stream::Buffered;
use Plack::Middleware::ContentLength;
use POSIX qw(EINTR);
use Socket qw(IPPROTO_TCP TCP_NODELAY);

use Try::Tiny;
use Time::HiRes qw(time);

my $alarm_interval;
BEGIN {
    if ($^O eq 'MSWin32') {
        $alarm_interval = 1;
    } else {
        Time::HiRes->import('alarm');
        $alarm_interval = 0.1;
    }
}

use constant MAX_REQUEST_SIZE => 131072;
use constant MSWin32          => $^O eq 'MSWin32';

class PSGI {

    has $!host            = 0;
    has $!port            = 8080;
    has $!timeout         = 300;
    has $!server_software = ${^META}->name;
    has $!server_ready    = do { sub {} };
    has $!listen_sock;
    has $!ssl;
    has $!ipv6;
    has $!ssl_key_file;
    has $!ssl_cert_file;

    method run ($app) {
        $self->setup_listener();
        $self->accept_loop($app);
    }

    method prepare_socket_class ($args) {

        if ($!ssl && $!ipv6) {
            Carp::croak("SSL and IPv6 are not supported at the same time (yet). Choose one.");
        }

        if ($!ssl) {
            eval { require IO::Socket::SSL; 1 }
                or Carp::croak("SSL suport requires IO::Socket::SSL");
            $args->{SSL_key_file}  = $!ssl_key_file;
            $args->{SSL_cert_file} = $!ssl_cert_file;
            return "IO::Socket::SSL";
        } elsif ($!ipv6) {
            eval { require IO::Socket::IP; 1 }
                or Carp::croak("IPv6 support requires IO::Socket::IP");
            $!host ||= '::';
            $args->{LocalAddr} ||= '::';
            return "IO::Socket::IP";
        }

        return "IO::Socket::INET";
    }

    method setup_listener {

        my %args = (
            Listen    => SOMAXCONN,
            LocalPort => $!port,
            LocalAddr => $!host,
            Proto     => 'tcp',
            ReuseAddr => 1,
        );

        my $socket_class = $self->prepare_socket_class(\%args);
        $!listen_sock ||= $socket_class->new(%args)
            or die "failed to listen to port $!port: $!";

        $!server_ready->({
            host            => $!host,
            port            => $!port,
            timeout         => $!timeout,
            server_software => $!server_software,
            server_ready    => $!server_ready,
            listen_sock     => $!listen_sock,
            ssl             => $!ssl,
            ipv6            => $!ipv6,
            ssl_key_file    => $!ssl_key_file,
            ssl_cert_file   => $!ssl_cert_file,
            proto           => $!ssl ? 'https' : 'http'
        });
    }

    method accept_loop ($app) {

        $app = Plack::Middleware::ContentLength->wrap($app);

        while (1) {
            local $SIG{PIPE} = 'IGNORE';
            if (my $conn = $!listen_sock->accept) {
                $conn->setsockopt(IPPROTO_TCP, TCP_NODELAY, 1)
                    or die "setsockopt(TCP_NODELAY) failed:$!";
                my $env = {
                    SERVER_PORT => $!port,
                    SERVER_NAME => $!host,
                    SCRIPT_NAME => '',
                    REMOTE_ADDR => $conn->peerhost,
                    REMOTE_PORT => $conn->peerport || 0,
                    'psgi.version' => [ 1, 1 ],
                    'psgi.errors'  => *STDERR,
                    'psgi.url_scheme' => $!ssl ? 'https' : 'http',
                    'psgi.run_once'     => Plack::Util::FALSE,
                    'psgi.multithread'  => Plack::Util::FALSE,
                    'psgi.multiprocess' => Plack::Util::FALSE,
                    'psgi.streaming'    => Plack::Util::TRUE,
                    'psgi.nonblocking'  => Plack::Util::FALSE,
                    'psgix.harakiri'    => Plack::Util::TRUE,
                    'psgix.input.buffered' => Plack::Util::TRUE,
                    'psgix.io'          => $conn,
                };

                $self->handle_connection($env, $conn, $app);
                $conn->close;
                last if $env->{'psgix.harakiri.commit'};
            }
        }
    }

    method handle_connection ($env, $conn, $app) {

        my $buf = '';
        my $res = [ 400, [ 'Content-Type' => 'text/plain' ], [ 'Bad Request' ] ];

        while (1) {
            my $rlen = $self->read_timeout(
                $conn, \$buf, MAX_REQUEST_SIZE - length($buf), length($buf),
                $!timeout,
            ) or return;
            my $reqlen = parse_http_request($buf, $env);
            if ($reqlen >= 0) {
                $buf = substr $buf, $reqlen;
                if (my $cl = $env->{CONTENT_LENGTH}) {
                    my $buffer = Stream::Buffered->new($cl);
                    while ($cl > 0) {
                        my $chunk;
                        if (length $buf) {
                            $chunk = $buf;
                            $buf = '';
                        } else {
                            $self->read_timeout($conn, \$chunk, $cl, 0, $!timeout)
                                or return;
                        }
                        $buffer->print($chunk);
                        $cl -= length $chunk;
                    }
                    $env->{'psgi.input'} = $buffer->rewind;
                } else {
                    open my $input, "<", \$buf;
                    $env->{'psgi.input'} = $input;
                }

                $res = Plack::Util::run_app $app, $env;
                last;
            }
            if ($reqlen == -2) {
                # request is incomplete, do nothing
            } elsif ($reqlen == -1) {
                # error, close conn
                last;
            }
        }

        if (ref $res eq 'ARRAY') {
            $self->_handle_response($res, $conn);
        } elsif (ref $res eq 'CODE') {
            $res->(sub {
                $self->_handle_response($_[0], $conn);
            });
        } else {
            die "Bad response $res";
        }

        return;
    }

    method _handle_response ($res, $conn) {

        my @lines = (
            "Date: @{[HTTP::Date::time2str()]}\015\012",
            "Server: $!server_software\015\012",
        );

        Plack::Util::header_iter($res->[1], sub {
            my ($k, $v) = @_;
            push @lines, "$k: $v\015\012";
        });

        unshift @lines, "HTTP/1.0 $res->[0] @{[ HTTP::Status::status_message($res->[0]) ]}\015\012";
        push @lines, "\015\012";

        $self->write_all($conn, join('', @lines), $!timeout)
            or return;

        if (defined $res->[2]) {
            my $err;
            my $done;
            {
                local $@;
                eval {
                    Plack::Util::foreach(
                        $res->[2],
                        sub {
                            $self->write_all($conn, $_[0], $!timeout)
                                or die "failed to send all data\n";
                        },
                    );
                    $done = 1;
                };
                $err = $@;
            };
            unless ($done) {
                if ($err =~ /^failed to send all data\n/) {
                    return;
                } else {
                    die $err;
                }
            }
        } else {
            return Plack::Util::inline_object
                write => sub { $self->write_all($conn, $_[0], $!timeout) },
                close => sub { };
        }
    }

    # returns 1 if socket is ready, undef on timeout
    method do_timeout ($cb, $_timeout) {
        local $SIG{ALRM} = sub {};
        my $wait_until = time + $_timeout;
        alarm($_timeout);
        my $ret;
        while (1) {
            if ($ret = $cb->()) {
                last;
            } elsif (! (! defined($ret) && $! == EINTR)) {
                undef $ret;
                last;
            }
            # got EINTR
            my $left = $wait_until - time;
            last if $left <= 0;
            alarm($left + $alarm_interval);
        }
        alarm(0);
        $ret;
    }

    # returns (positive) number of bytes read, or undef if the socket is to be closed
    method read_timeout ($sock, $buf, $len, $off, $_timeout) {
        $self->do_timeout(sub { $sock->sysread($$buf, $len, $off) }, $_timeout);
    }

    # returns (positive) number of bytes written, or undef if the socket is to be closed
    method write_timeout ($sock, $buf, $len, $off, $_timeout) {
        $self->do_timeout(sub { $sock->syswrite($buf, $len, $off) }, $_timeout);
    }

    # writes all data in buf and returns number of bytes written or undef if failed
    method write_all ($sock, $buf, $_timeout) {
        return 0 unless defined $buf;
        my $off = 0;
        while (my $len = length($buf) - $off) {
            my $ret = $self->write_timeout($sock, $buf, $len, $off, $_timeout)
                or return;
            $off += $ret;
        }
        return length $buf;
    }
}

1;

__END__

=head1 NAME

HTTP::Server::PSGI - Standalone PSGI compatible HTTP server

=head1 SYNOPSIS

  use HTTP::Server::PSGI;

  my $server = HTTP::Server::PSGI->new(
      host => "127.0.0.1",
      port => 9091,
      timeout => 120,
  );

  $server->run($app);

=head1 DESCRIPTION

HTTP::Server::PSGI is a standalone, single-process and PSGI compatible
HTTP server implementations.

This server should be great for the development and testing, but might
not be suitable for a production use.

Some features in HTTP/1.1, notably chunked requests, responses and
pipeline requests are B<NOT> supported, and it also does not support
HTTP/0.9.

See L<Starman> or uWSGI server if you want HTTP/1.1 and other features
ready for a production use.

=head1 PREFORKING

L<HTTP::Server::PSGI> does B<NOT> support preforking. See L<Starman>
or L<Starlet> if you want a multi-process prefork web servers.

=head1 HARAKIRI SUPPORT

This web server supports `psgix.harakiri` extension defined in the
L<PSGI::Extensions>.

This application is a non-forking single process web server
(i.e. `psgi.multiprocess` is false), and if your application commits
harakiri, the entire web server stops too. In case this behavior is
not what you want, be sure to check `psgi.multiprocess` as well to
enable harakiri only in the preforking servers such as L<Starman>.

On the other hand, this behavior might be handy if you want to embed
this module in your application and serve HTTP requests for only short
period of time, then go back to your main program.

=head1 AUTHOR

Kazuho Oku

Tatsuhiko Miyagawa

=head1 SEE ALSO

L<Plack::Handler::Standalone> L<Starman> L<Starlet>

=cut
