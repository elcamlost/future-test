package FT;
use 5.028;
use strict;
use warnings;
use experimental 'signatures';
use DBD::Pg ':async';
use Devel::Assert;
use Plack::Request;
use IO::Async::Loop;
use Time::HiRes;
use Syntax::Keyword::Try;
use Encode qw/decode_utf8 encode_utf8/;

use constant {
    SEARCH_FIELDS => [qw/period owner owner_inn type contractor contractor_inn date number/],
    ORGANIZATIONS => [qw/id name inn/],
    INVOICES      => [qw/period owner_inn type contractor_inn date number json/],
};

#@type IO::Async::Loop
my $loop;

sub run_psgi ($class, $env) {
    $loop = $env->{'io.async.loop'} // IO::Async::Loop->new;

    # validate and extract search hash from query

    my $query;
    try {
        $query = parse_request($env);
    } catch {
        return [
            '400',
            [ 'Content-Type' => 'text/html' ],
            [ "$@" ],
        ];
    };

    # optionally search inn based on hash
    if (exists $query->{owner} || exists $query->{contractor}) {
        my $inns = lookup_inn({
            map {
                $query->{$_} ? ($_ => $query->{$_}) : ()
            } qw/owner contractor/}
        );
    }

    # search invoices

    # prepare answer

    $class->invoices();
    return [
        '200',
        [ 'Content-Type' => 'text/html' ],
        [ 42 ],
    ];
}

sub parse_request ($env) {
    my $req = Plack::Request->new($env);
    my %query = $req->parameters->%*;
    %query = map { $_ => decode_utf8($query{$_}) } keys %query;

    state $validator = {
        owner_inn      => qr/^[0-9]{10,12}$/,
        contractor_inn => qr/^[0-9]{10,12}$/,
        period         => qr/^y20[01][0-9]q[1-4]$/,
        type           => qr/^(?:[8-9]|1[0-2])$/,
        date           => qr/^[0-9]{4}-[0-9]{2}-[0-9]]{2}$/,
    };
    foreach my $key (keys $validator->%*) {
        next unless exists $query{$key};
        next if $query{$key} =~ $validator->{$key};
        die "key $key is not valid";
    }

    return \%query;
}

sub lookup_inn($q) {
    assert(ref $loop eq 'IO::Async::Loop');
    assert(ref $q eq 'HASH');
    assert(scalar keys $q->%* > 0);

    my %sth;
    for my $field (qw/owner contractor/) {
        next unless exists $q->{$field};
        $sth{$field} = __PACKAGE__->db->prepare_cached(<<~'SQL', {pg_async => PG_ASYNC});
            SELECT inn FROM organizations WHERE name ILIKE ?
            SQL
        my $value = '%' . $q->{$field} . '%';
        $sth{$field}->execute($value);
    }

    my @inns;
    while (scalar @inns < scalar keys %sth) {
        for my $field (keys %sth) {
            next unless $sth{$field}->pg_ready;
            $sth{$field}->pg_result();
            my ($inn) = $sth{$field}->fetchrow_array();
            push @inns, $inn;
        }
        $loop->loop_once(0.1);
    }
    return [ grep {defined} @inns ];
}

sub db {
    state $dbh = DBI->connect('dbi:Pg:dbname=ft;host=db', 'dev', 'pass', {
        AutoCommit=>0,RaiseError=>1
    });
    return $dbh;
}

sub invoices ($class) {
    my $sth = $class->db->prepare(<<~'SQL', {pg_async => PG_ASYNC});
        select * from invoices
        SQL
    $sth->execute();

    while (!$class->db->pg_ready) {
        $loop->loop_once(0.1);
    }

    print "The query has finished. Gathering results\n";
    my $result = $sth->pg_result;
    print "Result: $result\n";
    my $info = $sth->fetchall_arrayref();

    return 1;
}

1;