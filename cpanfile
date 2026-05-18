requires 'Moo';
requires 'MooX::Cmd';
requires 'MooX::Options';
requires 'YAML::XS';
requires 'Path::Tiny';
requires 'JSON::MaybeXS';
requires 'Text::Table::Tiny';
requires 'Term::ANSIColor';
requires 'Time::Piece';
requires 'File::ShareDir';
requires 'Try::Tiny';
requires 'Git::Native';
requires 'Git::Libgit2';

on test => sub {
    requires 'Test::More';
    requires 'File::Temp';
    requires 'Test::Exception';
};
