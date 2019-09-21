#!/usr/bin/env perl
use strict;
use warnings 'FATAL';
use Test2::V0;
use Plack::Test;
use HTTP::Request::Common;

my $app = do './app.psgi';
my $test = Plack::Test->create($app);

my $res = $test->request(GET "/"); # HTTP::Response
is $res->code, 200;
is $res->message, 'OK';
is $res->header('Content-Type'), 'text/html';
is $res->content, 42;

done_testing();