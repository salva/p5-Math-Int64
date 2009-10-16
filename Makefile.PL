
use ExtUtils::MakeMaker;

use Config;

my $backend;

if ($Config::Config{ivsize} == 8) {
    $backend = 'NATIVE';
}
elsif ($Config::Config{doublesize} == 8) {
    $backend = 'DOUBLE';
}
else {
    $backend = 'STRING';
}

# we force the DOUBLE backend for the moment...
$backend = 'DOUBLE';

unless ($Config{i64type} and
        $Config{i64size} == 8 and
	($Config{d_int64_t} or $^O =~ /MSWin32/i)) {
    die "Your C compiler does not have enough support for int64 values\n";
}

my @define = ("INT64_BACKEND_" . $backend);

for (qw(strtoll strtoull atoll atoull)) {
    push @define, "INT64_HAS_" . uc $_
        if $Config{"d_$_"};
}

my $define = join (' ', map { "-D$_" } @define);

WriteMakefile( NAME              => 'Math::Int64',
               VERSION_FROM      => 'lib/Math/Int64.pm',
               PREREQ_PM         => {},
               ABSTRACT_FROM  => 'lib/Math/Int64.pm', # retrieve abstract from module
               AUTHOR         => 'Salvador Fandino <sfandino@yahoo.com>',
               LIBS              => [''], # e.g., '-lm'
               DEFINE            => $define,
               INC               => '-I.', # e.g., '-I. -I/usr/include/other'
    );
