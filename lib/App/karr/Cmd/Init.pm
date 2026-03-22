# ABSTRACT: Initialize a new karr board

package App::karr::Cmd::Init;
our $VERSION = '0.004';
use Moo;
use MooX::Cmd;
use MooX::Options (
  usage_string => 'USAGE: karr init [--name TEXT] [--statuses LIST] [--claude-skill]',
);
use Path::Tiny;
use YAML::XS qw( DumpFile );
use App::karr::Config;

=head1 SYNOPSIS

    karr init --name "My Project"
    karr init --statuses backlog,todo,in-progress,review,done
    karr init --name "Client Work" --claude-skill

=head1 DESCRIPTION

Creates a new F<karr/> board in the current working directory. The command
generates F<karr/config.yml>, creates the task directory, and can optionally
install the bundled Claude Code skill into the repository.

=head1 OPTIONS

=over 4

=item * C<--name>

Sets the board name stored in C<board.name>.

=item * C<--statuses>

Replaces the default status list with the comma-separated statuses you supply.

=item * C<--claude-skill>

Copies the bundled skill file to F<.claude/skills/karr/SKILL.md>.

=back

=cut

option name => (
  is => 'ro',
  format => 's',
  doc => 'Board name',
);

option statuses => (
  is => 'ro',
  format => 's',
  doc => 'Comma-separated status list',
);

option claude_skill => (
  is => 'ro',
  doc => 'Install Claude Code skill for karr',
);

sub execute {
  my ($self, $args_ref, $chain_ref) = @_;
  my $dir = path('karr');

  if ($dir->child('config.yml')->exists) {
    die "Board already exists in karr/\n";
  }

  $dir->mkpath;
  my $config = App::karr::Config->default_config(
    name => $self->name,
  );

  if ($self->statuses) {
    my @statuses = split /,/, $self->statuses;
    $config->{statuses} = \@statuses;
  }

  $dir->child('tasks')->mkpath;
  DumpFile($dir->child('config.yml')->stringify, $config);

  print "Initialized karr board in karr/\n";

  if ($self->claude_skill) {
    $self->_install_claude_skill;
  }
}

sub _install_claude_skill {
  my ($self) = @_;
  my $skill_dir = path('.claude/skills/karr');
  $skill_dir->mkpath;

  my $skill_content = $self->_find_skill_source;
  $skill_dir->child('SKILL.md')->spew_utf8($skill_content);
  print "Installed Claude Code skill to .claude/skills/karr/SKILL.md\n";
}

sub _find_skill_source {
  my ($self) = @_;

  # Try File::ShareDir (installed dist)
  eval {
    require File::ShareDir;
    my $dir = File::ShareDir::dist_dir('App-karr');
    my $file = path($dir)->child('claude-skill.md');
    return $file->slurp_utf8 if $file->exists;
  };

  # Fallback: relative to module location (development)
  my $module_path = $INC{'App/karr/Cmd/Init.pm'};
  if ($module_path) {
    my $share = path($module_path)->parent(5)->child('share/claude-skill.md');
    return $share->slurp_utf8 if $share->exists;
  }

  die "Could not find claude-skill.md. Is App::karr properly installed?\n";
}

1;
