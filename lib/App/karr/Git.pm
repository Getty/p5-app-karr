# ABSTRACT: Git operations for karr sync (native via Git::Native; fetch/push still CLI in Phase 3)

package App::karr::Git;
our $VERSION = '0.206';
use strict;
use warnings;
use Path::Tiny qw( path );
use Try::Tiny;
use YAML::XS qw( Dump Load );
use Git::Native;
use Git::Native::Signature;

=head1 SYNOPSIS

    my $git = App::karr::Git->new(dir => '.');

    $git->pull;
    my @ids = $git->list_task_refs;
    my $task = $git->load_task_ref($ids[0]);

=head1 DESCRIPTION

L<App::karr::Git> provides the low-level Git interface used by C<karr> for
syncing board state through C<refs/karr/*>. Local object/ref operations run
natively via L<Git::Native> (FFI to libgit2 — no fork/exec per op).
Network operations (C<fetch>/C<push>/C<pull>) still call the C<git> binary
until L<Git::Native> grows credential callbacks.

=head1 SEE ALSO

L<karr>, L<App::karr>, L<App::karr::BoardStore>, L<App::karr::Task>,
L<App::karr::Config>, L<Git::Native>

=cut

sub new {
    my ( $class, %args ) = @_;
    return bless {
        dir => $args{dir} // '.',
    }, $class;
}

sub dir {
    my ($self) = @_;
    return path( $self->{dir} );
}

# ----- Native repository handle (lazy) -----

sub _repo {
    my ($self) = @_;
    return $self->{_repo} if $self->{_repo};
    return undef unless $self->is_repo;
    $self->{_repo} = Git::Native->open_ext( $self->dir->stringify );
    return $self->{_repo};
}

sub _signature {
    my ($self) = @_;
    # Reuse one signature per process; falls back if user.name/email unset.
    return $self->{_sig} if $self->{_sig};
    my $repo = $self->_repo or return;
    $self->{_sig} = try { $repo->signature_default }
                    catch {
                      Git::Native::Signature->new(
                        name  => $self->git_user_name  || 'karr',
                        email => $self->git_user_email || 'karr@localhost',
                      );
                    };
    return $self->{_sig};
}

# ----- Legacy CLI shim (still needed for fetch/push/pull/check-ref-format) -----

sub _git_cmd {
    my ($self, @cmd) = @_;
    my $dir = $self->dir->stringify;
    my $pid = open(my $fh, '-|');
    if (!defined $pid) {
        die "fork failed: $!";
    }
    if (!$pid) {
        open(STDERR, '>', '/dev/null');
        chdir $dir or die "chdir $dir: $!";
        exec('git', @cmd) or die "exec git: $!";
    }
    my $output = do { local $/; <$fh> };
    close $fh;
    my $ok = $? == 0;
    chomp $output if defined $output;
    return wantarray ? ($output, $ok) : $output;
}

# ----- Repo discovery -----

sub is_repo {
    my ($self) = @_;
    my $ok = try {
        # open_ext walks up to find a .git; throws on miss.
        Git::Native->open_ext( $self->dir->stringify );
        1;
    } catch { 0 };
    return $ok;
}

sub repo_root {
    my ($self) = @_;
    my $repo = $self->_repo or return undef;
    # workdir is undef for bare repos; in that case fall back to gitdir.
    my $root = $repo->workdir // $repo->gitdir;
    $root =~ s{/+\z}{};
    return path($root);
}

# ----- User identity (read via native config, not via CLI) -----

sub _config_string {
    my ( $self, $key ) = @_;
    my $repo = $self->_repo or return '';
    my $val = try {
        my $cfg;
        require Git::Libgit2::FFI;
        Git::Libgit2::FFI::ffi();
        # Snapshot — git_config_get_string refuses to run on a live config.
        my $rc = Git::Libgit2::FFI::git_repository_config_snapshot( \$cfg, $repo->_handle );
        return '' if $rc < 0;
        my $out;
        my $rc2 = Git::Libgit2::FFI::git_config_get_string( \$out, $cfg, $key );
        Git::Libgit2::FFI::git_config_free($cfg);
        return $rc2 < 0 ? '' : ( $out // '' );
    } catch { '' };
    return $val;
}

sub git_user_email {
    my ($self) = @_;
    return $self->_config_string('user.email');
}

sub git_user_name {
    my ($self) = @_;
    return $self->_config_string('user.name');
}

sub git_user_identity {
    my ($self) = @_;
    my $name = $self->git_user_name;
    my $email = $self->git_user_email;
    return "$name <$email>" if $name && $email;
    return $email || $name || '';
}

# ----- Ref name validation -----

sub normalize_ref_name {
    my ( $self, $ref ) = @_;
    defined $ref or die "Ref name is required\n";
    $ref =~ s{^/+}{};
    return $ref =~ m{^refs/} ? $ref : "refs/$ref";
}

sub validate_helper_ref {
    my ( $self, $ref ) = @_;
    my $full_ref = $self->normalize_ref_name($ref);

    my @blocked = (
        'refs/heads/',
        'refs/tags/',
        'refs/remotes/',
        'refs/bisect/',
        'refs/replace/',
        'refs/karr/',
    );

    for my $prefix (@blocked) {
        die "Ref '$full_ref' is in a protected namespace\n"
            if index( $full_ref, $prefix ) == 0;
    }
    die "Ref '$full_ref' is in a protected namespace\n"
        if $full_ref eq 'refs/stash' || index( $full_ref, 'refs/stash/' ) == 0;

    # Native check: git_reference_name_is_valid.
    require Git::Libgit2::FFI;
    Git::Libgit2::FFI::ffi();
    my $valid = 0;
    my $rc = Git::Libgit2::FFI::git_reference_name_is_valid( \$valid, $full_ref );
    die "Ref '$full_ref' is not a valid git ref name\n"
        if $rc < 0 || !$valid;

    return $full_ref;
}

# ----- Ref CRUD (the hotspot — was 4 fork/exec per write_ref) -----

sub write_ref {
    my ( $self, $ref, $content ) = @_;
    my $repo = $self->_repo or return;

    my $blob_oid = $repo->blob_create_frombuffer($content);
    my $tb       = $repo->tree_builder;
    $tb->insert(name => 'data', oid => $blob_oid, mode => 0100644);
    my $tree_oid = $tb->write;

    my $sig = $self->_signature;
    my $commit_oid = $repo->commit_create(
        tree       => $tree_oid,
        parents    => [],
        message    => 'karr ref update',
        author     => $sig,
        committer  => $sig,
    );

    $repo->reference_create( $ref, $commit_oid, force => 1 );
    return 1;
}

sub read_ref {
    my ( $self, $ref ) = @_;
    my $repo = $self->_repo or return '';
    my $content = try {
        return '' unless $repo->reference_exists($ref);
        my $r      = $repo->reference($ref);
        my $oid    = $r->target;
        return '' unless $oid;
        my $commit = $repo->commit($oid);
        my $tree   = $commit->tree;
        my $entry  = $tree->entry_by_name('data');
        return '' unless $entry;
        return $repo->blob( $entry->{oid} )->content;
    } catch { '' };
    # Match historical CLI behaviour: cat-file's trailing newline was chomped.
    chomp $content if defined $content;
    return $content;
}

sub ref_exists {
    my ( $self, $ref ) = @_;
    my $repo = $self->_repo or return 0;
    return $repo->reference_exists($ref) ? 1 : 0;
}

sub delete_ref {
    my ( $self, $ref ) = @_;
    my $repo = $self->_repo or return 0;
    try { $repo->reference_delete($ref) };
    return 1;
}

# ----- Remote / network ops: still CLI until Phase 4 -----

sub has_remote {
    my ( $self, $remote ) = @_;
    $remote //= 'origin';
    my ( undef, $ok ) = $self->_git_cmd( 'remote', 'get-url', $remote );
    return $ok ? 1 : 0;
}

sub fetch {
    my ( $self, $remote ) = @_;
    $remote //= 'origin';
    my (undef, $ok) = $self->_git_cmd('fetch', $remote);
    return $ok;
}

sub push {
    my ( $self, $remote, $refspec ) = @_;
    $remote //= 'origin';
    return 1 unless $self->has_remote($remote);
    $refspec //= '+refs/karr/*:refs/karr/*';
    my (undef, $ok) = $self->_git_cmd('push', '--prune', $remote, $refspec);
    return $ok;
}

sub pull {
    my ( $self, $remote ) = @_;
    $remote //= 'origin';
    return 1 unless $self->has_remote($remote);
    my (undef, $ok) = $self->_git_cmd('fetch', $remote, 'refs/karr/*:refs/karr/*');
    return $ok;
}

sub push_ref {
    my ( $self, $ref, $remote ) = @_;
    $remote //= 'origin';
    $ref = $self->validate_helper_ref($ref);
    my ( undef, $ok ) = $self->_git_cmd( 'push', $remote, "+$ref:$ref" );
    return $ok;
}

sub pull_ref {
    my ( $self, $ref, $remote ) = @_;
    $remote //= 'origin';
    $ref = $self->validate_helper_ref($ref);
    my ( undef, $ok ) = $self->_git_cmd( 'fetch', $remote, "$ref:$ref" );
    return $ok;
}

# ----- Task / config refs (sit on top of write_ref/read_ref) -----

sub save_task_ref {
  my ($self, $task) = @_;
  my $ref = "refs/karr/tasks/" . $task->id . "/data";
  $self->write_ref($ref, $task->to_markdown);
}

sub load_task_ref {
  my ($self, $id) = @_;
  my $ref = "refs/karr/tasks/$id/data";
  my $content = $self->read_ref($ref);
  return undef unless $content;
  require App::karr::Task;
  return App::karr::Task->from_string($content);
}

sub list_task_refs {
  my ($self) = @_;
  my %ids;
  for my $ref ( $self->list_refs('refs/karr/tasks/') ) {
    $ids{$1} = 1 if $ref =~ m{refs/karr/tasks/(\d+)/};
  }
  return sort { $a <=> $b } keys %ids;
}

sub list_refs {
    my ( $self, $prefix ) = @_;
    $prefix //= 'refs/karr/';
    my $repo = $self->_repo or return ();
    # Glob to scope the iterator server-side.
    my $names = $repo->reference_names( glob => "$prefix*" );
    return @$names;
}

sub read_config_ref {
    my ($self) = @_;
    my $content = $self->read_ref('refs/karr/config');
    return {} unless $content;
    return Load($content);
}

sub write_config_ref {
    my ( $self, $data ) = @_;
    return $self->write_ref( 'refs/karr/config', Dump($data) );
}

sub read_next_id_ref {
    my ($self) = @_;
    my $content = $self->read_ref('refs/karr/meta/next-id');
    return 1 unless length $content;
    $content =~ s/\s+\z//;
    return $content =~ /^\d+$/ ? int($content) : 1;
}

sub write_next_id_ref {
    my ( $self, $next_id ) = @_;
    return $self->write_ref( 'refs/karr/meta/next-id', "$next_id\n" );
}

sub delete_refs {
    my ( $self, $prefix ) = @_;
    for my $ref ( $self->list_refs($prefix) ) {
        $self->delete_ref($ref);
    }
    return 1;
}

1;
