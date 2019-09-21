#!/usr/bin/env perl
use strict;
use warnings;

my $app = sub {
  return [
    '200',
    [ 'Content-Type' => 'text/html' ],
    [ 42 ],
  ];
};