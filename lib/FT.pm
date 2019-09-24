package FT;
use 5.028;
use strict;
use warnings;
use experimental 'signatures';
use Carp qw/confess croak/;
use FT::Pool;
use Devel::Assert;
use Plack::Request;
use Plack::Response;
use IO::Async::Loop;
use IO::Async::Stream;
use Cpanel::JSON::XS ();
use Time::HiRes;
use Syntax::Keyword::Try;
use Encode qw/decode_utf8 encode_utf8/;

use constant {
    SEARCH_FIELDS => [qw/period owner owner_inn type contractor contractor_inn date number/],
    ORGANIZATIONS => [qw/id name inn/],
    INVOICES      => [qw/period owner_inn type contractor_inn date number json/],
    LOOP_TIMEOUT  => 0.1,
};

#@type IO::Async::Loop
my $loop;


sub run_psgi ($class, $env) {

    # define loop for tests with // operator
    $loop = $env->{'io.async.loop'} //= IO::Async::Loop->new;

    my $res = Plack::Response->new(200);
    $res->content_type('application/json; charset=utf-8');

    # validate request and extract filter hash from query
    my $filter;
    try {
        $filter = parse_request($env);
    } catch {
        $res->body("$@");
        $res->status(400);
        return $res->finalize;
    };

    try {
        # optionally search inn based on hash
        $filter = $class->add_inn_to_filter($filter->%*);

        # search invoices
        my $invoices = $class->lookup_invoices($filter->%*);

        # prepare answer
        $res->body($class->encoder->encode($invoices));
        return $res->finalize;
    } catch {
        $res->body("$@");
        $res->status(500);
        return $res->finalize;
    };

}

sub parse_request ($env) {
    my $req    = Plack::Request->new($env);
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
        croak "key $key is not valid";
    }

    return \%filter;
}

sub add_inn_to_filter ($class, %filter) {
    my (@queries, @binds);
    for my $field (qw/owner contractor/) {
        next unless exists $filter{$field};

        my $type = "${field}_inn";
        push @queries, <<~"SQL";
            select '$type' as type, inn
            from organizations where name ilike ?
            SQL
        my $value = delete $filter{$field};
        push @binds, "%$value%";
    }
    return \%filter unless scalar @queries;

    my $query = join "\nUNION\n", @queries;
    my $dbh = $class->db_pool->dequeue_dbh();
    my $sth = $dbh->prepare($query);
    $sth->execute(@binds);
    my $data = $sth->fetchall_arrayref({});
    $class->db_pool->enqueue_dbh($dbh);

    foreach my $row ($data->@*) {
        $filter{$row->{type}} = $row->{inn};
    }
    return \%filter;
}

sub db_pool {
    state $pool = FT::Pool->new(
        'dbi:Pg:dbname=ft;host=db',
        'dev', 'pass',
        {
            AutoCommit => 0,
            RaiseError => 1
        }
    );
    return $pool;
}

sub encoder {
    state $encoder = Cpanel::JSON::XS->new->utf8;
    return $encoder;
}

sub lookup_invoices ($class, %filter) {
    state $fields = join ',', INVOICES->@*;
    my $query = <<~"SQL";
        SELECT $fields FROM invoices
            WHERE TRUE
        SQL

    my @binds;
    for my $field (keys %filter) {
        my ($op, $value);
        if ($field =~ /_inn$/) {
            $op    = 'ILIKE';
            $value = "%$filter{$field}%";
        } else {
            $op    = '=';
            $value = $filter{$field};
        }
        $query .= "\n\tAND $field $op ?";
        push @binds, $value;
    }

    my $dbh = $class->db_pool->dequeue_dbh;
    my $sth = $dbh->prepare($query);
    $sth->execute(@binds);
    my $data = $sth->fetchall_arrayref({});
    $class->db_pool->enqueue_dbh($dbh);
    return $data;
}

1;