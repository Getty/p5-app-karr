# ABSTRACT: Show full details of a task

package App::karr::Cmd::Show;
our $VERSION = '0.004';
use Moo;
use MooX::Cmd;
use MooX::Options (
  usage_string => 'USAGE: karr show ID [--json]',
);
use App::karr::Role::BoardAccess;
use App::karr::Role::Output;
use App::karr::Task;

with 'App::karr::Role::BoardAccess', 'App::karr::Role::Output';

sub execute {
  my ($self, $args_ref, $chain_ref) = @_;
  my $id = $args_ref->[0] or die "Usage: karr show ID\n";

  my $task = $self->find_task($id);
  die "Task $id not found\n" unless $task;

  if ($self->json) {
    my $data = $task->to_frontmatter;
    $data->{body} = $task->body if $task->body;
    $self->print_json($data);
    return;
  }

  printf "Task #%d: %s\n", $task->id, $task->title;
  printf "Status:   %s\n", $task->status;
  printf "Priority: %s\n", $task->priority;
  printf "Class:    %s\n", $task->class;
  printf "Assignee: %s\n", $task->assignee if $task->has_assignee;
  printf "Tags:     %s\n", join(', ', @{$task->tags}) if @{$task->tags};
  printf "Due:      %s\n", $task->due if $task->has_due;
  printf "Estimate: %s\n", $task->estimate if $task->has_estimate;
  printf "Claimed:  %s\n", $task->claimed_by if $task->has_claimed_by;
  printf "Blocked:  %s\n", $task->blocked if $task->has_blocked;
  printf "Created:  %s\n", $task->created;
  printf "Updated:  %s\n", $task->updated;
  if ($task->body) {
    print "\n" . $task->body . "\n";
  }
}

1;
