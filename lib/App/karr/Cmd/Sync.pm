# ABSTRACT: Sync karr board with remote

package App::karr::Cmd::Sync;
our $VERSION = '0.004';
use Moo;
use MooX::Cmd;
use feature 'say';
use MooX::Options (
    usage_string => 'USAGE: karr sync [--push] [--pull]',
);
use App::karr::Role::BoardAccess;

with 'App::karr::Role::BoardAccess';

=head1 SYNOPSIS

    karr sync
    karr sync --pull
    karr sync --push

=head1 DESCRIPTION

Synchronises the local board directory with the Git refs used by C<karr>.
Without flags it performs both directions: fetch and materialise refs locally,
then serialise the local board back into refs and push them to the remote.

=head1 OPTIONS

=over 4

=item * C<--pull>

Only fetches and materialises remote C<refs/karr/*>.

=item * C<--push>

Only serialises local board state and pushes it to the configured remote.

=back

=cut

option push => ( is => 'ro', default => 0, doc => 'Push refs to remote' );
option pull => ( is => 'ro', default => 0, doc => 'Pull refs from remote' );

sub execute {
    my ( $self, $args, $data ) = @_;

    require App::karr::Git;
    my $git = App::karr::Git->new( dir => $self->board_dir->parent->stringify );

    unless ( $git->is_repo ) {
        say "Not a git repository. Skipping sync.";
        return;
    }

    my $email = $git->git_user_email;
    my $name = $git->git_user_name;
    unless ($email) {
        say q(No git user.email configured. Run: git config --global user.email 'you@example.com');
        return;
    }

    say "User: $name <$email>";

    my $push_only = $self->push && !$self->pull;
    my $pull_only = $self->pull && !$self->push;

    unless ($push_only) {
        say "Pulling refs/karr/ from remote...";
        $git->pull;
        say "Materializing board from refs...";
        $self->_materialize_from_refs($git);
    }

    unless ($pull_only) {
        say "Serializing board to refs...";
        $self->_serialize_to_refs($git);
        say "Pushing refs/karr/ to remote...";
        $git->push;
    }

    say "Done.";
}

1;
