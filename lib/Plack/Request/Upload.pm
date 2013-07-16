package Plack::Request;
use v5.16;
use warnings;
use mop;

use Carp ();

class Upload {
    has $headers  is ro;
    has $tempname is ro;
    has $size     is ro;
    has $filename is ro;
    has $basename;

    method path { $tempname }

    method content_type { $headers->content_type(@_) }
    method type         { $self->content_type(@_)    }

    method basename {
        unless (defined $basename) {
            require File::Spec::Unix;
            $basename = $filename;
            $basename =~ s|\\|/|g;
            $basename = ( File::Spec::Unix->splitpath($basename) )[2];
            $basename =~ s|[^\w\.-]+|_|g;
        }
        $basename;
    }
}

1;
__END__

=head1 NAME

Plack::Request::Upload - handles file upload requests

=head1 SYNOPSIS

  # $req is Plack::Request
  my $upload = $req->uploads->{field};

  $upload->size;
  $upload->path;
  $upload->content_type;
  $upload->basename;

=head1 METHODS

=over 4

=item size

Returns the size of Uploaded file.

=item path

Returns the path to the temporary file where uploaded file is saved.

=item content_type

Returns the content type of the uploaded file.

=item filename

Returns the original filename in the client.

=item basename

Returns basename for "filename".

=back

=head1 AUTHORS

Kazuhiro Osawa

Tatsuhiko Miyagawa

=head1 SEE ALSO

L<Plack::Request>, L<Catalyst::Request::Upload>

=cut
