package Math::Int64::die_on_overflow;

sub import {
    require Math::Int64;
    Math::Int64::_set_may_die_on_overflow(1);
    $^H{'Math::Int64::die_on_overflow'} = 1
}


sub unimport {
    undef $^H{'Math::Int64::die_on_overflow'}
}

1;

__END__

=head1 NAME

Math::Int64::die_on_overflow - catch overflows when using Math::Int64

=head1 SYNOPSIS

  use Math::Int64 qw(uint64);
  use Math::Int64::die_on_overflow;

  my $number = uint64(2**32);
  say($number * $number); # overflow error!


=head1 SEE ALSO

L<Math::Int64>.

=head1 COPYRIGHT AND LICENSE

Copyright E<copy> 2011 by Salvador FandiE<ntilde>o
(sfandino@yahoo.com)

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
