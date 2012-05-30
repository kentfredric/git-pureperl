use strict;
use warnings;

use Test::More;

# FILENAME: 08_has_ancestor.t
# CREATED: 31/05/12 07:48:42 by Kent Fredric (kentnl) <kentfredric@gmail.com>
# ABSTRACT: Tests for has_ancestor
use strict;
use warnings;
use Test::More;
use Git::PurePerl;
use Path::Class;

sub shatrim {
    return substr( shift, 0, 8 );
}

sub repo_ancestor_check {
    my ( $repo, $commit, @ancestors ) = @_;
    my $git = Git::PurePerl->new( directory => $repo );
    my $commit_obj = $git->get_object($commit);
    for my $ancestor (@ancestors) {
        my ( $tcommit, $tancestor ) = map { shatrim($_) } $commit, $ancestor;
        ok(
            $commit_obj->has_ancestor_sha1($ancestor),
            "$repo @ $tcommit has ancestor $tancestor"
        );
    }
}

sub repo_ancestor_not_check {
    my ( $repo, $commit, @ancestors ) = @_;
    my $git = Git::PurePerl->new( directory => $repo );
    my $commit_obj = $git->get_object($commit);
    for my $ancestor (@ancestors) {
        my ( $tcommit, $tancestor ) = map { shatrim($_) } $commit, $ancestor;
        ok(
            !$commit_obj->has_ancestor_sha1($ancestor),
            "$repo @ $tcommit has no ancestor $tancestor"
        );
    }
}

repo_ancestor_check(
    'test-project' => '0c7b3d23c0f821e58cd20e60d5e63f5ed12ef391' => qw(
      a47f812b901251922153bac347a348604a24e372
      d24a32a404ce934cd4f39fd632fc1d43c413f652
      )
);

repo_ancestor_check(
    'test-project' => 'a47f812b901251922153bac347a348604a24e372' => qw(
      d24a32a404ce934cd4f39fd632fc1d43c413f652
      )
);

repo_ancestor_not_check(
    'test-project' => '0c7b3d23c0f821e58cd20e60d5e63f5ed12ef391' => qw(
      deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
      )
);

repo_ancestor_not_check(
    'test-project' => 'a47f812b901251922153bac347a348604a24e372' => qw(
      0c7b3d23c0f821e58cd20e60d5e63f5ed12ef391
      deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
      )
);
repo_ancestor_not_check(
    'test-project' => 'd24a32a404ce934cd4f39fd632fc1d43c413f652' => qw(
      0c7b3d23c0f821e58cd20e60d5e63f5ed12ef391
      deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
      a47f812b901251922153bac347a348604a24e372
      )
);

done_testing;

