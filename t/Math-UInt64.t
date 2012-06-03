#!/usr/bin/perl

use Test::More tests => 47;

use Math::Int64 qw(uint64 uint64_to_number
                   net_to_uint64 uint64_to_net
                   native_to_uint64 uint64_to_native);

my $i = uint64('1234567890123456789');
my $j = $i + 1;
my $k = (uint64(1) << 60) + 255;

# 1
ok($i == '1234567890123456789');

ok($j - 1 == '1234567890123456789');

ok (($k & 127) == 127);

ok (($k & 256) == 0);

# 5
ok ($i * 2 == $j + $j - 2);

ok ($i * $i * $i * $i == ($j * $j - 2 * $j + 1) * ($j * $j - 2 * $j + 1));

ok (($i / $j) == 0);

ok ($j / $i == 1);

ok ($i % $j == $i);

# 10
ok ($j % $i == 1);

ok (($j += 1) == $i + 2);

ok ($j == $i + 2);

ok (($j -= 3) == $i - 1);

ok ($j == $i - 1);

$j = $i;
# 15
ok (($j *= 2) == $i << 1);

ok (($j >> 1) == $i);

ok (($j / 2) == $i);

$j = $i + 2;

ok (($j %= $i) == 2);

ok ($j == 2);

# 20
ok (($j <=> $i) < 0);

ok (($i <=> $j) > 0);

ok (($i <=> $i) == 0);

ok (($j <=> 2) == 0);

ok ($j < $i);

# 25
ok ($j <= $i);

ok (!($i < $j));

ok (!($i <= $j));

ok ($i <= $i);

ok ($j >= $j);

# 30
ok ($i > $j);

ok ($i >= $j);

ok (!($j > $i));

ok (!($j >= $i));

ok (int(log(uint64(1)<<50)/log(2)+0.001) == 50);

# 35

my $l = uint64("1271310319617");

is ("$l", "1271310319617", "string to/from int64 conversion");

ok (native_to_uint64(uint64_to_native(1)) == 1);

ok (native_to_uint64(uint64_to_native(0)) == 0);

ok (native_to_uint64(uint64_to_native(12343)) == 12343);

ok (native_to_uint64(uint64_to_native($l)) == $l);

# 40

ok (native_to_uint64(uint64_to_native($j)) == $j);

ok (native_to_uint64(uint64_to_native($i)) == $i);

ok (net_to_uint64(uint64_to_net(1)) == 1);

ok (net_to_uint64(uint64_to_net(0)) == 0);

ok (net_to_uint64(uint64_to_net(12343)) == 12343);

# 45

ok (net_to_uint64(uint64_to_net($l)) == $l);

ok (net_to_uint64(uint64_to_net($j)) == $j);

ok (net_to_uint64(uint64_to_net($i)) == $i);
