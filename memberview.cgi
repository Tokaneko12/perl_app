#!/usr/bin/perl
BEGIN {
push(@INC, '/home/tkaneko/share/contents');
}

use strict;
use MemberView;

my $webapp = MemberView->new();
$webapp->run();
