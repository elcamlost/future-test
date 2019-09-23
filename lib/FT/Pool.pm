package FT::Pool;
use strict;
use warnings;
use experimental 'signatures';
use DBI;
use Carp qw/confess/;
use Devel::Assert;

use constant MAX_CONNECTION => 10;

sub new ($class, $dsn, $username, $password, $opts = {}) {
    assert (ref $dsn eq '');
    assert (ref $username eq '');
    assert (ref $password eq '');
    assert (ref $opts eq 'HASH');

    my %attrs;
    $attrs{dsn} = $dsn;
    $attrs{username} = $username;
    $attrs{password} = $password;
    $attrs{options} = {$opts->%*};
    $attrs{queue} = [];
    bless \%attrs, ref $class || $class;
}

sub dequeue_dbh ($self) {
    while (my $dbh = shift $self->{queue}->@*) {
        return $dbh if $dbh->ping;
    }
    my $dbh = DBI->connect(map { $self->{$_} } qw/dsn username password options/);
    return $dbh;
}

sub enqueue_dbh ($self, $dbh) {
    if ($dbh->ping) {
        push $self->{queue}->@*, $dbh;
    } else {
        confess q[can't enqueue invalid handle];
    }

}

1;