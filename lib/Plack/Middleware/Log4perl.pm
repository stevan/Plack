package Plack::Middleware;
use v5.16;
use warnings;
use mop;

use Carp ();

class Log4perl extends Plack::Middleware {
    has $!category is rw;
    has $!logger   is rw;
    has $!conf     is rw;

    method prepare_app {

        if ($!conf) {
            require Log::Log4perl;
            Log::Log4perl::init($!conf);
        }

        $!logger = Log::Log4perl->get_logger($!category || '');
    }

    method call ($env) {

        $env->{'psgix.logger'} = sub {
            my $args = shift;
            my $level = $args->{level};
            local $Log::Log4perl::caller_depth
                = $Log::Log4perl::caller_depth + 1;
            $!logger->$level($args->{message});
        };

        $self->app->($env);
    }
}

1;

__END__

=head1 NAME

Plack::Middleware::Log4perl - Uses Log::Log4perl to configure logger

=head1 SYNOPSIS

  use Log::Log4perl;

  Log::Log4perl::init('/path/to/log4perl.conf');

  builder {
      enable "Log4perl", category => "plack";
      $app;
  }

  # in log4perl.conf
  log4perl.logger.plack = INFO, Logfile
  log4perl.appender.Logfile = Log::Log4perl::Appender::File
  log4perl.appender.Logfile.filename = /path/to/logfile.log
  log4perl.appender.Logfile.layout   = Log::Log4perl::Layout::SimpleLayout

  # Or let middleware to configure log4perl
  enable "Log4perl", category => "plack", conf => '/path/to/log.conf';

=head1 DESCRIPTION

Log4perl is a L<Plack::Middleware> component that allows you to use
L<Log::Log4perl> to configure the logging object, C<psgix.logger>.

=head1 CONFIGURATION

=over 4

=item category

The C<log4perl> category to send logs to. Defaults to C<''> which means
it send to the root logger.

=item conf

The configuration file path (or a scalar ref containing the config
string) for L<Log::Log4perl> to automatically configure.

=back

=head1 AUTHOR

Tatsuhiko Miyagawa

=head1 SEE ALSO

L<Log::Log4perl>

L<Plack::Middleware::LogDispatch>

=cut

