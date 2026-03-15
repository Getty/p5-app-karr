# ABSTRACT: Git operations for karr sync (via CLI)

package App::karr::Git;

use strict;
use warnings;
use Path::Tiny qw( path );

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

sub is_repo {
    my ($self) = @_;
    return $self->dir->child('.git')->exists;
}

sub git_user_email {
    my ($self) = @_;
    my $email = `git config --get user.email`;
    chomp $email;
    return $email;
}

sub git_user_name {
    my ($self) = @_;
    my $name = `git config --get user.name`;
    chomp $name;
    return $name;
}

sub git_user_identity {
    my ($self) = @_;
    my $name = $self->git_user_name;
    my $email = $self->git_user_email;
    return "$name <$email>" if $name && $email;
    return $email // $name // '';
}

sub read_ref {
    my ( $self, $ref ) = @_;
    my $dir = $self->dir->stringify;
    my $content = `cd '$dir' && git cat-file -p '$ref' 2>/dev/null`;
    chomp $content if defined $content;
    return $content // '';
}

sub write_ref {
    my ( $self, $ref, $content ) = @_;
    my $dir = $self->dir->stringify;

    # Escape content for shell
    $content =~ s/'/'\\''/g;

    # Create blob from content
    my $blob_sha = `cd '$dir' && echo -n '$content' | git hash-object -w --stdin`;
    chomp $blob_sha;

    return unless $blob_sha;

    # Create/update ref
    `cd '$dir' && git update-ref '$ref' $blob_sha`;
    return 1;
}

sub delete_ref {
    my ( $self, $ref ) = @_;
    my $dir = $self->dir->stringify;
    `cd '$dir' && git update-ref -d '$ref' 2>/dev/null`;
    return 1;
}

sub fetch {
    my ( $self, $remote ) = @_;
    $remote //= 'origin';
    my $dir = $self->dir->stringify;
    system("cd \"$dir\" && git fetch \"$remote\" 2>/dev/null");
    return $? == 0;
}

sub push {
    my ( $self, $remote, $refspec ) = @_;
    $remote //= 'origin';
    my $dir = $self->dir->stringify;

    if ($refspec) {
        system("cd \"$dir\" && git push \"$remote\" $refspec 2>/dev/null");
    } else {
        system("cd \"$dir\" && git push \"$remote\" refs/karr/ 2>/dev/null");
    }
    return $? == 0;
}

sub pull {
    my ( $self, $remote ) = @_;
    $remote //= 'origin';
    my $dir = $self->dir->stringify;
    system("cd \"$dir\" && git fetch \"$remote\" refs/karr/*:refs/karr/* 2>/dev/null");
    return $? == 0;
}

1;
