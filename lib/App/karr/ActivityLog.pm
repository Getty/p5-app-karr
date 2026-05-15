# ABSTRACT: Activity log writer for karr board operations

package App::karr::ActivityLog;
our $VERSION = '0.103';
use Moo;
use JSON::MaybeXS qw( encode_json );
use POSIX qw( strftime );

has git => (
    is       => 'ro',
    required => 1,
);

sub log_entry {
    my ($self, %entry) = @_;
    $entry{ts} //= strftime('%Y-%m-%dT%H:%M:%SZ', gmtime());
    my $identity = $self->_identity;
    my $ref = "refs/karr/log/$identity";
    my $existing = $self->git->read_ref($ref);
    my $line = encode_json(\%entry);
    my $new = $existing ? "$existing\n$line" : $line;
    return $self->git->write_ref($ref, $new);
}

sub _identity {
    my ($self) = @_;
    my $email = $self->git->git_user_email || 'unknown';
    $email =~ s/[^a-zA-Z0-9._-]/_/g;
    return $email;
}

1;