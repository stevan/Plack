package Plack::Middleware;
use v5.16;
use warnings;
use mop;

use POSIX ();
use Scalar::Util ();

# Should this be in Plack::Util?
my $i = 0;
my %level_numbers = map { $_ => $i++ } qw(debug info warn error fatal);

class SimpleLogger extends Plack::Middleware is overload('inherited') {
    has $!level is rw;

    method call ($env) {

        my $min = $level_numbers{ $!level || "debug" };

        my $env_ref = $env;
        Scalar::Util::weaken($env_ref);

        $env->{'psgix.logger'} = sub {
            my $args = shift;

            if ($level_numbers{$args->{level}} >= $min) {
                $env_ref->{'psgi.errors'}->print($self->format_message($args->{level}, $args->{message}));
            }
        };

        $self->app->($env);
    }

    submethod format_time {
        my $old_locale = POSIX::setlocale(&POSIX::LC_ALL);
        POSIX::setlocale(&POSIX::LC_ALL, 'C');
        my $out = POSIX::strftime(@_);
        POSIX::setlocale(&POSIX::LC_ALL, $old_locale);
        return $out;
    }

    method format_message ($_level, $message) {
        my $time = $self->format_time("%Y-%m-%dT%H:%M:%S", localtime);
        sprintf "%s [%s #%d] %s: %s\n", uc substr($_level, 0, 1), $time, $$, uc $_level, $message;
    }
}

1;

__END__

=head1 NAME

Plack::Middleware::SimpleLogger - Simple logger that prints to psgi.errors

=head1 SYNOPSIS

  enable "SimpleLogger", level => "warn";

=head1 DESCRIPTION

SimpleLogger is a middleware component that formats the log message
with information such as the time and PID and prints them to
I<psgi.errors> stream, which is mostly STDERR or server log output.

=head1 SEE ALSO

L<Plack::Middleware::LogErrors>, essentially the opposite of this module

=head1 AUTHOR

Tatsuhiko Miyagawa

=cut
