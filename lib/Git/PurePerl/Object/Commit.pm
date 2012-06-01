package Git::PurePerl::Object::Commit;
use Moose;
use MooseX::StrictConstructor;
use Moose::Util::TypeConstraints;
use Encode qw/decode/;
use namespace::autoclean;

extends 'Git::PurePerl::Object';

has 'kind' =>
    ( is => 'ro', isa => 'ObjectKind', required => 1, default => 'commit' );
has 'tree_sha1'   => ( is => 'rw', isa => 'Str', required => 0 );
has 'parent_sha1s' => ( is => 'rw', isa => 'ArrayRef[Str]', required => 0, default => sub { [] });
has 'author' => ( is => 'rw', isa => 'Git::PurePerl::Actor', required => 0 );
has 'authored_time' => ( is => 'rw', isa => 'DateTime', required => 0 );
has 'committer' =>
    ( is => 'rw', isa => 'Git::PurePerl::Actor', required => 0 );
has 'committed_time' => ( is => 'rw', isa => 'DateTime', required => 0 );
has 'comment'        => ( is => 'rw', isa => 'Str',      required => 0 );
has 'encoding'       => ( is => 'rw', isa => 'Str',      required => 0 );
has 'gpg_signature' =>
  ( is => 'rw', isa => 'Str', required => 0, predicate => 'has_gpg_signature' );

my %method_map = (
    'tree'      => 'tree_sha1',
    'parent'    => '_push_parent_sha1',
    'author'    => 'authored_time',
    'committer' => 'committed_time',
    'gpgsig'    => 'gpg_signature',
);

my %multiline_headers = ( gpgsig => 1, );


sub _verify {
    my ( $content, $signature ) = @_;
    ##
    ## This crap exists because there is no GnuPG module on CPAN that works.
    ## Seriously.
    ##
    require File::Tempdir;
    require File::Temp;
    require GnuPG;
    require File::Spec;
    my $tmpdir =
      File::Tempdir->new( 'GnuPG.XXXXX', DIR => File::Spec->tmpdir, );
    my $dir = $tmpdir->name;
    my ( $fh, $content_filename ) =
      File::Temp::tempfile( "content.XXXXX", DIR => $dir );
    my ( $sfh, $signature_filename ) =
      File::Temp::tempfile( "signature.XXXXX", DIR => $dir );
    $fh->print($content);
    $sfh->print($signature);
    $fh->close;
    $sfh->close;
    return GnuPG->new( gnupg_path => '/usr/bin/gpg', )->verify(
        file      => $content_filename,
        signature => $signature_filename,
    );
}
sub verify_signature {
    my $self = shift;
    return if ( not $self->has_gpg_signature );
    my ( $content, $sig ) =
      $self->_extract_multiline( 'gpgsig', split qq{\n}, $self->content );
    my $content_blob   = join qq{}, map { "$_\n" } @{$content};
    my $signature_blob = join qq{}, map { "$_\n" } @{$sig};
    return _verify( $content_blob, $signature_blob );
}


# Apparent format is roughly:
#
# <token><space><DATA>
# <space><DATA>        # repeated
#
# And a line not leading with <space> ends the token.
#
# Though, at present, git itself has this special-cased for GPG Signatures.

sub _extract_multiline {
    my ( $self, $mltag, @lines ) = @_;
    my @out;
    my @sig_out;
    my $i = 0;
  headstep: while ( $i < $#lines ) {
        my $line = $lines[$i];

        if ( $line =~ /^\Q$mltag\E (.*$)/ ) {
            push @sig_out, "$1";

            $i++;
            $line = $lines[$i];

            # Walk down lines until ....
          instep: while ( $i < $#lines ) {

                # until you hit an unindented line
                last instep if not $line =~ /^ (.*$)/;
                push @sig_out, "$1";

                $i++;
                $line = $lines[$i];

            }
        }

        # Empty line = end of header
        if ( $line =~ /^$/ ) {
            push @out, splice @lines, $i;
            last headstep;
        }

        push @out, $line;
        $i++;
    }
    return \@out, \@sig_out;
}

sub BUILD {
    my $self = shift;
    return unless $self->content;
    my @lines = split "\n", $self->content;
    my %header;
    while ( my $line = $lines[0] ) {
        last unless $line;

        my ( $key, $value ) = split ' ', $line, 2;

        if ( exists $multiline_headers{$key} ) {
            my ( $out, $data ) = $self->_extract_multiline( $key, @lines );
            push @{ $header{$key} }, join q{}, map { "$_\n" } @{$data};
            @lines = @{$out};
            next;
        }
        push @{ $header{$key} }, $value;
        shift @lines;
    }
    $header{encoding}
        ||= [ $self->git->config->get(key => "i18n.commitEncoding") || "utf-8" ];
    my $encoding = $header{encoding}->[-1];
    for my $key (keys %header) {
        for my $value (@{$header{$key}}) {
            $value = decode($encoding, $value);
            if ( $key eq 'committer' or $key eq 'author' ) {
                my @data = split ' ', $value;
                my ( $email, $epoch, $tz ) = splice( @data, -3 );
                $email = substr( $email, 1, -1 );
                my $name = join ' ', @data;
                my $actor
                    = Git::PurePerl::Actor->new( name => $name, email => $email );
                $self->$key($actor);
                $key = $method_map{$key};
                my $dt
                    = DateTime->from_epoch( epoch => $epoch, time_zone => $tz );
                $self->$key($dt);
            } else {
                $key = $method_map{$key} || $key;
                $self->$key($value);
            }
        }
    }
    $self->comment( decode($encoding, join "\n", @lines) );
}

=head1 METHODS

=head2 tree

Returns the L<< C<::Tree>|Git::PurePerl::Object::Tree >> associated with this commit.

=cut

sub tree {
    my $self = shift;
    return $self->git->get_object( $self->tree_sha1 );
}


sub _push_parent_sha1 {
    my ($self, $sha1) = @_;
  
    push(@{$self->parent_sha1s}, $sha1);
}

=head2 parent_sha1

Returns the C<sha1> for the first parent of this this commit.

=cut

sub parent_sha1 {
    return shift->parent_sha1s->[0];
}

=head2 parent

Returns the L<< C<::Commit>|Git::PurePerl::Object::Commit >> for this commits first parent.

=cut

sub parent {
    my $self = shift;
    return $self->git->get_object( $self->parent_sha1 );
}

=head2 parents

Returns L<< C<::Commit>s|Git::PurePerl::Object::Commit >> for all this commits parents.

=cut

sub parents {
    my $self = shift;
    
    return map { $self->git->get_object( $_ ) } @{$self->parent_sha1s};
}

=head2 has_ancestor_sha1

Traverses up the parentage of the object graph to find out if the given C<sha1> appears as an ancestor.

  if ( $commit_object->has_ancestor_sha1( 'deadbeef' x  5 ) ) {
    ...
  }

=cut

sub has_ancestor_sha1 {
    my ( $self, $sha1 ) = @_;

    # This may seem redundant, but its not entirely.
    # However, its a penalty paid for the branch shortening optimization.
    #
    # x^, y^ , z^ , y[ y^ , y... ] , z[ z^ , z... ]
    #
    # Will still be faster than
    #
    # x^, y[ y^ , y... ] , z[ z^ , z... ]
    #
    # In the event y is very long.

    return 1 if $self->sha1 eq $sha1;

    # This is a slight optimization of sorts,
    # as it means
    #   x->{ y->{ y' } , z->{ z' } }
    # has a check order of:
    #   x^, y^ , z^ , y[ y^ , ... ], z[ z^, ... ]
    # instead of
    #   x^, y[ y^, y... ], z[ z^, z... ]
    # Which will probably make things a bit faster if y is incredibly large
    # and you just want to check if a given commit x has a direct ancestor i.

    for my $parent ( @{ $self->parent_sha1s } ) {
        return 1 if $parent eq $sha1;
    }

    # Depth First.
    # TODO perhaps make it breadth first? could be very useful on very long repos
    # where the given ancestor might not be in the "first-parent" ancestry line.
    # But if somebody wants this feature, they'll have to provide the benchmarks, the code, or both.

    for my $parent ( $self->parents ) {
        return 1 if $parent->has_ancestor_sha1( $sha1, );
    }
    return;
}
__PACKAGE__->meta->make_immutable;

