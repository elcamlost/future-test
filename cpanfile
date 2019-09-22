requires 'perl' => 5.28.0;
requires 'Database::Async';
requires 'Cpanel::JSON::XS';
requires 'Future::AsyncAwait';
requires 'Syntax::Keyword::Try';
requires 'Net::Async::HTTP::Server';
requires 'Devel::Assert';
requires 'DBI';
requires 'DBD::Pg';

on 'test' => sub {
    requires 'Test2::Suite',                '0.000115';
    requires 'Test2::Harness';
    requires 'Devel::Cover',                '1.31';
    requires 'Plack::Test';
};
