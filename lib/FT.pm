package FT;
use 5.028;
use strict;
use warnings;
use experimental 'signatures';
use DBD::Pg ':async';
use Devel::Assert;
use Plack::Request;
use Plack::Response;
use IO::Async::Loop;
use Cpanel::JSON::XS ();
use Time::HiRes;
use Syntax::Keyword::Try;
use Encode qw/decode_utf8 encode_utf8/;

use constant {
    SEARCH_FIELDS => [ qw/period owner owner_inn type contractor contractor_inn date number/ ],
    ORGANIZATIONS => [ qw/id name inn/ ],
    INVOICES      => [ qw/period owner_inn type contractor_inn date number json/ ],
    LOOP_TIMEOUT  => 0.1,
};

#@type IO::Async::Loop
my $loop;


sub run_psgi ($class, $env) {
    # define loop for tests with // operator
    $loop = $env->{'io.async.loop'} //= IO::Async::Loop->new;

    # validate request and extract filter hash from query
    my $filter;
    try {
        $filter = parse_request($env);
    } catch {
        return [
            '400',
            [ 'Content-Type' => 'text/html' ],
            [ "$@" ],
        ];
    };

    # optionally search inn based on hash
    if (exists $filter->{owner} || exists $filter->{contractor}) {
        my $inns = lookup_inn({
            map {
                $filter->{$_} ? ($_ => $filter->{$_}) : ()
            } qw/owner contractor/}
        );
        delete $filter->{$_} for qw/owner contractor/;
        if (scalar keys $inns->%*) {
            $filter->@{keys $inns->%*} = values $inns->%*;
        }
    }

    # search invoices
    my $invoices = $class->lookup_invoices($filter);

    # prepare answer
    my $res = Plack::Response->new(200);
    $res->content_type('application/json; charset=utf-8');
    $res->body($class->encoder->encode($invoices));
    return $res->finalize;;
}

sub parse_request ($env) {
    my $req = Plack::Request->new($env);
    my %filter = $req->parameters->%*;
    %filter = map { $_ => decode_utf8($filter{$_}) } keys %filter;

    state $validator = {
        owner_inn      => qr/^[0-9]{10,12}$/,
        contractor_inn => qr/^[0-9]{10,12}$/,
        period         => qr/^y20[01][0-9]q[1-4]$/,
        type           => qr/^(?:[8-9]|1[0-2])$/,
        date           => qr/^[0-9]{4}-[0-9]{2}-[0-9]]{2}$/,
    };
    foreach my $key (keys $validator->%*) {
        next unless exists $filter{$key};
        next if $filter{$key} =~ $validator->{$key};
        die "key $key is not valid";
    }

    return \%filter;
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

    my %inns;
    my $i = 0;
    while ($i < scalar keys %sth) {
        for my $field (keys %sth) {
            next unless $sth{$field}->pg_ready;
            $sth{$field}->pg_result();
            my ($inn) = $sth{$field}->fetchrow_array();
            $i ++;
            next unless defined $inn;
            $inns{"${field}_inn"} = $inn;

        }
        $loop->loop_once(LOOP_TIMEOUT);
    }
    return \%inns;
}

sub db {
    state $dbh = DBI->connect('dbi:Pg:dbname=ft;host=db', 'dev', 'pass', {
        AutoCommit=>0,RaiseError=>1
    });
    return $dbh;
}

sub encoder {
    state $encoder = Cpanel::JSON::XS->new->utf8;
    return $encoder;
}

sub lookup_invoices ($class, $filter) {
    state $fields = join ',', INVOICES->@*;
    my $query = <<~"SQL";
        SELECT $fields FROM invoices
            WHERE TRUE
        SQL

    my @binds;
    for my $field (keys $filter->%*) {
        my ($op, $value);
        if ($field =~ /_inn$/) {
            $op = 'ILIKE';
            $value = '%' . $filter->{$field} . '%';
        } else {
            $op = '=';
            $value = $filter->{$field};
        }
        $query .= "\n\tAND $field $op ?";
        push @binds, $value;
    }

    my $sth = $class->db->prepare($query, {pg_async => PG_ASYNC});
    $sth->execute(@binds);

    while (!$class->db->pg_ready) {
        $loop->loop_once(LOOP_TIMEOUT);
    }

    $sth->pg_result;
    return $sth->fetchall_arrayref({});
}

1;