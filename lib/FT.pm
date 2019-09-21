package FT;
use strict;
use warnings;
use experimental 'signatures';

sub run_psgi {
    return [
        '200',
        [ 'Content-Type' => 'text/html' ],
        [ 42 ],
    ];
}
1;