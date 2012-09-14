#!/usr/bin/perl

use Test::More tests => 200;

use strict;
use warnings;

use Storable;

use Math::Int64 qw(int64_rand uint64_rand);

my $a = [map int64_rand, 0..99];
my $b = Storable::thaw(Storable::freeze($a));

for (0..$#$a) {
    ok ($a->[$_] == $b->[$_]);
}

$a = [map uint64_rand, 0..99];
$b = Storable::thaw(Storable::freeze($a));

for (0..$#$a) {
    ok ($a->[$_] == $b->[$_]);
}
