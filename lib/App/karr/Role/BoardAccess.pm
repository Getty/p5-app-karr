# ABSTRACT: Role providing board discovery, sync lifecycle, and task access

package App::karr::Role::BoardAccess;
our $VERSION = '0.103';
use Moo::Role;

with 'App::karr::Role::BoardDiscovery';
with 'App::karr::Role::SyncLifecycle';

=head1 DESCRIPTION

This role composes L<Role::BoardDiscovery> and L<Role::SyncLifecycle> and
adds task-access methods that delegate to the store. Commands compose this role
for full board functionality.

All task operations work directly against refs via C<< $self->store->load_tasks() >>
and similar. No temporary directory is created.

=cut

sub load_tasks {
    my ($self) = @_;
    return $self->store->load_tasks;
}

sub find_task {
    my ($self, $id) = @_;
    return $self->store->find_task($id);
}

sub save_task {
    my ($self, $task) = @_;
    return $self->store->save_task($task);
}

sub delete_task {
    my ($self, $id) = @_;
    return $self->store->delete_task($id);
}

sub allocate_next_id {
    my ($self) = @_;
    return $self->store->allocate_next_id;
}

sub parse_ids {
    my ($self, $id_str) = @_;
    return split /,/, $id_str;
}

sub append_log {
    my ($self, $git, %entry) = @_;
    $git //= $self->git;
    require JSON::MaybeXS;
    require POSIX;
    $entry{ts} //= POSIX::strftime('%Y-%m-%dT%H:%M:%SZ', gmtime());
    my $identity = $git->git_user_email || 'unknown';
    $identity =~ s/[^a-zA-Z0-9._-]/_/g;
    my $ref = "refs/karr/log/$identity";
    my $existing = $git->read_ref($ref);
    my $line = JSON::MaybeXS::encode_json(\%entry);
    my $new = $existing ? "$existing\n$line" : $line;
    $git->write_ref($ref, $new);
}

sub save_config {
    my ($self, $effective) = @_;
    $effective //= $self->config;
    return $self->store->save_config($effective);
}

1;