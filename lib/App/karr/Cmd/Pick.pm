# ABSTRACT: Atomically find and claim the next available task

package App::karr::Cmd::Pick;

use Moo;
use MooX::Cmd;
use MooX::Options (
  usage_string => 'USAGE: karr pick --claim NAME [--move STATUS] [--status LIST] [--tags LIST]',
);
use App::karr::Role::BoardAccess;
use App::karr::Role::Output;
use App::karr::Task;
use App::karr::Config;
use Time::Piece;

with 'App::karr::Role::BoardAccess', 'App::karr::Role::Output';

option claim => (
  is => 'ro',
  format => 's',
  required => 1,
  doc => 'Agent name to claim the task for',
);

option status => (
  is => 'ro',
  format => 's',
  doc => 'Source status(es) to pick from (comma-separated)',
);

option move => (
  is => 'ro',
  format => 's',
  doc => 'Move picked task to this status',
);

option tags => (
  is => 'ro',
  format => 's',
  doc => 'Only pick tasks matching at least one tag',
);

sub execute {
  my ($self, $args_ref, $chain_ref) = @_;

  my $config = App::karr::Config->new(
    file => $self->board_dir->child('config.yml'),
  );

  my @tasks = $self->load_tasks;

  # Filter by status
  if ($self->status) {
    my %allowed = map { $_ => 1 } split /,/, $self->status;
    @tasks = grep { $allowed{$_->status} } @tasks;
  } else {
    # Exclude terminal statuses
    @tasks = grep { $_->status ne 'done' && $_->status ne 'archived' } @tasks;
  }

  # Exclude claimed tasks (unless claim expired)
  my $timeout = $self->_parse_timeout($config->claim_timeout);
  @tasks = grep {
    !$_->has_claimed_by || $self->_claim_expired($_, $timeout)
  } @tasks;

  # Exclude blocked
  @tasks = grep { !$_->has_blocked } @tasks;

  # Filter by tags
  if ($self->tags) {
    my %wanted = map { $_ => 1 } split /,/, $self->tags;
    @tasks = grep {
      my $t = $_;
      grep { $wanted{$_} } @{$t->tags};
    } @tasks;
  }

  # Sort by class priority, then by priority
  my %class_order = (expedite => 0, 'fixed-date' => 1, standard => 2, intangible => 3);
  my %pri_order   = (critical => 0, high => 1, medium => 2, low => 3);

  @tasks = sort {
    ($class_order{$a->class} // 2) <=> ($class_order{$b->class} // 2)
    || ($pri_order{$a->priority} // 2) <=> ($pri_order{$b->priority} // 2)
    || $a->id <=> $b->id
  } @tasks;

  unless (@tasks) {
    print "No available tasks to pick.\n";
    return;
  }

  my $task = $tasks[0];
  $task->claimed_by($self->claim);
  $task->claimed_at(gmtime->datetime . 'Z');

  if ($self->move) {
    $task->status($self->move);
    if ($self->move eq 'in-progress' && !$task->has_started) {
      $task->started(gmtime->strftime('%Y-%m-%d'));
    }
  }

  $task->save;

  if ($self->json) {
    my $data = $task->to_frontmatter;
    $data->{body} = $task->body if $task->body;
    $self->print_json($data);
    return;
  }

  printf "Picked task %d: %s (claimed by %s)\n", $task->id, $task->title, $self->claim;
  printf "Status: %s | Priority: %s | Class: %s\n", $task->status, $task->priority, $task->class;
  if ($task->body) {
    print "\n" . $task->body . "\n";
  }
}

sub _parse_timeout {
  my ($self, $timeout_str) = @_;
  return 3600 unless $timeout_str;
  if ($timeout_str =~ /^(\d+)h$/) { return $1 * 3600; }
  if ($timeout_str =~ /^(\d+)m$/) { return $1 * 60; }
  return 3600;
}

sub _claim_expired {
  my ($self, $task, $timeout_secs) = @_;
  return 0 unless $task->has_claimed_at;
  my $claimed = eval { Time::Piece->strptime($task->claimed_at =~ s/Z$//r, '%Y-%m-%dT%H:%M:%S') };
  return 0 unless $claimed;
  return (gmtime() - $claimed) > $timeout_secs;
}

1;
