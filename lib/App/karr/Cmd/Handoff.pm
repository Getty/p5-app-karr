# ABSTRACT: Hand off a task for review

package App::karr::Cmd::Handoff;

use Moo;
use MooX::Cmd;
use MooX::Options (
  usage_string => 'USAGE: karr handoff ID --claim NAME [--note TEXT] [--block REASON] [--release]',
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
  doc => 'Agent name claiming the task',
);

option note => (
  is => 'ro',
  format => 's',
  doc => 'Handoff note to append to body',
);

option timestamp => (
  is => 'ro',
  short => 't',
  doc => 'Prefix timestamp to note',
);

option block => (
  is => 'ro',
  format => 's',
  doc => 'Block task with reason',
);

option release => (
  is => 'ro',
  doc => 'Release claim after handoff',
);

sub _sync_after {
  my ($self) = @_;
  require App::karr::Git;
  my $git = App::karr::Git->new( dir => $self->board_dir->stringify );
  return unless $git->is_repo;
  $git->pull;
  $git->push;
}

sub execute {
  my ($self, $args_ref, $chain_ref) = @_;

  # Auto-sync before
  $self->_sync_after if -d '.git';

  my $id = $args_ref->[0] or die "Usage: karr handoff ID --claim NAME [--note TEXT] [--block REASON] [--release]\n";

  my $config = App::karr::Config->new(
    file => $self->board_dir->child('config.yml'),
  );

  my $task = $self->find_task($id);
  die "Task $id not found\n" unless $task;

  # Validate claim ownership
  if ($task->has_claimed_by && $task->claimed_by ne $self->claim) {
    my $timeout = $self->_parse_timeout($config->claim_timeout);
    unless ($self->_claim_expired($task, $timeout)) {
      die sprintf "Task %d is claimed by %s\n", $task->id, $task->claimed_by;
    }
  }

  # Move to review
  my $old_status = $task->status;
  if ($task->status ne 'review') {
    $task->status('review');
  }

  # Refresh claim
  $task->claimed_by($self->claim);
  $task->claimed_at(gmtime->datetime . 'Z');

  # Block if requested
  if ($self->block) {
    $task->blocked($self->block);
  }

  # Append note
  if ($self->note) {
    my $note_text = $self->note;
    if ($self->timestamp) {
      $note_text = gmtime->strftime('%Y-%m-%d %H:%M') . ' ' . $note_text;
    }
    $task->body(($task->body ? $task->body . "\n" : '') . $note_text);
  }

  # Release claim if requested
  if ($self->release) {
    $task->claimed_by(undef);
    $task->claimed_at(undef);
  }

  $task->save;

  if ($self->json) {
    my $data = $task->to_frontmatter;
    $data->{body} = $task->body if $task->body;
    $self->print_json($data);
    return;
  }

  my $msg = sprintf "Handed off task %d -> review", $task->id;
  $msg .= sprintf " (blocked: %s)", $self->block if $self->block;
  $msg .= " (claim released)" if $self->release;
  print "$msg\n";
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
