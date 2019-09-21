#!/usr/bin/env perl
use strict;
use warnings;
use FindBin qw/$RealBin/;
use lib $RealBin . '/../lib';

use FT;

my $app = sub { FT->run_psgi(@_); };