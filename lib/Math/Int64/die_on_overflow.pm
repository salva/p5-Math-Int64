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

# ABSTRACT: catch overflows when using Math::Int64

__END__

=head1 SYNOPSIS

  use Math::Int64 qw(uint64);
  use Math::Int64::die_on_overflow;

  my $number = uint64(2**32);
  say($number * $number); # overflow error!


=head1 SEE ALSO

L<Math::Int64>.

=cut
