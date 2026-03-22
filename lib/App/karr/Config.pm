# ABSTRACT: Board configuration management

package App::karr::Config;
our $VERSION = '0.004';
use Moo;
use YAML::XS qw( LoadFile DumpFile );
use Path::Tiny;

=head1 SYNOPSIS

    my $config = App::karr::Config->new(
      file => path('karr/config.yml'),
    );

    my @statuses = $config->statuses;
    my $next_id  = $config->next_id;

=head1 DESCRIPTION

L<App::karr::Config> wraps the board configuration file and centralises access
to derived values such as status names, priority order, WIP limits, and the
next task id. It is used by command modules that need a structured view of
F<karr/config.yml> instead of working with raw YAML hashes.

=cut

has file => ( is => 'ro', required => 1 );
has data => ( is => 'lazy' );

sub _build_data {
  my ($self) = @_;
  return LoadFile($self->file->stringify);
}

sub save {
  my ($self) = @_;
  DumpFile($self->file->stringify, $self->data);
}

sub statuses {
  my ($self) = @_;
  return map {
    ref $_ ? $_->{name} : $_
  } @{ $self->data->{statuses} // [] };
}

sub status_config {
  my ($self, $name) = @_;
  for my $s (@{ $self->data->{statuses} // [] }) {
    if (ref $s) {
      return $s if $s->{name} eq $name;
    } elsif ($s eq $name) {
      return { name => $s };
    }
  }
  return undef;
}

sub priorities {
  my ($self) = @_;
  return @{ $self->data->{priorities} // [qw(low medium high critical)] };
}

sub next_id {
  my ($self) = @_;
  my $id = $self->data->{next_id} // 1;
  $self->data->{next_id} = $id + 1;
  $self->save;
  return $id;
}

sub wip_limit {
  my ($self, $status) = @_;
  return $self->data->{wip_limits}{$status};
}

sub claim_timeout {
  my ($self) = @_;
  return $self->data->{claim_timeout} // '1h';
}

sub default_config {
  my ($class, %args) = @_;
  return {
    version => 1,
    board => {
      name => $args{name} // 'Kanban Board',
    },
    tasks_dir => 'tasks',
    statuses => [
      'backlog',
      'todo',
      { name => 'in-progress', require_claim => 1 },
      { name => 'review', require_claim => 1 },
      'done',
      'archived',
    ],
    priorities => [qw( low medium high critical )],
    wip_limits => {
      'in-progress' => 3,
      'review' => 2,
    },
    classes => [
      { name => 'expedite', wip_limit => 1, bypass_column_wip => 1 },
      { name => 'fixed-date' },
      { name => 'standard' },
      { name => 'intangible' },
    ],
    claim_timeout => '1h',
    defaults => {
      status   => 'backlog',
      priority => 'medium',
      class    => 'standard',
    },
    next_id => 1,
  };
}

1;
