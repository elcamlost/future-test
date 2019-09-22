package FT;
use 5.028;
use strict;
use warnings;
use experimental 'signatures';
use Database::Async;
use Future::AsyncAwait;

sub run_psgi ($class, $env) {
    my $loop = $env->{'io.async.loop'};

    $class->invoices($loop);
    return [
        '200',
        [ 'Content-Type' => 'text/html' ],
        [ 42 ],
    ];
}

sub db ($class, $loop) {
    warn 'here db';
    state $dbh  //= do {
        my $d = Database::Async->new(
            uri  => 'postgres://dev:pass@db/ft',
            pool => {
                max => 2,
            },
        );
        $loop->add($d);
        $d;
    };
    return $dbh;
}

async sub invoices ($class, $loop) {
    warn 'here invoices';
    my @invoice = await $class->db($loop)->query(<<~'SQL',
        select * from invoices
        SQL
    )->single;
    use Data::Dumper;warn Dumper \@invoice;
    return 1;
}

1;