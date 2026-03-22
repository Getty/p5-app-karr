# ABSTRACT: List tasks with filtering and sorting

package App::karr::Cmd::List;
our $VERSION = '0.004';
use Moo;
use MooX::Cmd;
use MooX::Options (
  usage_string => 'USAGE: karr list [--status LIST] [--priority LIST] [--sort FIELD] [options]',
);
use App::karr::Role::BoardAccess;
use App::karr::Role::Output;
use App::karr::Task;

with 'App::karr::Role::BoardAccess', 'App::karr::Role::Output';

=head1 SYNOPSIS

    karr list
    karr list --status todo,in-progress --priority high,critical
    karr list --claimed-by agent-fox --compact
    karr list -s docker --json

=head1 DESCRIPTION

Lists tasks from the current board with optional filtering and sorting.
Archived tasks are excluded by default so the output focuses on active work.
Use C<--compact> for terse one-line output and C<--json> for machine-readable
automation.

=head1 FILTERS AND SORTING

=over 4

=item * C<--status>, C<--priority>

Accept comma-separated lists and only return tasks matching one of the
requested values.

=item * C<--assignee>, C<--tag>, C<--claimed-by>

Limit the result set to a specific assignee, tag, or claim owner.

=item * C<-s>, C<--search>

Performs a case-insensitive substring search across title, body, and tags.

=item * C<--sort>, C<--reverse>

Sort by C<id>, C<status>, C<priority>, C<created>, C<updated>, or C<due>, and
optionally reverse the result order.

=back

=cut

option status => (
  is => 'ro',
  format => 's',
  doc => 'Filter by status (comma-separated)',
);

option priority => (
  is => 'ro',
  format => 's',
  doc => 'Filter by priority (comma-separated)',
);

option assignee => (
  is => 'ro',
  format => 's',
  doc => 'Filter by assignee',
);

option tag => (
  is => 'ro',
  format => 's',
  doc => 'Filter by tag',
);

option search => (
  is => 'ro',
  format => 's',
  short => 's',
  doc => 'Search tasks by title, body, or tags',
);

option claimed_by => (
  is => 'ro',
  format => 's',
  doc => 'Filter by claim owner',
);

option sort => (
  is => 'ro',
  format => 's',
  default => sub { 'id' },
  doc => 'Sort by: id, status, priority, created, updated, due',
);

option reverse => (
  is => 'ro',
  short => 'r',
  doc => 'Reverse sort order',
);

sub execute {
  my ($self, $args_ref, $chain_ref) = @_;
  my @tasks = $self->_load_tasks;
  @tasks = $self->_filter(\@tasks);
  @tasks = $self->_sort(\@tasks);

  if ($self->json) {
    $self->print_json([map { $_->to_frontmatter } @tasks]);
    return;
  }

  if ($self->compact) {
    for my $t (@tasks) {
      printf "%3d  %-12s %-8s %s\n", $t->id, $t->status, $t->priority, $t->title;
    }
    return;
  }

  # Table output
  printf "%-4s %-12s %-8s %-10s %s\n", 'ID', 'Status', 'Priority', 'Assignee', 'Title';
  printf "%s\n", '-' x 70;
  for my $t (@tasks) {
    printf "%-4d %-12s %-8s %-10s %s\n",
      $t->id, $t->status, $t->priority,
      ($t->has_assignee ? $t->assignee : '-'),
      $t->title;
  }
  printf "\n%d task(s)\n", scalar @tasks;
}

sub _load_tasks {
  my ($self) = @_;
  my $dir = $self->tasks_dir;
  return () unless $dir->exists;
  my @files = sort $dir->children(qr/\.md$/);
  return map { App::karr::Task->from_file($_) } @files;
}

sub _filter {
  my ($self, $tasks) = @_;
  my @filtered = @$tasks;

  # Exclude archived by default
  @filtered = grep { $_->status ne 'archived' } @filtered;

  if ($self->status) {
    my %statuses = map { $_ => 1 } split /,/, $self->status;
    @filtered = grep { $statuses{$_->status} } @filtered;
  }
  if ($self->priority) {
    my %priorities = map { $_ => 1 } split /,/, $self->priority;
    @filtered = grep { $priorities{$_->priority} } @filtered;
  }
  if ($self->assignee) {
    @filtered = grep { $_->has_assignee && $_->assignee eq $self->assignee } @filtered;
  }
  if ($self->tag) {
    @filtered = grep {
      my $t = $_;
      grep { $_ eq $self->tag } @{$t->tags};
    } @filtered;
  }
  if ($self->claimed_by) {
    @filtered = grep { $_->has_claimed_by && $_->claimed_by eq $self->claimed_by } @filtered;
  }
  if ($self->search) {
    my $q = lc($self->search);
    @filtered = grep {
      index(lc($_->title), $q) >= 0
      || index(lc($_->body), $q) >= 0
      || grep { index(lc($_), $q) >= 0 } @{$_->tags}
    } @filtered;
  }
  return @filtered;
}

sub _sort {
  my ($self, $tasks) = @_;
  my $field = $self->sort;
  my @sorted;
  if ($field eq 'id') {
    @sorted = sort { $a->id <=> $b->id } @$tasks;
  } elsif ($field eq 'priority') {
    my %pri = (low => 0, medium => 1, high => 2, critical => 3);
    @sorted = sort { ($pri{$a->priority} // 0) <=> ($pri{$b->priority} // 0) } @$tasks;
  } else {
    @sorted = sort { ($a->$field // '') cmp ($b->$field // '') } @$tasks;
  }
  @sorted = reverse @sorted if $self->reverse;
  return @sorted;
}

1;
