#!/usr/bin/perl

use Test::More tests => 597;

use Math::Int64 qw(uint64 uint64_to_number
                   net_to_uint64 uint64_to_net
                   native_to_uint64 uint64_to_native
                   uint64_to_hex hex_to_uint64
                   uint64_to_string string_to_uint64
                   uint64_to_BER BER_to_uint64
                   uint64_rand );

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


for (1..50) {
    my $n = uint64_rand;
    # $n = uint64("8420970171052099265");
    my $hex = uint64_to_hex($n);
    ok($n == uint64("$n"));
    ok($n == string_to_uint64(uint64_to_string($n)), "uint64->string->uint64 n: $n hex: $hex");
    ok(uint64_to_hex($n) eq uint64_to_hex(string_to_uint64(uint64_to_string($n))));
    ok($n == hex_to_uint64(uint64_to_hex($n)));
    is("$n", string_to_uint64(uint64_to_string($n)));
    is("$n", string_to_uint64(uint64_to_string($n, 25), 25));
    is("$n", string_to_uint64(uint64_to_string($n, 36), 36));
    is("$n", string_to_uint64(uint64_to_string($n, 2), 2));
    is("$n", native_to_uint64(uint64_to_native($n)));
    is("$n", net_to_uint64(uint64_to_net($n)));
    is("$n", BER_to_uint64(uint64_to_BER($n)));
}
