# ABSTRACT: Role providing board directory discovery and config access

package App::karr::Role::BoardAccess;

use Moo::Role;
use Path::Tiny;
use YAML::XS qw( LoadFile DumpFile );
use Carp qw( croak );

has board_dir => (
  is => 'lazy',
);

has config => (
  is => 'lazy',
);

sub _build_board_dir {
  my ($self) = @_;
  if ($self->can('has_dir') && $self->has_dir) {
    return path($self->dir);
  }
  my $dir = path('.')->absolute;
  while (1) {
    my $candidate = $dir->child('karr');
    return $candidate if $candidate->is_dir && $candidate->child('config.yml')->exists;
    last if $dir->is_rootdir;
    $dir = $dir->parent;
  }
  croak "No karr board found. Run 'karr init' to create one.";
}

sub _build_config {
  my ($self) = @_;
  my $config_file = $self->board_dir->child('config.yml');
  croak "No config.yml found in " . $self->board_dir unless $config_file->exists;
  return LoadFile($config_file->stringify);
}

sub save_config {
  my ($self) = @_;
  DumpFile($self->board_dir->child('config.yml')->stringify, $self->config);
}

sub tasks_dir {
  my ($self) = @_;
  my $name = $self->config->{tasks_dir} // 'tasks';
  return $self->board_dir->child($name);
}

sub find_task {
  my ($self, $id) = @_;
  my $dir = $self->tasks_dir;
  return undef unless $dir->exists;
  require App::karr::Task;
  for my $file ($dir->children(qr/\.md$/)) {
    if ($file->basename =~ /^0*${id}-/) {
      return App::karr::Task->from_file($file);
    }
  }
  return undef;
}

sub load_tasks {
  my ($self) = @_;
  my $dir = $self->tasks_dir;
  return () unless $dir->exists;
  require App::karr::Task;
  my @files = sort $dir->children(qr/\.md$/);
  return map { App::karr::Task->from_file($_) } @files;
}

sub parse_ids {
  my ($self, $id_str) = @_;
  return split /,/, $id_str;
}

1;
