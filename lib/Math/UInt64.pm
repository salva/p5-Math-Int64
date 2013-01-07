package Math::UInt64;

require Math::Int64;
require Carp;

sub import { goto &Math::Int64::import }

1;

__END__

=head1 NAME

Math::UInt64 - Manipulate 64 bit unsigned integers from Perl

=head1 DESCRIPTION

Math::UInt64 is just an alias for Math::Int64, the only reason it
exists as an independent package is to allow L<Storable> to load it on
demand.

=head1 SEE ALSO

L<Math::Int64>.

=head1 COPYRIGHT AND LICENSE

Copyright E<copy> 2007, 2009, 2011-2013 by Salvador FandiE<ntilde>o
(sfandino@yahoo.com)

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
