# ABSTRACT: Lock management via Git refs

package App::karr::Lock;

use strict;
use warnings;
use App::karr::Git;

sub new {
    my ( $class, %args ) = @_;
    return bless {
        git     => App::karr::Git->new( dir => $args{dir} // '.' ),
        task_id => $args{task_id},
    }, $class;
}

sub task_id { shift->{task_id} }
sub git     { shift->{git} }

sub ref_name {
    my ( $self, $task_id ) = @_;
    $task_id //= $self->task_id;
    return "refs/karr/tasks/$task_id/lock";
}

sub get {
    my ( $self, $task_id ) = @_;
    my $ref = $self->ref_name($task_id);
    my $content = $self->git->read_ref($ref);
    return $content;
}

sub acquire {
    my ( $self, $task_id, $email ) = @_;
    $task_id //= $self->task_id;
    my $ref = $self->ref_name($task_id);

    # Check if already locked
    my $current = $self->get($task_id);
    if ( $current && $current ne $email ) {
        return ( 0, "locked by $current" );
    }

    # Acquire lock
    $self->git->write_ref( $ref, $email );
    return ( 1, "acquired" );
}

sub release {
    my ( $self, $task_id, $email ) = @_;
    $task_id //= $self->task_id;
    my $ref = $self->ref_name($task_id);

    # Check ownership
    my $current = $self->get($task_id);
    if ( $current && $current ne $email ) {
        return ( 0, "locked by $current" );
    }

    $self->git->delete_ref($ref);
    return ( 1, "released" );
}

1;
