package Math::Int64;

use strict;
use warnings;

BEGIN {
    our $VERSION = '0.08';

    require XSLoader;
    XSLoader::load('Math::Int64', $VERSION);
}

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(int64
                    int64_to_number
                    net_to_int64 int64_to_net
                    native_to_int64 int64_to_native
                    uint64
                    uint64_to_number
                    net_to_uint64 uint64_to_net
                    native_to_uint64 uint64_to_native);

sub import {
    my $pkg = shift;
    my @subs = grep { $_ ne ':native_if_available'} @_;
    if (@subs != @_ and _backend eq 'IV') {
	Math::Int64::Native->export_to_level(1, $pkg, @subs);
    }
    else {
	__PACKAGE__->export_to_level(1, $pkg, @subs);
    }
}

use overload ( '+' => \&_add,
               '+=' => \&_add,
               '-' => \&_sub,
               '-=' => \&_sub,
               '*' => \&_mul,
               '*=' => \&_mul,
               '/' => \&_div,
               '/=' => \&_div,
               '%' => \&_rest,
               '%=' => \&_rest,
               'neg' => \&_neg,
               '++' => \&_inc,
               '--' => \&_dec,
               '!' => \&_not,
               '~' => \&_bnot,
               '&' => \&_and,
               '|' => \&_or,
               '^' => \&_xor,
               '<<' => \&_left,
               '>>' => \&_right,
               '<=>' => \&_spaceship,
               '>' => \&_gtn,
               '<' => \&_ltn,
               '>=' => \&_gen,
               '<=' => \&_len,
               '==' => \&_eqn,
               '!=' => \&_nen,
               'bool' => \&_bool,
               '0+' => \&_number,
               '""' => \&_string,
               '=' => \&_clone,
               fallback => 1 );

package Math::UInt64;
use overload ( '+' => \&_add,
               '+=' => \&_add,
               '-' => \&_sub,
               '-=' => \&_sub,
               '*' => \&_mul,
               '*=' => \&_mul,
               '/' => \&_div,
               '/=' => \&_div,
               '%' => \&_rest,
               '%=' => \&_rest,
               'neg' => \&_neg,
               '++' => \&_inc,
               '--' => \&_dec,
               '!' => \&_not,
               '~' => \&_bnot,
               '&' => \&_and,
               '|' => \&_or,
               '^' => \&_xor,
               '<<' => \&_left,
               '>>' => \&_right,
               '<=>' => \&_spaceship,
               '>' => \&_gtn,
               '<' => \&_ltn,
               '>=' => \&_gen,
               '<=' => \&_len,
               '==' => \&_eqn,
               '!=' => \&_nen,
               'bool' => \&_bool,
               '0+' => \&_number,
               '""' => \&_string,
               '=' => \&_clone,
               fallback => 1 );

package Math::Int64::Native;

use Carp;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = @Math::Int64::EXPORT_OK;

*int64_to_number = \&Math::Int64::int64_to_number;
*int64_to_net = \&Math::Int64::int64_to_net;
*int64_to_native = \&Math::Int64::int64_to_native;

*uint64_to_number = \&Math::Int64::int64_to_number;
*uint64_to_net = \&Math::Int64::uint64_to_net;
*uint64_to_native = \&Math::Int64::uint64_to_native;

1;

__END__

=head1 NAME

Math::Int64 - Manipulate 64 bits integers in Perl

=head1 SYNOPSIS

  use Math::Int64 qw(int64);

  my $i = int64(1);
  my $j = $i << 40;
  my $k = int64("12345678901234567890");
  print($i + $j * 1000000);


=head1 DESCRIPTION

This module adds support for 64 bit integers, signed and unsigned, to
Perl.

=head2 Exportable functions

=over 4

=item int64()

=item int64($value)

Creates a new int64 value and initializes it to C<$value>, where
$value can be a Perl number or a string containing a number.

For instance:

  $i = int64(34);
  $j = int64("-123454321234543212345");

  $k = int64(1234567698478483938988988); # wrong!!!
                                         #  the unquoted number would
                                         #  be converted first to a
                                         #  real number causing it to
                                         #  loose some precision.

Once the int64 number is created it can be manipulated as any other
Perl value supporting all the standard operations (addition, negation,
multiplication, postincrement, etc.).


=item net_to_int64($str)

Converts an 8 bytes string containing an int64 in network order to the
internal representation used by this module.

=item int64_to_net($int64)

Returns an 8 bytes string with the representation of the int64 value
in network order.

=item native_to_int64($str)

=item int64_to_native($int64)

similar to net_to_int64 and int64_to_net, but using the native CPU
order.

=item int64_to_number($int64)

returns the optimum representation of the int64 value using Perl
internal types (IV, UV or NV). Precision may be lost.

For instance:

  for my $l (10, 20, 30, 40, 50, 60) {
    my $i = int64(1) << $l;
    my $n = int64_to_number($i);
    print "int64:$i => perl:$n\n";
  }


=item uint64

=item uint64_to_number

=item net_to_uint64

=item uint64_to_net

=item native_to_uint64

=item uint64_to_native

These functions are similar to their int64 counterparts, but
manipulate 64 bit unsigned integers.

=back

=head2 Fallback to native 64bit support if available

If the tag C<:native_if_available> is added to the import list and the
version of perl used has native support for 64bit integers, the
functions exported by the module to create 64bit intgers will return
regular perl scalars.

Usage example:

  use Math::Int64 qw( :native_if_available int64 );


This feature is not enabled by default because the semantics for perl
scalars and for 64 bit integers as implemented in this module are not
identical. Perl is prone to coerze integers into floats while this
module keeps then always as 64bit integers. Specifically, the division
operation and overflows are the most problematic cases.

Besides that, in most situations it is safe to use the native fallback.

=head1 BUGS AND SUPPORT

The fallback to native 64bit integers feature is experimental.

This module requires int64 support from the C compiler.

For bug reports, feature requests or just help using this module, use
the RT system at L<http://rt.cpan.org> or send my and email or both!

The source code of this module is hosted at GitHub:
L<http://github.com/salva/p5-Math-Int64>.

=head1 SEE ALSO

Other modules that allow Perl to support larger integers or numbers
are L<Math::BigInt>, L<Math::BigRat> and L<Math::Big>,
L<Math::BigInt::BitVect>, L<Math::BigInt::Pari> and
L<Math::BigInt::GMP>.

=head1 COPYRIGHT AND LICENSE

Copyright E<copy> 2007, 2009 by Salvador FandiE<ntilde>o
(sfandino@yahoo.com)

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
