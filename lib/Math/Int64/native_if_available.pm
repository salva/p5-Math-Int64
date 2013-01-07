package Math::Int64::native_if_available;

sub import {
    if (Math::Int64::_backend() eq 'IV' and $] >= 5.008) {
        Math::Int64::_set_may_use_native(1);
        $^H{Math::Int64::native_if_available} = 1;
    }
}

sub unimport {
    undef $^H{Math::Int64::native_if_available};
}

1;
