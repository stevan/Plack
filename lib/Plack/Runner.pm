package Plack;
use v5.16;
use warnings;
use mop;

use Carp ();
use Plack::Util;
use Try::Tiny;

class Runner {

    # these all seem to be used internally
    has $!app;
    has $!server;
    has $!eval;
    has $!access_log;
    has $!path;
    has $!help;
    has $!version;
    has $!watch;
    has $!version_cb;

    # the tests asked to see these ...
    has $!daemonize          is ro;
    has $!options            is ro;
    has $!argv               is ro;
    has $!env                is ro = $ENV{PLACK_ENV};

    # these seem to have defaults
    has $!loader             = 'Plack::Loader';
    has $!_loader; ## << this just stores the loader instance
    has $!includes           = [];
    has $!modules            = [];
    has $!default_middleware = 1;

    # delay the build process for reloader
    method build ($block, $app) {
        $app ||= sub { };
        return sub { $block->($app->()) };
    }

    method parse_options {
        local @ARGV = @_;

        # From 'prove': Allow cuddling the paths with -I, -M and -e
        @ARGV = map { /^(-[IMe])(.+)/ ? ($1,$2) : $_ } @ARGV;

        my ($host, $port, $socket, @listen);

        require Getopt::Long;
        my $parser = Getopt::Long::Parser->new(
            config => [ "no_auto_abbrev", "no_ignore_case", "pass_through" ],
        );

        $parser->getoptions(
            "a|app=s"      => \$!app,
            "o|host=s"     => \$host,
            "p|port=i"     => \$port,
            "s|server=s"   => \$!server,
            "S|socket=s"   => \$socket,
            'l|listen=s@'  => \@listen,
            'D|daemonize'  => \$!daemonize,
            "E|env=s"      => \$!env,
            "e=s"          => \$!eval,
            'I=s@'         => $!includes,
            'M=s@'         => $!modules,
            'r|reload'     => sub { $!loader = "Restarter" },
            'R|Reload=s'   => sub { $!loader = "Restarter"; $self->loader->watch(split ",", $_[1]) },
            'L|loader=s'   => \$!loader,
            "access-log=s" => \$!access_log,
            "path=s"       => \$!path,
            "h|help"       => \$!help,
            "v|version"    => \$!version,
            "default-middleware!" => \$!default_middleware,
        );

        my(@options, @argv);
        while (defined(my $arg = shift @ARGV)) {
            if ($arg =~ s/^--?//) {
                my @v = split '=', $arg, 2;
                $v[0] =~ tr/-/_/;
                if (@v == 2) {
                    push @options, @v;
                } elsif ($v[0] =~ s/^(disable|enable)_//) {
                    push @options, $v[0], $1 eq 'enable';
                } else {
                    push @options, $v[0], shift @ARGV;
                }
            } else {
                push @argv, $arg;
            }
        }

        push @options, $self->mangle_host_port_socket($host, $port, $socket, @listen);
        push @options, daemonize => 1 if $!daemonize;

        $!options = \@options;
        $!argv    = \@argv;
    }

    method set_options {
        push @{$!options}, @_;
    }

    method mangle_host_port_socket ($host, $port, $socket, @listen) {

        for my $listen (reverse @listen) {
            if ($listen =~ /:\d+$/) {
                ($host, $port) = split /:/, $listen, 2;
                $host = undef if $host eq '';
            } else {
                $socket ||= $listen;
            }
        }

        unless (@listen) {
            if ($socket) {
                @listen = ($socket);
            } else {
                $port ||= 5000;
                @listen = ($host ? "$host:$port" : ":$port");
            }
        }

        return host => $host, port => $port, listen => \@listen, socket => $socket;
    }

    method version_cb {
        $!version_cb || sub {
            require Plack;
            print "Plack $Plack::VERSION\n";
        };
    }

    method setup {

        if ($!help) {
            require Pod::Usage;
            Pod::Usage::pod2usage(0);
        }

        if ($!version) {
            $self->version_cb->();
            exit;
        }

        if (@{$!includes}) {
            require lib;
            lib->import(@{$!includes});
        }

        if ($!eval) {
            push @{$!modules}, 'Plack::Builder';
        }

        for (@{$!modules}) {
            my($module, @import) = split /[=,]/;
            eval "require $module" or die $@;
            $module->import(@import);
        }
    }

    method locate_app (@args) {

        my $psgi = $!app || $args[0];

        if (ref $psgi eq 'CODE') {
            return sub { $psgi };
        }

        if ($!eval) {
            $self->loader->watch("lib");
            return build {
                no strict;
                no warnings;
                my $eval = "builder { $!eval;";
                $eval .= "Plack::Util::load_psgi(\$psgi);" if $psgi;
                $eval .= "}";
                eval $eval or die $@;
            };
        }

        $psgi ||= "app.psgi";

        require File::Basename;
        $self->loader->watch( File::Basename::dirname($psgi) . "/lib", $psgi );
        build { Plack::Util::load_psgi $psgi };
    }

    method watch (@dir) {
        push @{$!watch}, @dir
            if $!loader eq 'Restarter';
    }

    method apply_middleware ($_app, $_class, @args) {
        my $mw_class = Plack::Util::load_class($_class, 'Plack::Middleware');
        build { $mw_class->wrap($_[0], @args) } $_app;
    }

    method prepare_devel ($_app) {

        if ($!default_middleware) {
            $_app = $self->apply_middleware($_app, 'Lint');
            $_app = $self->apply_middleware($_app, 'StackTrace');
            if (!$ENV{GATEWAY_INTERFACE} and !$!access_log) {
                $_app = $self->apply_middleware($_app, 'AccessLog');
            }
        }

        push @{$!options}, server_ready => sub {
            my($args) = @_;
            my $name  = $args->{server_software} || ref($args); # $args is $!server
            my $host  = $args->{host} || 0;
            my $proto = $args->{proto} || 'http';
            print STDERR "$name: Accepting connections at $proto://$host:$args->{port}/\n";
        };

        $_app;
    }

    method loader {
        $!_loader ||= Plack::Util::load_class($!loader, 'Plack::Loader')->new;
    }

    method load_server ($__loader) {
        if ($!server) {
            return $__loader->load($!server, @{$!options});
        } else {
            return $__loader->auto(@{$!options});
        }
    }

    method run {

        unless (ref $self) {
            $self = $self->new;
            $self->parse_options(@_);
            return $self->run;
        }

        unless ($!options) {
            $self->parse_options();
        }

        my @args = @_ ? @_ : @{$!argv};

        $self->setup;

        my $_app = $self->locate_app(@args);

        if ($!path) {
            require Plack::App::URLMap;
            $_app = build {
                my $urlmap = Plack::App::URLMap->new;
                $urlmap->mount($!path => $_[0]);
                $urlmap->to_app;
            } $_app;
        }

        $ENV{PLACK_ENV} ||= $!env || 'development';
        if ($ENV{PLACK_ENV} eq 'development') {
            $_app = $self->prepare_devel($_app);
        }

        if ($!access_log) {
            open my $logfh, ">>", $!access_log
                or die "open($!access_log): $!";
            $logfh->autoflush(1);
            $_app = $self->apply_middleware($_app, 'AccessLog', logger => sub { $logfh->print( @_ ) });
        }

        my $__loader = $self->loader;
        $__loader->preload_app($_app);

        my $_server = $self->load_server($__loader);
        $__loader->run($_server);
    }
}

1;

__END__

=head1 NAME

Plack::Runner - plackup core

=head1 SYNOPSIS

  # Your bootstrap script
  use Plack::Runner;
  my $app = sub { ... };

  my $runner = Plack::Runner->new;
  $runner->parse_options(@ARGV);
  $runner->run($app);

=head1 DESCRIPTION

Plack::Runner is the core of L<plackup> runner script. You can create
your own frontend to run your application or framework, munge command
line options and pass that to C<run> method of this class.

C<run> method does exactly the same thing as the L<plackup> script
does, but one notable addition is that you can pass a PSGI application
code reference directly to the method, rather than via C<.psgi>
file path or with C<-e> switch. This would be useful if you want to
make an installable PSGI application.

Also, when C<-h> or C<--help> switch is passed, the usage text is
automatically extracted from your own script using L<Pod::Usage>.

=head1 NOTES

Do not directly call this module from your C<.psgi>, since that makes
your PSGI application unnecessarily depend on L<plackup> and won't run
other backends like L<Plack::Handler::Apache2> or mod_psgi.

If you I<really> want to make your C<.psgi> runnable as a standalone
script, you can do this:

  my $app = sub { ... };

  unless (caller) {
      require Plack::Runner;
      my $runner = Plack::Runner->new;
      $runner->parse_options(@ARGV);
      return $runner->run($app);
  }

  return $app;

B<WARNING>: this section used to recommend C<if (__FILE__ eq $0)> but
it's known to be broken since Plack 0.9971, since C<$0> is now
I<always> set to the .psgi file path even when you run it from
plackup.

=head1 SEE ALSO

L<plackup>

=cut


