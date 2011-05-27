package Math::Int64;

use strict;
use warnings;

BEGIN {
    our $VERSION = '0.14';

    require XSLoader;
    XSLoader::load('Math::Int64', $VERSION);
}

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(int64
                    int64_to_number
                    net_to_int64 int64_to_net
                    native_to_int64 int64_to_native
                    string_to_int64 hex_to_int64
                    int64_to_string int64_to_hex
                    int64_rand
                    int64_srand
                    uint64
                    uint64_to_number
                    net_to_uint64 uint64_to_net
                    native_to_uint64 uint64_to_native
                    string_to_uint64 hex_to_uint64
                    uint64_to_string uint64_to_hex
                    uint64_rand
                  );

sub import {
    my $pkg = shift;
    my @subs = grep { $_ ne ':native_if_available'} @_;
    my %native;
    if (@subs != @_ and _backend eq 'IV') {
        $native{$_} = 1 for grep Math::Int64::Native->can($_), @subs;
    }
    # warn "native: ".join(", ", keys %native);
    Math::Int64::Native->export_to_level(1, $pkg, grep $native{$_}, @subs);
    Math::Int64->export_to_level(1, $pkg, grep !$native{$_}, @subs);
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

our @ISA = qw(Exporter);
our @EXPORT_OK = @Math::Int64::EXPORT_OK;

#*int64_to_number = \&Math::Int64::int64_to_number;
#*int64_to_net = \&Math::Int64::int64_to_net;
#*int64_to_native = \&Math::Int64::int64_to_native;

#*uint64_to_number = \&Math::Int64::int64_to_number;
#*uint64_to_net = \&Math::Int64::uint64_to_net;
#*uint64_to_native = \&Math::Int64::uint64_to_native;

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

=item string_to_int64($str, $base)

Converts the string to a int64 value. The conversion is done according
to the given base, which must be a number between 2 and 36 inclusive
or the special value 0. C<$base> defaults to 0.

The string may begin with an arbitrary amount of white space followed
by a single optional C<+> or C<-> sign. If base is zero or 16, the
string may then include a "0x" prefix, and the number will be read in
base 16; otherwise, a zero base is taken as 10 (decimal) unless the
next character is '0', in which case it is taken as 8 (octal).

Underscore characters (C<_>) between the digits are ignored.

No overflow checks are performed by this function.

See also L<strtoll(3)>.

=item hex_to_int64($i64)

Shortcut for string_to_int64($str, 16)

=item int64_to_string($i64, $base)

Converts the int64 value to its string representation in the given
base (defaults to 10).

=item int64_to_hex($i64)

Shortcut for C<int64_to_string($i64, 16)>.

=item int64_rand

Generates a 64 bit random number using ISAAC-64 algorithm.

=item int64_srand($seed)

=item int64_srand()

Sets the seed for the random number generator.

C<$seed>, if given, should be a 2KB long string.

=item uint64

=item uint64_to_number

=item net_to_uint64

=item uint64_to_net

=item native_to_uint64

=item uint64_to_native

=item string_to_uint64

=item hex_to_uint64

=item uint64_to_string

=item uint64_to_hex

These functions are similar to their int64 counterparts, but
manipulate 64 bit unsigned integers.

=back

=head2 Fallback to native 64bit support if available

If the tag C<:native_if_available> is added to the import list and the
version of perl used has native support for 64bit integers, the
functions exported by the module to create 64bit integers will return
regular perl scalars.

Usage example:

  use Math::Int64 qw( :native_if_available int64 );


This feature is not enabled by default because the semantics for perl
scalars and for 64 bit integers as implemented in this module are not
identical. Perl is prone to coerze integers into floats while this
module keeps then always as 64bit integers. Specifically, the division
operation and overflows are the most problematic cases.

Besides that, in most situations it is safe to use the native fallback.

=head2 C API

This module provides a native C API that can be used to create and
read Math::Int64 int64 and uint64 SVs from your own XS modules.

In order to use it you need to follow these steps:

=over 4

=item *

Import the files C<perl_math_int64.c>, C<perl_math_int64.h> and
optionally C<typemaps> from Math::Int64 C<c_api> directory into your
project directory.

=item *

Include the file C<perl_math_int64.h> in the C or XS source files
where you want to convert 64bit integers to/from Perl SVs.

Note that this header file requires the types int64_t and uint64_t to
be defined beforehand.

=item *

Add the file C<perl_math_int64.c> to your compilation targets (see the
sample Makefile.PL below).

=item *

Add a call to the macro C<MATH_INT64_BOOT> to the C<BOOT> section of
your XS file.

=back

For instance:

 --- Foo64.xs ---------

  #include "EXTERN.h"
  #include "perl.h"
  #include "XSUB.h"
  #include "ppport.h"
  
  /* #define MATH_INT64_NATIVE_IF_AVAILABLE */
  #include "math_int64.h"
  
  MODULE = Foo64		PACKAGE = Foo64
  BOOT:
      MATH_INT64_BOOT;
  
  int64_t
  some_int64()
  CODE:
      RETVAL = -42;
  OUTPUT:
      RETVAL
  
  
  --- Makefile.PL -----

  use ExtUtils::MakeMaker;
  WriteMakefile( NAME         => 'Foo64',
                 VERSION_FROM => 'lib/Foo64.pm',
                 OBJECT       => '$(O_FILES)' );


If the macro C<MATH_INT64_NATIVE_IF_AVAILABLE> is defined before
including C<perl_math_int64.h> and the perl interpreter is compiled
with mative 64bit integer support, IVs will be used to represent 64bit
integers instead of the object representation provided by Math::Int64.

These are the C macros available from Math::Int64 C API:

=over 4

=item SV *newSVi64(int64_t i64)

Returns an SV representing the given int64_t value.

=item SV *newSVu64(uint64_t 64)

Returns an SV representing the given uint64_t value.

=item int64_t SvI64(SV *sv)

Extracts the int64_t value from the given SV.

=item uint64_t SvU64(SV *sv)

Extracts the uint64_t value from the given SV.

=item int SvI64OK(SV *sv)

Returns true is the given SV contains a valid int64_t value.

=item int SvU64OK(SV *sv)

Returns true is the given SV contains a valid uint64_t value.

=back

If you require any other function available through the C API don't
hesitate to ask for it!

=head1 BUGS AND SUPPORT

The C API feature is experimental.

The fallback to native 64bit integers feature is experimental.

This module requires int64 support from the C compiler.

For bug reports, feature requests or just help using this module, use
the RT system at L<http://rt.cpan.org> or send my and email or both!

The source code of this module is hosted at GitHub:
L<http://github.com/salva/p5-Math-Int64>.

=head1 SEE ALSO

The C API usage sample module L<Math::Int64::C_API::Sample>.

Other modules that allow Perl to support larger integers or numbers
are L<Math::BigInt>, L<Math::BigRat> and L<Math::Big>,
L<Math::BigInt::BitVect>, L<Math::BigInt::Pari> and
L<Math::BigInt::GMP>.

=head1 COPYRIGHT AND LICENSE

Copyright E<copy> 2007, 2009, 2011 by Salvador FandiE<ntilde>o
(sfandino@yahoo.com)

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
