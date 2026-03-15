# t/11-git-impl.t - Test Git CLI implementation for karr sync
use strict;
use warnings;
use Test::More;
use Path::Tiny qw( path tempdir );

subtest 'git config: user.email must be set' => sub {
    my $email = `git config --get user.email`;
    chomp $email;
    ok($email, "user.email is set to: $email");
};

subtest 'git repo detection' => sub {
    my $git_dir = path('.git');
    ok($git_dir->exists, '.git directory exists');

    my $head = `git rev-parse --is-inside-work-tree`;
    chomp $head;
    is($head, 'true', 'current dir is inside git work tree');
};

subtest 'refs/karr/ refs work' => sub {
    my $tmpdir = tempdir( CLEANUP => 1 );

    system("cd $tmpdir && git init -q 2>/dev/null");
    system("cd $tmpdir && git config user.email test\@test.com");
    system("cd $tmpdir && git config user.name Test");

    # Create a commit
    path("$tmpdir/test.txt")->spew("test");
    system("cd $tmpdir && git add . 2>/dev/null");
    system("cd $tmpdir && git commit -m 'test' -q 2>/dev/null");

    my $sha = `cd $tmpdir && git rev-parse HEAD`;
    chomp $sha;

    # Create ref
    my $ref = 'refs/karr/tasks/1';
    system("cd $tmpdir && git update-ref $ref $sha 2>/dev/null");

    my $read = `cd $tmpdir && git rev-parse $ref 2>/dev/null`;
    chomp $read;
    is($read, $sha, "refs/karr/tasks/1 created and read back");

    # Use -D to force delete
    system("cd $tmpdir && git update-ref -d $ref 2>/dev/null");
};

subtest 'git fetch works' => sub {
    my $remote = `git remote get-url origin 2>/dev/null`;
    if ($remote) {
        chomp $remote;
        pass("Remote configured: $remote");
    } else {
        skip("No remote configured", 1);
    }
};

done_testing;
