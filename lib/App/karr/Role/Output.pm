# ABSTRACT: Role providing common output format options

package App::karr::Role::Output;
our $VERSION = '0.004';
use Moo::Role;
use MooX::Options;

option json => (
  is => 'ro',
  doc => 'JSON output',
);

option compact => (
  is => 'ro',
  doc => 'Compact output',
);

sub print_json {
  my ($self, $data) = @_;
  require JSON::MaybeXS;
  print JSON::MaybeXS::encode_json($data) . "\n";
}

1;
