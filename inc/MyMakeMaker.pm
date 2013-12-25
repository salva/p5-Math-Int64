package inc::MyMakeMaker;

use strict;
use warnings;

use Moose;

extends 'Dist::Zilla::Plugin::MakeMaker::Awesome';

override _build_MakeFile_PL_template => sub {
    my $self = shift;
    my $template = super();

    my $extra = do { local $/; <DATA> };
    return $template . $extra;
};

__PACKAGE__->meta()->make_immutable();

1;

__DATA__

sub _backend_define {
    my $backend
        = defined $ENV{MATH_INT64_BACKEND} ? $ENV{MATH_INT64_BACKEND}
        : $Config::Config{ivsize} >= 8     ? 'IV'
        : $Config::Config{doublesize} >= 8 ? 'NV'
        :                                    die <<'EOF';
Unable to find a suitable representation for int64 on your system.
Your Perl must have ivsize >= 8 or doublesize >= 8.
EOF

    return '-DINT64_BACKEND_' . $backend;
}
