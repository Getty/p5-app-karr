# ABSTRACT: Create a new task

package App::karr::Cmd::Create;

use Moo;
use MooX::Cmd;
use MooX::Options (
  usage_string => 'USAGE: karr create --title TEXT [--priority LEVEL] [--status STATUS] [options]',
);
use App::karr::Role::BoardAccess;
use App::karr::Task;
use App::karr::Config;

with 'App::karr::Role::BoardAccess';

option title => (
  is => 'ro',
  format => 's',
  doc => 'Task title',
);

option status => (
  is => 'ro',
  format => 's',
  doc => 'Initial status',
);

option priority => (
  is => 'ro',
  format => 's',
  doc => 'Priority level',
);

option assignee => (
  is => 'ro',
  format => 's',
  doc => 'Person assigned',
);

option tags => (
  is => 'ro',
  format => 's',
  doc => 'Comma-separated tags',
);

option due => (
  is => 'ro',
  format => 's',
  doc => 'Due date (YYYY-MM-DD)',
);

option estimate => (
  is => 'ro',
  format => 's',
  doc => 'Time estimate',
);

option class => (
  is => 'ro',
  format => 's',
  doc => 'Class of service',
);

option body => (
  is => 'ro',
  format => 's',
  doc => 'Task description',
);

sub execute {
  my ($self, $args_ref, $chain_ref) = @_;
  my $title = $self->title // $args_ref->[0]
    or die "Title is required. Use --title or pass as argument.\n";

  my $config = App::karr::Config->new(
    file => $self->board_dir->child('config.yml'),
  );
  my $defaults = $config->data->{defaults} // {};

  my %task_args = (
    id       => $config->next_id,
    title    => $title,
    status   => $self->status   // $defaults->{status}   // 'backlog',
    priority => $self->priority // $defaults->{priority}  // 'medium',
    class    => $self->class    // $defaults->{class}     // 'standard',
  );

  $task_args{assignee} = $self->assignee if $self->assignee;
  $task_args{tags}     = [split /,/, $self->tags] if $self->tags;
  $task_args{due}      = $self->due if $self->due;
  $task_args{estimate} = $self->estimate if $self->estimate;
  $task_args{body}     = $self->body if $self->body;

  my $task = App::karr::Task->new(%task_args);
  my $file = $task->save($self->tasks_dir);

  printf "Created task %d: %s (%s)\n", $task->id, $task->title, $file->basename;
}

1;
