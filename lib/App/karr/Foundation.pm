# ABSTRACT: Single-shot foundation daemon — periodic agent execution across karr boards

package App::karr::Foundation;
use Moo;
use MooX::Options (
  usage_string => 'USAGE: karr-foundation [options]',
);
use Carp qw( croak );
use Path::Tiny;
use YAML::XS ();
use JSON::MaybeXS qw( encode_json decode_json );
use Time::Piece;
use POSIX qw( WNOHANG );
use Digest::MD5 qw( md5_hex );
use Try::Tiny;
use App::karr::Git;
use App::karr::BoardStore;

option config => (
  is     => 'ro',
  format => 's',
  doc    => 'Path to config file (default: ~/.config/karr-foundation/config.yml)',
);

option force => (
  is  => 'ro',
  doc => 'Run agent even if no board change detected and no open tasks',
);

option dry_run => (
  is  => 'ro',
  doc => 'Print what would run without executing',
);

option verbose => (
  is  => 'ro',
  doc => 'Extra output',
);

has _config_data => (
  is      => 'lazy',
  builder => '_build_config_data',
);

sub _build_config_data {
  my ( $self ) = @_;
  my $cfg_path = defined $self->config
    ? path( $self->config )
    : path( $ENV{HOME} )->child( '.config', 'karr-foundation', 'config.yml' );

  unless ( $cfg_path->exists ) {
    warn "karr-foundation: config not found at $cfg_path — nothing to do\n";
    return {};
  }

  my $data = try {
    YAML::XS::LoadFile("$cfg_path");
  } catch {
    croak "Cannot parse config $cfg_path: $_";
  };
  croak "Config must be a YAML mapping" unless ref $data eq 'HASH';
  return $data;
}

=synopsis

    # Typical cron entry — run every 5 minutes
    */5 * * * * /path/to/karr-foundation

    # Force a run regardless of board state
    karr-foundation --force

    # Preview what would run
    karr-foundation --dry-run --verbose

=description

F<karr-foundation> is a single-shot, idempotent CLI meant to be invoked
periodically (cron, systemd-timer, while-loop). It scans configured karr
boards, detects changes or open work, and optionally invokes a configured agent
command.

B<Config file:> C<~/.config/karr-foundation/config.yml> (or C<--config>).

  dirs:
    - /path/to/repo1
    - /path/to/repo2

  scan:
    - /path/to/parent-dir   # finds all direct subdirs that have a .karr file

B<Per-repo .karr file:>

  command: claude -p "Use karr-coordinator agent, pick next task"
  on_idle: skip             # 'skip' (default) | 'always-run'
  max_runtime: 1800         # seconds before hard SIGKILL (default: 1800)

All state files are gitignored: C<.karr.state>, C<.karr.lock>, C<.karr.log>.

=cut

# ---------------------------------------------------------------------------
# Public
# ---------------------------------------------------------------------------

sub run {
  my ( $self ) = @_;
  my @repos = $self->_discover_repos;
  unless ( @repos ) {
    warn "karr-foundation: no repos found — check config\n";
    return 1;
  }
  for my $repo ( @repos ) {
    try {
      $self->_process_repo( $repo );
    } catch {
      warn "karr-foundation: error in $repo: $_\n";
    };
  }
  return 0;
}

# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------

sub _discover_repos {
  my ( $self ) = @_;
  my @repos;

  # Explicit repo roots
  for my $dir ( @{ $self->_config_data->{dirs} // [] } ) {
    my $p = path( $dir );
    if ( $p->is_dir ) {
      push @repos, $p;
    } else {
      warn "karr-foundation: dir not found: $dir\n";
    }
  }

  # Scanned parent directories — check direct children for .karr file
  for my $scan_dir ( @{ $self->_config_data->{scan} // [] } ) {
    my $p = path( $scan_dir );
    unless ( $p->is_dir ) {
      warn "karr-foundation: scan dir not found: $scan_dir\n";
      next;
    }
    for my $child ( $p->children ) {
      push @repos, $child
        if $child->is_dir && $child->child('.karr')->exists;
    }
  }

  return @repos;
}

# ---------------------------------------------------------------------------
# Per-repo processing
# ---------------------------------------------------------------------------

sub _process_repo {
  my ( $self, $repo ) = @_;
  my $dot_karr = $repo->child('.karr');
  unless ( $dot_karr->exists ) {
    $self->_say_verbose("skip $repo — no .karr file");
    return;
  }

  my $karr = $self->_load_karr( $repo );
  unless ( defined $karr->{command} ) {
    warn "karr-foundation: $repo/.karr has no 'command' key — skipping\n";
    return;
  }

  # Check lock — skip if another instance is running
  if ( $self->_lock_held( $repo ) ) {
    $self->_say_verbose("skip $repo — locked by running agent");
    return;
  }

  # Pull latest refs
  $self->_sync_pull( $repo );

  # Decide whether to run
  my $should_run = $self->force;
  unless ( $should_run ) {
    my $prev_hash   = $self->_state_get( $repo, 'hash' ) // '';
    my $curr_hash   = $self->_ref_hash( $repo ) // '';
    my $has_tasks   = $self->_has_open_tasks( $repo );
    my $on_idle     = $karr->{on_idle} // 'skip';
    $should_run = ( $curr_hash ne $prev_hash )
               || $has_tasks
               || ( $on_idle eq 'always-run' );
  }

  unless ( $should_run ) {
    $self->_say_verbose("skip $repo — no board change and no open tasks");
    return;
  }

  # Acquire lock, run, release
  $self->_acquire_lock( $repo );
  my $exit_code = try {
    $self->_run_command( $repo, $karr );
  } catch {
    warn "karr-foundation: command error in $repo: $_\n";
    1;
  };
  $self->_release_lock( $repo );

  # Update state
  $self->_state_set( $repo,
    hash      => $self->_ref_hash( $repo ) // '',
    last_run  => localtime->datetime,
    last_exit => $exit_code // 0,
  );
}

# ---------------------------------------------------------------------------
# Sync
# ---------------------------------------------------------------------------

sub _sync_pull {
  my ( $self, $repo ) = @_;
  $self->_say_verbose("sync --pull $repo");
  return if $self->dry_run;
  my $git = App::karr::Git->new( dir => "$repo" );
  return unless $git->is_repo;
  $git->pull;
}

# ---------------------------------------------------------------------------
# Ref hash (detect board changes)
# ---------------------------------------------------------------------------

sub _ref_hash {
  my ( $self, $repo ) = @_;
  my $git = App::karr::Git->new( dir => "$repo" );
  return undef unless $git->is_repo;
  my $oids = $git->ref_oids('refs/karr/') or return undef;
  # Deterministic fingerprint of refs/karr/* (ref name + target OID).
  my $out = join '', map { "$_ $oids->{$_}\n" } sort keys %$oids;
  return md5_hex( $out );
}

# ---------------------------------------------------------------------------
# Open tasks check
# ---------------------------------------------------------------------------

sub _has_open_tasks {
  my ( $self, $repo ) = @_;
  my $git = App::karr::Git->new( dir => "$repo" );
  return 0 unless $git->is_repo;
  my $store = App::karr::BoardStore->new( git => $git );
  my %open = map { $_ => 1 } qw( todo in-progress );
  for my $task ( $store->load_tasks ) {
    next unless $task;
    return 1 if $open{ $task->status // '' };
  }
  return 0;
}

# ---------------------------------------------------------------------------
# Command execution
# ---------------------------------------------------------------------------

sub _run_command {
  my ( $self, $repo, $karr ) = @_;
  my $command     = $karr->{command};
  my $max_runtime = $karr->{max_runtime} // 1800;

  # Env-var substitution in command string
  $command =~ s/\$\{(\w+)\}/$ENV{$1} \/\/ ''/ge;
  $command =~ s/\$(\w+)/$ENV{$1} \/\/ ''/ge;

  $self->_append_log( $repo, "START command=$command" );
  $self->_say_verbose("exec in $repo: $command");

  if ( $self->dry_run ) {
    $self->_append_log( $repo, "DRY-RUN (skipped)" );
    return 0;
  }

  my $log_file = $repo->child('.karr.log');
  local $ENV{KARR_REPO} = "$repo";

  my $pid = fork;
  croak "fork failed: $!" unless defined $pid;

  if ( $pid == 0 ) {
    # child
    chdir "$repo" or die "chdir $repo: $!";
    open( STDOUT, '>>', "$log_file" ) or die "open log: $!";
    open( STDERR, '>&STDOUT' )       or die "dup stderr: $!";
    exec( '/bin/sh', '-c', $command ) or die "exec: $!";
  }

  # parent — wait with hard timeout
  my $started   = time;
  my $exit_code = 0;
  eval {
    local $SIG{ALRM} = sub { die "timeout\n" };
    alarm( $max_runtime );
    waitpid( $pid, 0 );
    alarm( 0 );
    $exit_code = $? >> 8;
  };
  if ( $@ ) {
    if ( $@ eq "timeout\n" ) {
      my $elapsed = time - $started;
      $self->_append_log( $repo, "TIMEOUT after ${elapsed}s — sending SIGTERM to $pid" );
      kill 'TERM', $pid;
      sleep 2;
      kill 'KILL', $pid;
      waitpid( $pid, WNOHANG );
      $exit_code = -1;
    } else {
      die $@;
    }
  }

  my $elapsed = time - $started;
  $self->_append_log( $repo, "END elapsed=${elapsed}s exit=$exit_code" );
  return $exit_code;
}

# ---------------------------------------------------------------------------
# Lock file
# ---------------------------------------------------------------------------

sub _lock_file { path( $_[1]->child('.karr.lock') ) }

sub _lock_held {
  my ( $self, $repo ) = @_;
  my $lock = $self->_lock_file( $repo );
  return 0 unless $lock->exists;
  my $pid = $lock->slurp_utf8;
  chomp $pid;
  return 0 unless $pid =~ /^\d+$/;
  # Check if PID is alive
  return kill( 0, $pid ) ? 1 : 0;
}

sub _acquire_lock {
  my ( $self, $repo ) = @_;
  return if $self->dry_run;
  $self->_lock_file( $repo )->spew_utf8( "$$\n" );
}

sub _release_lock {
  my ( $self, $repo ) = @_;
  return if $self->dry_run;
  my $lock = $self->_lock_file( $repo );
  $lock->remove if $lock->exists;
}

# ---------------------------------------------------------------------------
# State file
# ---------------------------------------------------------------------------

sub _state_file { path( $_[1]->child('.karr.state') ) }

sub _state_get {
  my ( $self, $repo, $key ) = @_;
  my $state_file = $self->_state_file( $repo );
  return undef unless $state_file->exists;
  my $data = try { decode_json( $state_file->slurp_utf8 ) } catch { {} };
  return $data->{$key};
}

sub _state_set {
  my ( $self, $repo, %kv ) = @_;
  return if $self->dry_run;
  my $state_file = $self->_state_file( $repo );
  my $data = {};
  if ( $state_file->exists ) {
    $data = try { decode_json( $state_file->slurp_utf8 ) } catch { {} };
  }
  $data->{$_} = $kv{$_} for keys %kv;
  $state_file->spew_utf8( encode_json( $data ) );
}

# ---------------------------------------------------------------------------
# Log file
# ---------------------------------------------------------------------------

sub _append_log {
  my ( $self, $repo, $msg ) = @_;
  my $ts  = localtime->strftime('%Y-%m-%dT%H:%M:%S');
  my $line = "[$ts] $$: $msg\n";
  print $line if $self->verbose;
  return if $self->dry_run;
  $repo->child('.karr.log')->append_utf8( $line );
}

sub _say_verbose {
  my ( $self, $msg ) = @_;
  print "$msg\n" if $self->verbose;
}

# ---------------------------------------------------------------------------
# .karr file
# ---------------------------------------------------------------------------

sub _load_karr {
  my ( $self, $repo ) = @_;
  my $karr_file = $repo->child('.karr');
  return {} unless $karr_file->exists;
  my $data = try {
    YAML::XS::LoadFile("$karr_file");
  } catch {
    warn "karr-foundation: cannot parse $karr_file: $_\n";
    {};
  };
  return ref $data eq 'HASH' ? $data : {};
}

1;
