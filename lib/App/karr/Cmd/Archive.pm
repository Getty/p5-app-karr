# ABSTRACT: Archive a task (soft-delete)

package App::karr::Cmd::Archive;
our $VERSION = '0.004';
use Moo;
use MooX::Cmd;
use MooX::Options (
  usage_string => 'USAGE: karr archive ID[,ID,...] [--json]',
);
use App::karr::Role::BoardAccess;
use App::karr::Role::Output;
use App::karr::Task;

with 'App::karr::Role::BoardAccess', 'App::karr::Role::Output';

sub execute {
  my ($self, $args_ref, $chain_ref) = @_;

  $self->sync_before;

  my $id_str = $args_ref->[0] or die "Usage: karr archive ID[,ID,...]\n";

  my @ids = $self->parse_ids($id_str);
  my @results;

  for my $id (@ids) {
    my $task = $self->find_task($id);
    unless ($task) {
      push @results, { id => $id + 0, error => "not found" };
      warn "Task $id not found\n" unless $self->json;
      next;
    }

    if ($task->status eq 'archived') {
      push @results, {
        id     => $task->id,
        title  => $task->title,
        status => 'archived',
        note   => 'already archived',
      };
      printf "Task %d is already archived: %s\n", $task->id, $task->title
        unless $self->json;
      next;
    }

    my $old_status = $task->status;
    $task->status('archived');
    $task->save;

    push @results, {
      id          => $task->id,
      title       => $task->title,
      status      => 'archived',
      old_status  => $old_status,
    };
    printf "Archived task %d: %s\n", $task->id, $task->title
      unless $self->json;
  }

  $self->sync_after;

  if ($self->json) {
    $self->print_json(@results == 1 ? $results[0] : \@results);
  }
}

1;
