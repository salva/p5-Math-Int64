#!/usr/bin/perl

use strict;
use warnings;

use Test::More 0.88;

use Math::Int64 qw(int64 int64_to_number
                   net_to_int64 int64_to_net
                   string_to_int64 int64_to_string
                   native_to_int64 int64_to_native
                   int64_to_BER BER_to_int64 uint64_to_BER
                   int64_rand
                   int64_to_hex hex_to_int64
                 );

my $i = int64('1234567890123456789');
my $j = $i + 1;
my $k = (int64(1) << 60) + 255;

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

ok (int(log(int64(1)<<50)/log(2)+0.001) == 50);

# 35

my $n = int64_to_net(-1);
ok (join(" ", unpack "C*" => $n) eq join(" ", (255) x 8));

ok (net_to_int64($n) == -1);

ok (native_to_int64(int64_to_native(-1)) == -1);

ok (native_to_int64(int64_to_native(0)) == 0);

ok (native_to_int64(int64_to_native(-12343)) == -12343);

# 40

$n = pack(NN => 0x01020304, 0x05060708);
my $nu = (int64(0x01020304) << 32) + 0x05060708;

ok (net_to_int64($n) == $nu);

ok ((($i | $j) & 1) != 0);

ok ((($i & $j) & 1) == 0);

my $l = int64("1271310319617");

is ("$l", "1271310319617", "string to/from int64 conversion");

is(BER_to_int64(int64_to_BER($l)). "", "1271310319617");

is(int64_to_BER($nu), uint64_to_BER($nu << 1));

for (1..50) {
    my $n = int64_rand;
    # $n = int64("8420970171052099265");
    my $hex = int64_to_hex($n);
    ok($n == int64("$n"));
    ok($n == string_to_int64(int64_to_string($n)), "int64->string->int64 n: $n hex: $hex");
    ok(int64_to_hex($n) eq int64_to_hex(string_to_int64(int64_to_string($n))));
    ok($n == hex_to_int64(int64_to_hex($n)));
    is("$n", string_to_int64(int64_to_string($n)));
    is("$n", string_to_int64(int64_to_string($n, 25), 25));
    is("$n", string_to_int64(int64_to_string($n, 36), 36));
    is("$n", string_to_int64(int64_to_string($n, 2), 2));
    is("$n", native_to_int64(int64_to_native($n)));
    is("$n", net_to_int64(int64_to_net($n)));
    is("$n", BER_to_int64(int64_to_BER($n)));
}

my $two  = int64(2);
my $four = int64(4);
is ($two  ** -1, 0, "signed pow 2**-1");
is ($four ** -1, 0, "signed pow 4**-1");

for my $j (0..63) {
    my $one = int64(1);

    is($two  ** $j, $one <<     $j, "signed pow 2**$j");
    is($four ** $j, $one << 2 * $j, "signed pow 4**$j") if $j < 32;

    is($one << $j, $two ** $j, "$one << $j");

    $one <<= $j;
    is($one, $two ** $j, "$one <<= $j");

    next unless $j;

    my $max = (((int64(2)**62)-1)*2)+1;
    is($max >> $j, $max / ( 2**$j ), "max int64 >> $j");

    my $copy = int64($max);
    $copy >>= $j;
    is($copy, $max / ( 2**$j ), "max int64 >>= $j");

}

done_testing();
