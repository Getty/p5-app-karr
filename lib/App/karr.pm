# ABSTRACT: Kanban Assignment & Responsibility Registry

package App::karr;
our $VERSION = '0.004';
use Moo;
use MooX::Cmd;
use MooX::Options;
use Term::ANSIColor qw( colored );
use App::karr::Role::BoardAccess;

with 'App::karr::Role::BoardAccess';

=head1 SYNOPSIS

    karr init --name "My Project"
    karr create "Fix login bug" --priority high
    karr list --status todo,in-progress
    karr board
    karr set-refs superpowers/spec/1234.md draft ready
    karr get-refs superpowers/spec/1234.md

=head1 DESCRIPTION

L<App::karr> is the main entry point for the C<karr> command line tool. It
manages a file-based kanban board stored in F<karr/>, where each task is a
Markdown file with YAML frontmatter and the board configuration lives in
F<karr/config.yml>.

The CLI is designed for local use and for multi-agent workflows backed by Git
refs. Commands that mutate board state synchronize through C<refs/karr/*> when
the board is inside a Git repository, so multiple machines or agents can see
the same task state without merging task files by hand.

Perl remains the primary local installation path, but Docker is a first-class
runtime option when you want to vendor the client into other environments. The
README covers the Docker flow in detail, including the shell alias pattern.

Besides the board itself, C<karr> can also store helper payloads in arbitrary
non-protected refs such as C<refs/superpowers/spec/...>. This is aimed at
AI-assisted and agent-style workflows where lightweight shared state is useful
without changing the task model.

=head1 COMMAND OVERVIEW

=over 4

=item * C<init>, C<config>, C<context>, C<skill>

Board bootstrap, configuration, context generation, and shipped skill
installation.

=item * C<create>, C<list>, C<show>, C<edit>, C<move>, C<delete>, C<archive>

Day-to-day task lifecycle management.

=item * C<board>, C<pick>, C<handoff>, C<log>, C<sync>, C<agentname>

Board visualisation, multi-agent coordination, activity inspection, Git sync,
and helper utilities.

=item * C<set-refs>, C<get-refs>

Store and retrieve helper payloads in free-form Git refs outside the protected
board namespace.

=back

=head1 BOARD DISCOVERY

Most commands automatically search upward from the current directory for a
F<karr/config.yml> file. The global C<--dir> option overrides that discovery
and points the CLI at a specific board directory.

=head1 DEFAULT BEHAVIOUR

Running C<karr> without a subcommand shows the board summary, which makes the
tool convenient as a quick project status command.

=cut

option dir => (
  is => 'ro',
  format => 's',
  doc => 'Path to karr board directory (overrides auto-detection)',
  predicate => 1,
);

my @COMMANDS = (
  [ init      => 'Initialize a new karr board' ],
  [ create    => 'Create a new task' ],
  [ list      => 'List and filter tasks' ],
  [ show      => 'Show full task details' ],
  [ board     => 'Show board summary' ],
  [ move      => 'Change task status' ],
  [ edit      => 'Modify task fields' ],
  [ delete    => 'Delete a task' ],
  [ pick      => 'Claim the next available task' ],
  [ archive   => 'Archive a task (soft-delete)' ],
  [ handoff   => 'Hand off a task for review' ],
  [ config    => 'View or modify board config' ],
  [ context   => 'Generate board context summary' ],
  [ sync      => 'Sync board with remote' ],
  [ agentname => 'Generate a random agent name' ],
  [ skill     => 'Install/update agent skills' ],
  [ 'set-refs' => 'Store helper payloads in a Git ref' ],
  [ 'get-refs' => 'Fetch and print helper payloads from a Git ref' ],
);

sub _print_help {
  my ($self_or_class, $code) = @_;
  $code //= 0;

  my $out = '';
  $out .= colored("karr", 'bold') . " - Kanban Assignment & Responsibility Registry\n\n";
  $out .= colored("USAGE:", 'bold') . " karr [--dir PATH] <command> [options]\n\n";
  $out .= colored("COMMANDS:", 'bold') . "\n";

  my $max = 0;
  for (@COMMANDS) { $max = length($_->[0]) if length($_->[0]) > $max }

  for my $cmd (@COMMANDS) {
    $out .= sprintf "  %-*s  %s\n", $max, colored($cmd->[0], 'cyan'), $cmd->[1];
  }

  $out .= "\n" . colored("OPTIONS:", 'bold') . "\n";
  $out .= "  --dir PATH   Board directory (default: auto-detect karr/)\n";
  $out .= "  --json       JSON output (most commands)\n";
  $out .= "  --compact    Compact output (list, board)\n";
  $out .= "\n" . colored("EXAMPLES:", 'bold') . "\n";
  $out .= "  karr init --name \"My Project\"\n";
  $out .= "  karr create --title \"Fix login bug\" --priority high\n";
  $out .= "  karr list --status todo,in-progress\n";
  $out .= "  karr move 1 in-progress --claim agent-fox\n";
  $out .= "  karr pick --claim agent-fox --move in-progress\n";
  $out .= "  karr set-refs superpowers/spec/1234.md draft ready\n";
  $out .= "  karr board\n";
  $out .= "\nRun " . colored("karr <command> --help", 'bold') . " for command-specific options.\n";

  if ($code > 0) { warn $out } else { print $out }
  exit $code if $code >= 0;
}

around options_usage      => sub { $_[1]->_print_help($_[2]) };
around options_help       => sub { $_[1]->_print_help($_[2]) };
around options_short_usage => sub { $_[1]->_print_help($_[2]) };

sub execute {
  my ($self, $args_ref, $chain_ref) = @_;
  # Default action: show board summary
  eval {
    require App::karr::Cmd::Board;
    App::karr::Cmd::Board->new(
      board_dir => $self->board_dir,
    )->execute($args_ref, $chain_ref);
  };
  if ($@) {
    if ($@ =~ /No karr board found/) {
      die "No karr board found. Run 'karr init' to create one.\n";
    }
    die $@;
  }
}

1;
