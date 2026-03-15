# ABSTRACT: Sync karr board with remote

package App::karr::Cmd::Sync;

use strict;
use warnings;
use Moo;
use feature 'say';
use MooX::Options (
    usage_string => 'USAGE: karr sync [--push] [--pull]',
);

option push => ( is => 'ro', default => 0, doc => 'Push refs to remote' );
option pull => ( is => 'ro', default => 0, doc => 'Pull refs from remote' );
option watch => ( is => 'ro', default => 0, doc => 'Watch for changes in background' );

sub execute {
    my ( $self, $args, $data ) = @_;

    require App::karr::Git;
    my $git = App::karr::Git->new( dir => '.' );

    unless ( $git->is_repo ) {
        say "Not a git repository. Skipping sync.";
        return;
    }

    my $email = $git->git_user_email;
    my $name = $git->git_user_name;
    unless ($email ) {
        say q(No git user.email configured. Run: git config --global user.email 'you@example.com');
        return;
    }

    say "User: $name <$email>";

    # Pull first
    if ( $self->pull || !$self->push ) {
        say "Pulling refs/karr/ from remote...";
        $git->pull;
    }

    # Push after
    if ( $self->push ) {
        say "Pushing refs/karr/ to remote...";
        $git->push;
    }

    say "Done.";
}

1;
