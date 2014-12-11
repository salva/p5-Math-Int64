package Config::AutoConf;

use warnings;
use strict;

use base 'Exporter';

our @EXPORT = ('$LIBEXT', '$EXEEXT');

use constant QUOTE => do { $^O eq "MSWin32" ? q["] : q['] };

use ExtUtils::CBuilder;

use Config;
use Carp qw/croak/;

use File::Temp qw/tempfile/;
use File::Basename;
use File::Spec;
use Text::ParseWords qw//;

use Capture::Tiny qw/capture/;

# in core since 5.7.3
eval "use Scalar::Util qw/looks_like_number/;";
__PACKAGE__->can("looks_like_number") or eval <<'EOP';
=begin private

=head2 looks_like_number

=end private

=cut

# from PP part of Params::Util
sub looks_like_number {
    local $_ = shift;

    # checks from perlfaq4
    return 0 if !defined($_);
    if (ref($_)) {
        return overload::Overloaded($_) ? defined(0 + $_) : 0;
    }
    return 1 if (/^[+-]?[0-9]+$/); # is a +/- integer
    return 1 if (/^([+-]?)(?=[0-9]|\.[0-9])[0-9]*(\.[0-9]*)?([Ee]([+-]?[0-9]+))?$/); # a C float
    return 1 if ($] >= 5.008 and /^(Inf(inity)?|NaN)$/i) or ($] >= 5.006001 and /^Inf$/i);

    0;
}
EOP

eval "use File::Slurp::Tiny qw/read_file/;";
__PACKAGE__->can("read_file") or eval <<'EOP';
=begin private

=head2 read_file

=end private

=cut

sub read_file {
  my $fn = shift;
  local $@ = "";
  open( my $fh, "<", $fn ) or croak "Error opening $fn: $!";
  my $fc = <$fh>;
  close($fh) or croak "I/O error closing $fn: $!";
  return $fc;
}
EOP

# PA-RISC1.1-thread-multi
my %special_dlext = (
  darwin => ".dylib",
  MSWin32 => ".dll",
  ($Config{archname} =~ m/PA-RISC/i ? ("hpux" => ".sl") : ()),
);

our ($LIBEXT, $EXEEXT);

defined $LIBEXT
  or $LIBEXT = defined $Config{so} ? "." . $Config{so} :
               defined $special_dlext{$^O} ? $special_dlext{$^O} : ".so";
defined $EXEEXT
  or $EXEEXT = ($^O eq "MSWin32") ? ".exe" : "";

=encoding UTF-8

=head1 NAME

Config::AutoConf - A module to implement some of AutoConf macros in pure perl.

=cut

our $VERSION = '0.305';

=head1 ABSTRACT

With this module I pretend to simulate some of the tasks AutoConf
macros do. To detect a command, to detect a library, etc.

=head1 SYNOPSIS

    use Config::AutoConf;

    Config::AutoConf->check_prog("agrep");
    my $grep = Config::AutoConf->check_progs("agrep", "egrep", "grep");

    Config::AutoConf->check_header("ncurses.h");
    my $curses = Config::AutoConf->check_headers("ncurses.h","curses.h");

    Config::AutoConf->check_prog_awk;
    Config::AutoConf->check_prog_egrep;

    Config::AutoConf->check_cc();

    Config::AutoConf->check_lib("ncurses", "tgoto");

    Config::AutoConf->check_file("/etc/passwd"); # -f && -r

=head1 FUNCTIONS

=cut

my $glob_instance;

=head2 new

This function instantiates a new instance of Config::AutoConf, eg. to
configure child components. The contructor adds also values set via
environment variable C<PERL5_AUTOCONF_OPTS>.

=cut

sub new {
  my $class = shift;
  ref $class and $class = ref $class;
  my %args = @_;

  my %flags = map {
    my ($k, $v) = split("=", $_, 2); defined $v or $v = 1; ($k, $v)
  } split( ":", $ENV{PERL5_AUTOCONF_OPTS} ) if($ENV{PERL5_AUTOCONF_OPTS});

  my %instance = (
    msg_prefix => 'configure: ',
    lang => "C",
    lang_stack => [],
    lang_supported => {
      "C" => "ExtUtils::CBuilder",
    },
    cache => {},
    defines => {},
    extra_libs => [],
    extra_lib_dirs => [],
    extra_include_dirs => [],
    extra_preprocess_flags => [],
    extra_compile_flags => {
      "C" => [],
    },
    extra_link_flags => [],
    logfile => "config.log",
    c_ac_flags => {%flags},
    %args
  );
  bless( \%instance, $class );
}

=head2 check_file

This function checks if a file exists in the system and is readable by
the user. Returns a boolean. You can use '-f $file && -r $file' so you
don't need to use a function call.

=cut

sub check_file {
  my ($self, $file) = @_;
  -f $file && -r $file;
}


=head2 check_files

This function checks if a set of files exist in the system and are
readable by the user. Returns a boolean.

=cut

sub check_files {
  my $self = shift;

  for (@_) {
    return 0 unless $self->check_file($_)
  }

  1;
}

sub _sanitize_prog {
  my ($self, $prog) = @_;
  (scalar Text::ParseWords::shellwords $prog) > 1 and $prog = QUOTE . $prog . QUOTE;
  $prog;
}

my @exe_exts = ( $^O eq "MSWin32" ? qw(.exe .com .bat .cmd) : ("") );

=head2 check_prog(prog,[dirlist])

This function checks for a program with the supplied name. In success
returns the full path for the executable;

An optional array reference containing a list of directories to be searched
instead of $PATH is gracefully honored.

=cut

sub check_prog {
  my $self = shift;
  # sanitize ac_prog
  my $ac_prog = _sanitize(shift @_);
  my @dirlist;
  @_ and scalar @_ > 1 and @dirlist = @_;
  @_ and scalar @_ == 1 and ref $_[0] eq "ARRAY" and @dirlist = @{$_[0]};
  @dirlist or @dirlist = split(/$Config{path_sep}/,$ENV{PATH});

  for my $p (@dirlist) {
    for my $e (@exe_exts) {
      my $cmd = $self->_sanitize_prog(File::Spec->catfile($p,$ac_prog.$e));
      return $cmd if -x $cmd;
    }
  }
  return;
}

=head2 check_progs(progs, [dirlist])

This function takes a list of program names. Returns the full path for
the first found on the system. Returns undef if none was found.

An optional array reference containing a list of directories to be searched
instead of $PATH is gracefully honored.

=cut

sub check_progs {
  my $self = shift;
  my @dirlist;
  scalar @_ > 1 and ref $_[-1] eq "ARRAY" and @dirlist = @{pop @_};
  @dirlist or @dirlist = split(/$Config{path_sep}/,$ENV{PATH});

  my @progs = @_;
  for (@progs) {
    defined $_ or next;
    my $ans = $self->check_prog($_, \@dirlist);
    return $ans if $ans;
  }
  return;
}

sub _append_prog_args {
  my ($self, $prog) = @_;
  join(" ", $self->_sanitize_prog($prog), @_);
}

=head2 check_prog_yacc

From the autoconf documentation,

  If `bison' is found, set [...] `bison -y'.
  Otherwise, if `byacc' is found, set [...] `byacc'. 
  Otherwise set [...] `yacc'.  The result of this test can be influenced
  by setting the variable YACC or the cache variable ac_cv_prog_YACC.

Returns the full path, if found.

=cut

sub check_prog_yacc {
  my $self = shift;

# my ($self, $cache_name, $message, $check_sub) = @_;

  my $cache_name = $self->_cache_name("prog", "YACC");
  $self->check_cached( $cache_name, "for yacc",
    sub {
      defined $ENV{YACC} and return $ENV{YACC};
      my $binary = $self->check_progs(qw/bison byacc yacc/);
      defined $binary and $binary =~ /bison(?:\.(?:exe|com|bat|cmd))?$/
        and $binary = $self->_append_prog_args($binary, "-y");
      return $binary;
    } );
}

=head2 check_prog_awk

From the autoconf documentation,

  Check for `gawk', `mawk', `nawk', and `awk', in that order, and
  set output [...] to the first one that is found.  It tries
  `gawk' first because that is reported to be the best implementation.
  The result can be overridden by setting the variable AWK or the
  cache variable ac_cv_prog_AWK.

Note that it returns the full path, if found.

=cut

sub check_prog_awk {
  my $self = shift;
  my $cache_name = $self->_cache_name("prog", "AWK");
  $self->check_cached( $cache_name, "for awk",
    sub {$ENV{AWK} || $self->check_progs(qw/gawk mawk nawk awk/)} );
}


=head2 check_prog_egrep

From the autoconf documentation,

  Check for `grep -E' and `egrep', in that order, and [...] output
  [...] the first one that is found.  The result can be overridden by
  setting the EGREP variable and is cached in the ac_cv_path_EGREP
  variable. 

Note that it returns the full path, if found.

=cut

sub check_prog_egrep {
  my $self = shift;

  my $cache_name = $self->_cache_name("prog", "EGREP");
  $self->check_cached( $cache_name, "for egrep",
    sub {
      defined $ENV{EGREP} and return $ENV{EGREP};
      my $grep;
      $grep = $self->check_progs("egrep") and return $grep;

      if ($grep = $self->check_prog("grep")) {
        # check_run - Capture::Tiny, Open3 ... ftw!
        my $ans = `echo a | ($grep -E '(a|b)') 2>/dev/null`;
        chomp $ans;
        $ans eq "a" and return $self->_append_prog_args($grep,  "-E");
      }
    } );
}

=head2 check_prog_lex

From the autoconf documentation,

  If flex is found, set output [...] to ‘flex’ and [...] to -lfl, if that
  library is in a standard place. Otherwise set output [...] to ‘lex’ and
  [...] to -ll, if found. If [...] packages [...] ship the generated
  file.yy.c alongside the source file.l, this [...] allows users without a
  lexer generator to still build the package even if the timestamp for
  file.l is inadvertently changed.

Note that it returns the full path, if found.

The structure $self->{lex} is set with attributes

  prog => $LEX
  lib => $LEXLIB
  root => $lex_root

=cut

sub check_prog_lex {
  my $self = shift->_get_instance;
  my $cache_name = $self->_cache_name("prog", "LEX");
  my $lex = $self->check_cached( $cache_name, "for lex",
    sub {$ENV{LEX} || $self->check_progs(qw/flex lex/)} );
  if($lex) {
    defined $self->{lex}->{prog} or $self->{lex}->{prog} = $lex;
    my $lex_root_var = $self->check_cached( "ac_cv_prog_lex_root", "for lex output file root",
      sub {
        my ($fh, $filename) = tempfile( "testXXXXXX", SUFFIX => '.l');
        my $src = <<'EOLEX';
%%
a { ECHO; }
b { REJECT; }
c { yymore (); }
d { yyless (1); }
e { /* IRIX 6.5 flex 2.5.4 underquotes its yyless argument.  */
    yyless ((input () != 0)); }
f { unput (yytext[0]); }
. { BEGIN INITIAL; }
%%
#ifdef YYTEXT_POINTER
extern char *yytext;
#endif
int
main (void)
{
  return ! yylex () + ! yywrap ();
}
EOLEX

        print {$fh} $src;
        close $fh;

        my ( $stdout, $stderr, $exit ) =
          capture { system( $lex, $filename ); };
        chomp $stdout;
        unlink $filename;
        -f "lex.yy.c" and return "lex.yy";
        -f "lexyy.c" and return "lexyy";
        $self->msg_error("cannot find output from $lex; giving up");
      });
    defined $self->{lex}->{root} or $self->{lex}->{root} = $lex_root_var;

    my $conftest = read_file($lex_root_var.".c");
    unlink $lex_root_var.".c";

    $cache_name = $self->_cache_name( "lib", "lex" );
    my $check_sub = sub {
      my @save_libs = @{$self->{extra_libs}};
      my $have_lib = 0;
      foreach my $libstest ( undef, qw(-lfl -ll) ) {
        # XXX would local work on array refs? can we omit @save_libs?
        $self->{extra_libs} = [ @save_libs ];
        defined( $libstest ) and unshift( @{$self->{extra_libs}}, $libstest );
        $self->link_if_else( $conftest )
          and ( $have_lib = defined( $libstest ) ? $libstest : "none required" )
          and last;
      }
      $self->{extra_libs} = [ @save_libs ];

      if( $have_lib ) {
        $self->define_var( _have_lib_define_name( "lex" ), $have_lib,
                           "defined when lex library is available" );
      }
      else {
        $self->define_var( _have_lib_define_name( "lex" ), undef,
                           "defined when lex library is available" );
      }
      return $have_lib;
    };

    my $lex_lib = $self->check_cached( $cache_name, "lex library", $check_sub );
    defined $self->{lex}->{lib} or $self->{lex}->{lib} = $lex_lib;
  }

  $lex;
}


=head2 check_prog_sed

From the autoconf documentation,

  Set output variable [...] to a Sed implementation that conforms to Posix
  and does not have arbitrary length limits. Report an error if no
  acceptable Sed is found. See Limitations of Usual Tools, for more
  information about portability problems with Sed.

  The result of this test can be overridden by setting the SED variable and
  is cached in the ac_cv_path_SED variable. 

Note that it returns the full path, if found.

=cut

sub check_prog_sed {
  my $self = shift;
  my $cache_name = $self->_cache_name("prog", "SED");
  $self->check_cached( $cache_name, "for sed",
    sub {$ENV{SED} || $self->check_progs(qw/gsed sed/)} );
}


=head2 check_prog_pkg_config

Checks for C<pkg-config> program. No additional tests are made for it ...

=cut
 
sub check_prog_pkg_config {
  my $self = shift->_get_instance();
  my $cache_name = $self->_cache_name("prog", "PKG_CONFIG");
  $self->check_cached( $cache_name, "for pkg-config",
    sub {$self->check_prog("pkg-config")} );
}

=head2 check_cc

This function checks if you have a running C compiler.

=cut

sub check_cc {
  ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
}

=head2 msg_checking

Prints "Checking @_ ..."

=cut

sub msg_checking {
  my $self = shift->_get_instance();
  $self->{quiet} or
    print "Checking " . join(" ", @_) . "... ";
  $self->_add_log_entry( "Checking " . join( " ", @_, "..." ) );
  return;
}

=head2 msg_result

Prints result \n

=cut

my @_num_to_msg = qw/no yes/;

sub _neat
{
  defined $_[0] or return "";
  looks_like_number( $_[0] ) and defined $_num_to_msg[$_[0]] and return $_num_to_msg[$_[0]];
  $_[0];
}

sub msg_result {
  my $self = shift->_get_instance();
  $self->{quiet} or
    print join( " ", map { _neat $_ } @_ ), "\n";
  $self->_add_log_entry( join( " ", map { _neat $_ } @_ ), "\n" );
  return;
}

=head2 msg_notice

Prints "configure: " @_ to stdout

=cut

sub msg_notice {
  my $self = shift->_get_instance();
  $self->{quiet} or
    print $self->{msg_prefix} . join( " ", @_ ) . "\n";
  $self->_add_log_entry( $self->{msg_prefix} . join( " ", @_ ) . "\n" );
  return;
}

=head2 msg_warn

Prints "configure: " @_ to stderr

=cut

sub msg_warn {
  my $self = shift->_get_instance();
  print STDERR $self->{msg_prefix} . join( " ", @_ ) . "\n";
  $self->_add_log_entry( "WARNING: " . $self->{msg_prefix} . join( " ", @_ ) . "\n" );
  return;
}

=head2 msg_error

Prints "configure: " @_ to stderr and exits with exit code 0 (tells
toolchain to stop here and report unsupported environment)

=cut

sub msg_error {
  my $self = shift->_get_instance();
  print STDERR $self->{msg_prefix} . join( " ", @_ ) . "\n";
  $self->_add_log_entry( "ERROR: " . $self->{msg_prefix} . join( " ", @_ ) . "\n" );
  exit(0); # #toolchain agreement: prevents configure stage to finish
}

=head2 msg_failure

Prints "configure: " @_ to stderr and exits with exit code 0 (tells
toolchain to stop here and report unsupported environment). Additional
details are provides in config.log (probably more information in a
later stage).

=cut

sub msg_failure {
  my $self = shift->_get_instance();
  print STDERR $self->{msg_prefix} . join( " ", @_ ) . "\n";
  $self->_add_log_entry( "FAILURE: " . $self->{msg_prefix} . join( " ", @_ ) . "\n" );
  exit(0); # #toolchain agreement: prevents configure stage to finish
}

=head2 define_var( $name, $value [, $comment ] )

Defines a check variable for later use in further checks or code to compile.

=cut

sub define_var {
  my $self = shift->_get_instance();
  my ($name, $value, $comment) = @_;

  defined( $name ) or croak( "Need a name to add a define" );

  $self->{defines}->{$name} = [ $value, $comment ];

  return;
}

=head2 write_config_h( [$target] )

Writes the defined constants into given target:

  Config::AutoConf->write_config_h( "config.h" );

=cut

sub write_config_h {
  my $self = shift->_get_instance();
  my $tgt;
  
  defined( $_[0] )
    ? ( ref( $_[0] )
      ? $tgt = $_[0]
      : open( $tgt, ">", $_[0] ) )
    : open( $tgt, ">", "config.h" );

  my $conf_h = <<'EOC';
/**
 * Generated from Config::AutoConf
 *
 * Do not edit this file, all modifications will be lost,
 * modify Makefile.PL or Build.PL instead.
 *
 * Inspired by GNU AutoConf.
 *
 * (c) 2011 Alberto Simoes & Jens Rehsack
 */
#ifndef __CONFIG_H__

EOC

  while( my ($defname, $defcnt) = each( %{ $self->{defines} } ) ) {
    if( $defcnt->[0] ) {
      defined $defcnt->[1] and $conf_h .= "/* " . $defcnt->[1] . " */\n";
      $conf_h .= join( " ", "#define", $defname, $defcnt->[0] ) . "\n";
    }
    else {
      defined $defcnt->[1] and $conf_h .= "/* " . $defcnt->[1] . " */\n";
      $conf_h .= "/* " . join( " ", "#undef", $defname ) . " */\n\n";
    }
  }
  $conf_h .= "#endif /* ?__CONFIG_H__ */\n";

  print {$tgt} $conf_h;

  return;
}

=head2 push_lang(lang [, implementor ])

Puts the current used language on the stack and uses specified language
for subsequent operations until ending pop_lang call.

=cut

sub push_lang {
  my $self = shift->_get_instance();

  push @{$self->{lang_stack}}, [ $self->{lang} ];

  $self->_set_language( @_ );
}

=head2 pop_lang([ lang ])

Pops the currently used language from the stack and restores previously used
language. If I<lang> specified, it's asserted that the current used language
equals to specified language (helps finding control flow bugs).

=cut

sub pop_lang {
  my $self = shift->_get_instance();

  scalar( @{$self->{lang_stack}} ) > 0 or croak( "Language stack empty" );
  defined( $_[0] ) and $self->{lang} ne $_[0] and
    croak( "pop_lang( $_[0] ) doesn't match language in use (" . $self->{lang} . ")" );

  $self->_set_language( @{ pop @{ $self->{lang} } } );
}

=head2 lang_call( [prologue], function )

Builds program which simply calls given function.
When given, prologue is prepended otherwise, the default
includes are used.

=cut

sub lang_call {
  my ($self, $prologue, $function) = @_;
  ref $self or $self = $self->_get_instance();

  defined( $prologue ) or $prologue = $self->_default_includes();
  $prologue .= <<"_ACEOF";
/* Override any GCC internal prototype to avoid an error.
   Use char because int might match the return type of a GCC
   builtin and then its argument prototype would still apply.  */
#ifdef __cplusplus
extern "C" {
#endif
char $function ();
#ifdef __cplusplus
}
#endif
_ACEOF
  my $body = "return $function ();";
  $body = $self->_build_main( $body );

  $self->_fill_defines() . "\n$prologue\n\n$body\n";
}

=head2 lang_build_program( prologue, body )

Builds program for current chosen language. If no prologue is given
(I<undef>), the default headers are used. If body is missing, default
body is used.

Typical call of

  Config::AutoConf->lang_build_program( "const char hw[] = \"Hello, World\\n\";",
                                        "fputs (hw, stdout);" )

will create

  const char hw[] = "Hello, World\n";

  /* Override any gcc2 internal prototype to avoid an error.  */
  #ifdef __cplusplus
  extern "C" {
  #endif

  int
  main (int argc, char **argv)
  {
    (void)argc;
    (void)argv;
    fputs (hw, stdout);;
    return 0;
  }

  #ifdef __cplusplus
  }
  #endif

=cut

sub lang_build_program {
  my ($self, $prologue, $body) = @_;
  ref $self or $self = $self->_get_instance();

  defined( $prologue ) or $prologue = $self->_default_includes();
  defined( $body ) or $body = "";
  $body = $self->_build_main( $body );

  $self->_fill_defines() . "\n$prologue\n\n$body\n";
}

=head2 lang_build_bool_test (prologue, test, [@decls])

Builds a static test which will fail to compile when test
evaluates to false. If C<@decls> is given, it's prepended
before the test code at the variable definition place.

=cut

sub lang_build_bool_test {
  my ($self, $prologue, $test, @decls) = @_;
  ref $self or $self = $self->_get_instance();

  defined( $test ) or $test = "1";
  my $test_code = <<ACEOF;
  static int test_array [($test) ? 1 : -1 ];
  test_array [0] = 0
ACEOF
  if( @decls ) {
    $test_code = join( "\n", @decls, $test_code );
  }
  $self->lang_build_program( $prologue, $test_code );
}

=head2 push_includes

Adds given list of directories to preprocessor/compiler
invocation. This is not proved to allow adding directories
which might be created during the build.

=cut

sub push_includes {
  my ($self, @includes) = @_;
  ref $self or $self = $self->_get_instance();

  push( @{$self->{extra_include_dirs}}, @includes );

  return;
}

=head2 push_preprocess_flags

Adds given flags to the parameter list for preprocessor invocation.

=cut

sub push_preprocess_flags {
  my ($self, @cpp_flags) = @_;
  ref $self or $self = $self->_get_instance();

  push( @{$self->{extra_preprocess_flags}}, @cpp_flags );

  return;
}

=head2 push_compiler_flags

Adds given flags to the parameter list for compiler invocation.

=cut

sub push_compiler_flags {
  my ($self, @compiler_flags) = @_;
  ref $self or $self = $self->_get_instance();
  my $lang = $self->{lang};

  if( scalar( @compiler_flags ) && ( ref($compiler_flags[-1]) eq "HASH" ) ) {
    my $lang_opt = pop( @compiler_flags );
    defined( $lang_opt->{lang} ) or croak( "Missing lang attribute in language options" );
    $lang = $lang_opt->{lang};
    defined( $self->{lang_supported}->{$lang} ) or croak( "Unsupported language '$lang'" );
  }

  push( @{$self->{extra_compile_flags}->{$lang}}, @compiler_flags );

  return;
}

=head2 push_libraries

Adds given list of libraries to the parameter list for linker invocation.

=cut

sub push_libraries {
  my ($self, @libs) = @_;
  ref $self or $self = $self->_get_instance();

  push( @{$self->{extra_libs}}, @libs );

  return;
}

=head2 push_library_paths

Adds given list of library paths to the parameter list for linker invocation.

=cut

sub push_library_paths {
  my ($self, @libdirs) = @_;
  ref $self or $self = $self->_get_instance();

  push( @{$self->{extra_lib_dirs}}, @libdirs );

  return;
}

=head2 push_link_flags

Adds given flags to the parameter list for linker invocation.

=cut

sub push_link_flags {
  my ($self, @link_flags) = @_;
  ref $self or $self = $self->_get_instance();

  push( @{$self->{extra_link_flags}}, @link_flags );

  return;
}

=head2 compile_if_else( $src [, action-if-true [, action-if-false ] ] )

This function trys to compile specified code and runs action-if-true on success
or action-if-false otherwise.

Returns a boolean value containing check success state.

=cut

sub compile_if_else {
  my ($self, $src, $action_if_true, $action_if_false) = @_;
  ref $self or $self = $self->_get_instance();
  my $builder = $self->_get_builder();

  my ($fh, $filename) = tempfile("testXXXXXX", SUFFIX => '.c', , UNLINK => 0);

  print {$fh} $src;
  close $fh;

  my ($obj_file, $outbuf, $errbuf, $exception);
  ($outbuf, $errbuf) = capture {
    eval {
      $obj_file = $builder->compile(
        source => $filename,
        include_dirs => $self->{extra_include_dirs},
        extra_compiler_flags => $self->_get_extra_compiler_flags() );
    };

    $exception = $@;
  };

  unlink $filename;
  unlink $obj_file if $obj_file;

  if ($exception || !$obj_file) {
    $self->_add_log_lines( "compile stage failed" . ( $exception ? " - " . $exception : "" ) );
    $errbuf and
      $self->_add_log_lines( $errbuf );
    $self->_add_log_lines( "failing program is:\n" . $src );
    $outbuf and
      $self->_add_log_lines( "stdout was :\n" . $outbuf );

    defined( $action_if_false ) and "CODE" eq ref( $action_if_false ) and &{$action_if_false}();
    return 0;
  }

  defined( $action_if_true ) and "CODE" eq ref( $action_if_true ) and &{$action_if_true}();
  1;
}

=head2 link_if_else( $src [, action-if-true [, action-if-false ] ] )

This function trys to compile and link specified code and runs action-if-true on success
or action-if-false otherwise.

Returns a boolean value containing check success state.

=cut

sub link_if_else {
  my ($self, $src, $action_if_true, $action_if_false) = @_;
  ref $self or $self = $self->_get_instance();
  my $builder = $self->_get_builder();

  my ($fh, $filename) = tempfile( "testXXXXXX", SUFFIX => '.c');

  print {$fh} $src;
  close $fh;

  my ($obj_file, $outbuf, $errbuf, $exception);
  ($outbuf, $errbuf) = capture {
    eval {
      $obj_file = $builder->compile(
        source => $filename,
        include_dirs => $self->{extra_include_dirs},
        extra_compiler_flags => $self->_get_extra_compiler_flags() );
    };

    $exception = $@;
  };

  if ($exception || !$obj_file) {
    $self->_add_log_lines( "compile stage failed" . ( $exception ? " - " . $exception : "" ) );
    $errbuf and
      $self->_add_log_lines( $errbuf );
    $self->_add_log_lines( "failing program is:\n" . $src );
    $outbuf and
      $self->_add_log_lines( "stdout was :\n" . $outbuf );

    unlink $filename;
    unlink $obj_file if $obj_file;
    defined( $action_if_false ) and "CODE" eq ref( $action_if_false ) and &{$action_if_false}();
    return 0;
  }

  my $exe_file;
  ($outbuf, $errbuf) = capture {
    eval {
      $exe_file = $builder->link_executable(
        objects => $obj_file,
        extra_linker_flags => $self->_get_extra_linker_flags() );
    };

    $exception = $@;
  };
  unlink $filename;
  unlink $obj_file if $obj_file;
  unlink $exe_file if $exe_file;

  if ($exception || !$exe_file) {
    $self->_add_log_lines( "link stage failed" . ( $exception ? " - " . $exception : "" ) );
    $errbuf and
      $self->_add_log_lines( $errbuf );
    $self->_add_log_lines( "failing program is:\n" . $src );
    $outbuf and
      $self->_add_log_lines( "stdout was :\n" . $outbuf );

    defined( $action_if_false ) and "CODE" eq ref( $action_if_false ) and &{$action_if_false}();
    return 0;
  }

  defined( $action_if_true ) and "CODE" eq ref( $action_if_true ) and &{$action_if_true}();
  1;
}

=head2 check_cached( cache-var, message, sub-to-check )

This function checks whether a specified cache variable is set or not, and if not
it's going to set it using specified sub-to-check.

=cut

sub check_cached {
  my ($self, $cache_name, $message, $check_sub) = @_;
  ref $self or $self = $self->_get_instance();

  $self->msg_checking( $message );

  defined $ENV{$cache_name} and not defined $self->{cache}->{$cache_name}
    and $self->{cache}->{$cache_name} = $ENV{$cache_name};

  if( defined($self->{cache}->{$cache_name}) ) {
    $self->msg_result( "(cached)", $self->{cache}->{$cache_name} );
  }
  else {
    $self->{cache}->{$cache_name} = &{$check_sub}();
    $self->msg_result( $self->{cache}->{$cache_name} );
  }

  $self->{cache}->{$cache_name};
}

=head2 cache_val

This functions returns the value of a previously check_cached call.

=cut

sub cache_val {
  my ($self, $cache_name) = @_;
  ref $self or $self = $self->_get_instance();
  defined $self->{cache}->{$cache_name} or return;
  $self->{cache}->{$cache_name};
}

=head2 check_decl( symbol, [action-if-found], [action-if-not-found], [prologue = default includes] )

If symbol (a function, variable or constant) is not declared in includes and
a declaration is needed, run the code ref given in I<action-if-not-found>,
otherwise I<action-if-found>. includes is a series of include directives,
defaulting to I<default includes>, which are used prior to the declaration
under test.

This method actually tests whether symbol is defined as a macro or can be
used as an r-value, not whether it is really declared, because it is much
safer to avoid introducing extra declarations when they are not needed.
In order to facilitate use of C++ and overloaded function declarations, it
is possible to specify function argument types in parentheses for types
which can be zero-initialized:

          Config::AutoConf->check_decl("basename(char *)")

This method caches its result in the C<ac_cv_decl_E<lt>set langE<gt>>_symbol variable.

=cut

sub check_decl {
  my ($self, $symbol, $action_if_found, $action_if_not_found, $prologue) = @_;
  $self = $self->_get_instance();
  defined( $symbol ) or return; # XXX prefer croak
  ref( $symbol ) eq "" or return;
  ( my $sym_plain = $symbol ) =~ s/ *\(.*//;
  my $sym_call = $symbol;
  $sym_call =~ s/\(/((/;
  $sym_call =~ s/\)/) 0)/;
  $sym_call =~ s/,/) 0, (/g;

  my $cache_name = $self->_cache_name( "decl", $self->{lang}, $symbol );
  my $check_sub = sub {
  
    my $body = <<ACEOF;
#ifndef $sym_plain
  (void) $sym_call;
#endif
ACEOF
    my $conftest = $self->lang_build_program( $prologue, $body );

    my $have_decl = $self->compile_if_else( $conftest );
    if( $have_decl ) {
      if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
	&{$action_if_found}();
      }
    }
    else {
      if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
	&{$action_if_not_found}();
      }
    }

    $have_decl;
  };

  $self->check_cached( $cache_name, "whether $symbol is declared", $check_sub );
}

=head2 check_decls( symbols, [action-if-found], [action-if-not-found], [prologue = default includes] )

For each of the symbols (with optional function argument types for C++
overloads), run L<check_decl>. If I<action-if-not-found> is given, it
is additional code to execute when one of the symbol declarations is
needed, otherwise I<action-if-found> is executed.

Contrary to GNU autoconf, this method does not declare HAVE_DECL_symbol
macros for the resulting C<confdefs.h>, because it differs as C<check_decl>
between compiling languages.

=cut

sub check_decls {
  my ($self, $symbols, $action_if_found, $action_if_not_found, $prologue) = @_;
  $self = $self->_get_instance();

  my $have_syms = 1;
  foreach my $symbol (@$symbols) {
    $have_syms &= $self->check_decl( $symbol, undef, undef, $prologue );
  }

  if( $have_syms ) {
    if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
      &{$action_if_found}();
    }
  }
  else {
    if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
      &{$action_if_not_found}();
    }
  }

  $have_syms;
}

sub _have_type_define_name {
  my $type = $_[0];
  my $have_name = "HAVE_" . uc($type);
  $have_name =~ tr/*/P/;
  $have_name =~ tr/_A-Za-z0-9/_/c;
  $have_name;
}

=head2 check_type (type, [action-if-found], [action-if-not-found], [prologue = default includes])

Check whether type is defined. It may be a compiler builtin type or defined
by the includes. I<prologue> should be a series of include directives,
defaulting to I<default includes>, which are used prior to the type under
test.

In C, type must be a type-name, so that the expression C<sizeof (type)> is
valid (but C<sizeof ((type))> is not)

If I<type> type is defined, preprocessor macro HAVE_I<type> (in all
capitals, with "*" replaced by "P" and spaces and dots replaced by
underscores) is defined.

This method caches its result in the C<ac_cv_type_>type variable.

=cut

sub check_type {
  my ($self, $type, $action_if_found, $action_if_not_found, $prologue) = @_;
  $self = $self->_get_instance();
  defined $type or return; # XXX prefer croak
  ref $type eq "" or return;

  my $cache_name = $self->_cache_type_name( "type", $type );
  my $check_sub = sub {
  
    my $body = <<ACEOF;
  if( sizeof ($type) )
    return 0;
ACEOF
    my $conftest = $self->lang_build_program( $prologue, $body );

    my $have_type = $self->compile_if_else( $conftest );
    $self->define_var( _have_type_define_name( $type ), $have_type ? $have_type : undef, "defined when $type is available" );
    if( $have_type ) {
      if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
	&{$action_if_found}();
      }
    }
    else {
      if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
	&{$action_if_not_found}();
      }
    }

    $have_type;
  };

  $self->check_cached( $cache_name, "for $type", $check_sub );
}

=head2 check_types (types, [action-if-found], [action-if-not-found], [prologue = default includes])

For each type L<check_type> is called to check for type.

If I<action-if-found> is given, it is additionally executed when all of the
types are found. If I<action-if-not-found> is given, it is executed when one
of the types is not found.

=cut

sub check_types {
  my ($self, $types, $action_if_found, $action_if_not_found, $prologue) = @_;
  $self = $self->_get_instance();

  my $have_types = 1;
  foreach my $type (@$types) {
    $have_types &= $self->check_type( $type, undef, undef, $prologue );
  }

  if( $have_types ) {
    if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
      &{$action_if_found}();
    }
  }
  else {
    if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
      &{$action_if_not_found}();
    }
  }

  $have_types;
}

sub _compute_int_compile {
  my ($self, $expr, $prologue, @decls) = @_;
  $self = $self->_get_instance();

  my( $body, $conftest, $compile_result );

  my ($low, $mid, $high) = (0, 0, 0);
  if( $self->compile_if_else( $self->lang_build_bool_test( $prologue, "((long int)($expr)) >= 0", @decls ) ) ) {
    $low = $mid = 0;
    while( 1 ) {
      if( $self->compile_if_else( $self->lang_build_bool_test( $prologue, "((long int)($expr)) <= $mid", @decls ) ) ) {
	$high = $mid;
	last;
      }
      $low = $mid + 1;
      # avoid overflow
      if( $low <= $mid ) {
	$low = 0;
	last;
      }
      $mid = $low * 2;
    }
  }
  elsif( $self->compile_if_else( $self->lang_build_bool_test( $prologue, "((long int)($expr)) < 0", @decls ) ) ) {
    $high = $mid = -1;
    while( 1 ) {
      if( $self->compile_if_else( $self->lang_build_bool_test( $prologue, "((long int)($expr)) >= $mid", @decls ) ) ) {
	$low = $mid;
	last;
      }
      $high = $mid - 1;
      # avoid overflow
      if( $mid < $high ) {
	$high = 0;
	last;
      }
      $mid = $high * 2;
    }
  }

  # perform binary search between $low and $high
  while( $low <= $high ) {
    $mid = int( ( $high - $low ) / 2 + $low );
    if( $self->compile_if_else( $self->lang_build_bool_test( $prologue, "((long int)($expr)) < $mid", @decls ) ) ) {
      $high = $mid - 1;
    }
    elsif( $self->compile_if_else( $self->lang_build_bool_test( $prologue, "((long int)($expr)) > $mid", @decls ) ) ) {
      $low = $mid + 1;
    }
    else {
      return $mid;
    }
  }

  return;
}

=head2 compute_int (expression, [action-if-fails], [prologue = default includes], [@decls])

Returns the value of the integer I<expression>. The value should fit in an
initializer in a C variable of type signed long.  It should be possible
to evaluate the expression at compile-time. If no includes are specified,
the default includes are used.

Execute I<action-if-fails> if the value cannot be determined correctly.

=cut

sub compute_int {
  my ($self, $expr, $action_if_fails, $prologue, @decls) = @_;
  $self = $self->_get_instance();

  my $cache_name = $self->_cache_type_name( "compute_int", $self->{lang}, $expr );
  my $check_sub = sub {

    my $val = $self->_compute_int_compile( $expr, $prologue, @decls);
    unless( defined( $val ) ) {
      if( defined( $action_if_fails ) and "CODE" eq ref( $action_if_fails ) ) {
	&{$action_if_fails}();
      }
    }

    $val;
  };

  $self->check_cached( $cache_name, "for compute result of ($expr)", $check_sub );
}

sub _sizeof_type_define_name {
  my $type = $_[0];
  my $have_name = "SIZEOF_" . uc($type);
  $have_name =~ tr/*/P/;
  $have_name =~ tr/_A-Za-z0-9/_/c;
  $have_name;
}

=head2 check_sizeof_type (type, [action-if-found], [action-if-not-found], [prologue = default includes])

Checks for the size of the specified type by compiling. If no size can
determined, I<action-if-not-found> is invoked when given. Otherwise
I<action-if-found> is invoked and C<SIZEOF_type> is defined using the
determined size.

In opposition to GNU AutoConf, this method can determine size of structure
members, eg.

  $ac->check_sizeof_type( "SV.sv_refcnt", undef, undef, $include_perl );
  # or
  $ac->check_sizeof_type( "struct utmpx.ut_id", undef, undef, "#include <utmpx.h>" );

This method caches its result in the C<ac_cv_sizeof_E<lt>set langE<gt>>_type variable.

=cut

sub check_sizeof_type {
  my ($self, $type, $action_if_found, $action_if_not_found, $prologue) = @_;
  $self = $self->_get_instance();
  defined( $type ) or return; # XXX prefer croak
  ref( $type ) eq "" or return;

  my $cache_name = $self->_cache_type_name( "sizeof", $self->{lang}, $type );
  my $check_sub = sub {

    my @decls;
    if( $type =~ m/^([^.]+)\.([^.]+)$/ ) {
      my $struct = $1;
      $type = "_ac_test_aggr.$2";
      my $decl = "static $struct _ac_test_aggr;";
      push( @decls, $decl );
    }
  
    my $typesize = $self->_compute_int_compile( "sizeof($type)", $prologue, @decls );
    $self->define_var( _sizeof_type_define_name( $type ), $typesize ? $typesize : undef, "defined when sizeof($type) is available" );
    if( $typesize ) {
      if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
	&{$action_if_found}();
      }
    }
    else {
      if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
	&{$action_if_not_found}();
      }
    }

    $typesize;
  };

  $self->check_cached( $cache_name, "for size of $type", $check_sub );
}

=head2 check_sizeof_types (type, [action-if-found], [action-if-not-found], [prologue = default includes])

For each type L<check_sizeof_type> is called to check for size of type.

If I<action-if-found> is given, it is additionally executed when all of the
sizes of the types could determined. If I<action-if-not-found> is given, it
is executed when one size of the types could not determined.

=cut

sub check_sizeof_types {
  my ($self, $types, $action_if_found, $action_if_not_found, $prologue) = @_;
  $self = $self->_get_instance();

  my $have_sizes = 1;
  foreach my $type (@$types) {
    $have_sizes &= ! ! ($self->check_sizeof_type ( $type, undef, undef, $prologue ));
  }

  if( $have_sizes ) {
    if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
      &{$action_if_found}();
    }
  }
  else {
    if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
      &{$action_if_not_found}();
    }
  }

  $have_sizes;
}

sub _alignof_type_define_name {
  my $type = $_[0];
  my $have_name = "ALIGNOF_" . uc($type);
  $have_name =~ tr/*/P/;
  $have_name =~ tr/_A-Za-z0-9/_/c;
  $have_name;
}

=head2 check_alignof_type (type, [action-if-found], [action-if-not-found], [prologue = default includes])

Define ALIGNOF_type to be the alignment in bytes of type. I<type y;> must
be valid as a structure member declaration or I<type> must be a structure
member itself.

This method caches its result in the C<ac_cv_alignof_E<lt>set langE<gt>>_type
variable, with I<*> mapped to C<p> and other characters not suitable for a
variable name mapped to underscores.

=cut

sub check_alignof_type {
  my ($self, $type, $action_if_found, $action_if_not_found, $prologue) = @_;
  $self = $self->_get_instance();
  defined( $type ) or return; # XXX prefer croak
  ref( $type ) eq "" or return;

  my $cache_name = $self->_cache_type_name( "alignof", $self->{lang}, $type );
  my $check_sub = sub {

    my @decls = (
      "#ifndef offsetof",
      "# ifdef __ICC",
      "#  define offsetof(type,memb) ((size_t)(((char *)(&((type*)0)->memb)) - ((char *)0)))",
      "# else",
      "#  define offsetof(type,memb) ((size_t)&((type*)0)->memb)",
      "# endif",
      "#endif"
    );

    my ($struct, $memb);
    if( $type =~ m/^([^.]+)\.([^.]+)$/ ) {
      $struct = $1;
      $memb = $2;
    }
    else {
      push( @decls, "typedef struct { char x; $type y; } ac__type_alignof_;" );
      $struct = "ac__type_alignof_";
      $memb = "y";
    }
  
    my $typealign = $self->_compute_int_compile( "offsetof($struct, $memb)", $prologue, @decls );
    $self->define_var( _alignof_type_define_name( $type ), $typealign ? $typealign : undef, "defined when alignof($type) is available" );
    if( $typealign ) {
      if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
	&{$action_if_found}();
      }
    }
    else {
      if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
	&{$action_if_not_found}();
      }
    }

    $typealign;
  };

  $self->check_cached( $cache_name, "for align of $type", $check_sub );
}

=head2 check_alignof_types (type, [action-if-found], [action-if-not-found], [prologue = default includes])

For each type L<check_alignof_type> is called to check for align of type.

If I<action-if-found> is given, it is additionally executed when all of the
aligns of the types could determined. If I<action-if-not-found> is given, it
is executed when one align of the types could not determined.

=cut

sub check_alignof_types {
  my ($self, $types, $action_if_found, $action_if_not_found, $prologue) = @_;
  $self = $self->_get_instance();

  my $have_aligns = 1;
  foreach my $type (@$types) {
    $have_aligns &= ! ! ($self->check_alignof_type ( $type, undef, undef, $prologue ));
  }

  if( $have_aligns ) {
    if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
      &{$action_if_found}();
    }
  }
  else {
    if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
      &{$action_if_not_found}();
    }
  }

  $have_aligns;
}

sub _have_member_define_name {
  my $member = $_[0];
  my $have_name = "HAVE_" . uc($member);
  $have_name =~ tr/_A-Za-z0-9/_/c;
  $have_name;
}

=head2 check_member (member, [action-if-found], [action-if-not-found], [prologue = default includes])

Check whether I<member> is in form of I<aggregate>.I<member> and
I<member> is a member of the I<aggregate> aggregate. I<prologue>
should be a series of include directives, defaulting to
I<default includes>, which are used prior to the aggregate under test.

  Config::AutoConf->check_member(
    "struct STRUCT_SV.sv_refcnt",
    undef,
    sub { Config::AutoConf->msg_failure( "sv_refcnt member required for struct STRUCT_SV" ); }
    "#include <EXTERN.h>\n#include <perl.h>"
  );

If I<aggregate> aggregate has I<member> member, preprocessor
macro HAVE_I<aggregate>_I<MEMBER> (in all capitals, with spaces
and dots replaced by underscores) is defined.

This macro caches its result in the C<ac_cv_>aggr_member variable.

=cut

sub check_member {
  my ($self, $member, $action_if_found, $action_if_not_found, $prologue) = @_;
  $self = $self->_get_instance();
  defined( $member ) or return; # XXX prefer croak
  ref( $member ) eq "" or return;

  $member =~ m/^([^.]+)\.([^.]+)$/ or return;
  my $type = $1;
  $member = $2;

  my $cache_name = $self->_cache_type_name( "member", $type );
  my $check_sub = sub {
  
    my $body = <<ACEOF;
  static $type check_aggr;
  if( check_aggr.$member )
    return 0;
ACEOF
    my $conftest = $self->lang_build_program( $prologue, $body );

    my $have_member = $self->compile_if_else( $conftest );
    $self->define_var( _have_member_define_name( $member ), $have_member ? $have_member : undef, "defined when $member is available" );
    if( $have_member ) {
      if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
	&{$action_if_found}();
      }
    }
    else {
      if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
	&{$action_if_not_found}();
      }
    }

    $have_member;
  };

  $self->check_cached( $cache_name, "for $type.$member", $check_sub );
}

=head2 check_members (members, [action-if-found], [action-if-not-found], [prologue = default includes])

For each member L<check_member> is called to check for member of aggregate.

If I<action-if-found> is given, it is additionally executed when all of the
aggregate members are found. If I<action-if-not-found> is given, it is
executed when one of the aggregate members is not found.

=cut

sub check_members {
  my ($self, $members, $action_if_found, $action_if_not_found, $prologue) = @_;
  $self = $self->_get_instance();

  my $have_members = 1;
  foreach my $member (@$members) {
    $have_members &= $self->check_member( $member, undef, undef, $prologue );
  }

  if( $have_members ) {
    if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
      &{$action_if_found}();
    }
  }
  else {
    if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
      &{$action_if_not_found}();
    }
  }

  $have_members;
}

=head2 check_headers

This function uses check_header to check if a set of include files exist in the system and can
be included and compiled by the available compiler. Returns the name of the first header file found.

=cut

sub check_headers {
  my $self = shift;
  $self->check_header($_) and return $_ for(@_);
  return;
}

sub _have_header_define_name {
  my $header = $_[0];
  my $have_name = "HAVE_" . uc($header);
  $have_name =~ tr/_A-Za-z0-9/_/c;
  return $have_name;
}

sub _check_header {
  my ($self, $header, $prologue, $body) = @_;

  $prologue .= <<"_ACEOF";
    #include <$header>
_ACEOF
  my $conftest = $self->lang_build_program( $prologue, $body );

  my $have_header = $self->compile_if_else( $conftest );
  $have_header;
}

=head2 check_header

This function is used to check if a specific header file is present in
the system: if we detect it and if we can compile anything with that
header included. Note that normally you want to check for a header
first, and then check for the corresponding library (not all at once).

The standard usage for this module is:

  Config::AutoConf->check_header("ncurses.h");
  
This function will return a true value (1) on success, and a false value
if the header is not present or not available for common usage.

=cut

sub check_header {
  my $self = shift;
  my $header = shift;
  my $pre_inc = shift;

  return 0 unless $header;
  my $cache_name = $self->_cache_name( $header );
  my $check_sub = sub {
    my $prologue  = "";
    defined $pre_inc
      and $prologue .= "$pre_inc\n";

    my $have_header = $self->_check_header( $header, $prologue, "" );
    $self->define_var( _have_header_define_name( $header ), $have_header ? $have_header : undef, "defined when $header is available" );

    return $have_header;
  };

  $self->check_cached( $cache_name, "for $header", $check_sub );
}

=head2 check_all_headers

This function checks each given header for usability.

=cut

sub check_all_headers {
  my $self = shift->_get_instance();
  @_ or return;
  my $rc = 1;
  foreach my $header (@_) {
    $rc &= $self->check_header( $header );
  }
  $rc;
}

=head2 check_stdc_headers

Checks for standard C89 headers, namely stdlib.h, stdarg.h, string.h and float.h.
If those are found, additional all remaining C89 headers are checked: assert.h,
ctype.h, errno.h, limits.h, locale.h, math.h, setjmp.h, signal.h, stddef.h,
stdio.h and time.h.

Returns a false value if it fails.

=cut

sub check_stdc_headers {
  my $self = shift->_get_instance();
  my $rc = 0;
  if( $rc = $self->check_all_headers( qw(stdlib.h stdarg.h string.h float.h) ) ) {
    $rc &= $self->check_all_headers( qw/assert.h ctype.h errno.h limits.h/ );
    $rc &= $self->check_all_headers( qw/locale.h math.h setjmp.h signal.h/ );
    $rc &= $self->check_all_headers( qw/stddef.h stdio.h time.h/ );
  }
  $rc and $self->define_var( "STDC_HEADERS", 1, "Define to 1 if you have the ANSI C header files." );
  $rc;
}

=head2 check_default_headers

This function checks for some default headers, the std c89 haeders and
sys/types.h, sys/stat.h, memory.h, strings.h, inttypes.h, stdint.h and unistd.h

=cut

sub check_default_headers {
  my $self = shift->_get_instance();
  my $rc = $self->check_stdc_headers() and $self->check_all_headers( qw(sys/types.h sys/stat.h memory.h strings.h inttypes.h stdint.h unistd.h) );
  $rc;
}

=head2 check_dirent_header

Check for the following header files. For the first one that is found and
defines 'DIR', define the listed C preprocessor macro:

  dirent.h 	HAVE_DIRENT_H
  sys/ndir.h 	HAVE_SYS_NDIR_H
  sys/dir.h 	HAVE_SYS_DIR_H
  ndir.h 	HAVE_NDIR_H

The directory-library declarations in your source code should look
something like the following:

  #include <sys/types.h>
  #ifdef HAVE_DIRENT_H
  # include <dirent.h>
  # define NAMLEN(dirent) strlen ((dirent)->d_name)
  #else
  # define dirent direct
  # define NAMLEN(dirent) ((dirent)->d_namlen)
  # ifdef HAVE_SYS_NDIR_H
  #  include <sys/ndir.h>
  # endif
  # ifdef HAVE_SYS_DIR_H
  #  include <sys/dir.h>
  # endif
  # ifdef HAVE_NDIR_H
  #  include <ndir.h>
  # endif
  #endif

Using the above declarations, the program would declare variables to be of
type C<struct dirent>, not C<struct direct>, and would access the length
of a directory entry name by passing a pointer to a C<struct dirent> to
the C<NAMLEN> macro.

This macro might be obsolescent, as all current systems with directory
libraries have C<<E<lt>dirent.hE<gt>>>. Programs supporting only newer OS
might not need touse this macro.

=cut

sub check_dirent_header {
  my $self = shift->_get_instance();

  my $cache_name = $self->_cache_name( "header_dirent" );
  my $check_sub = sub {

    my $have_dirent;
    foreach my $header (qw(dirent.h sys/ndir.h sys/dir.h ndir.h)) {
      $have_dirent = $self->_check_header( $header, "#include <sys/types.h>\n", "if ((DIR *) 0) { return 0; }" );
      $self->define_var( _have_header_define_name( $header ), $have_dirent ? $have_dirent : undef, "defined when $header is available" );
      $have_dirent and $have_dirent = $header and last;
    }

    $have_dirent;
  };


  $self->check_cached( $cache_name, "for header defining DIR *", $check_sub );
}

sub _have_lib_define_name {
  my $lib = $_[0];
  my $have_name = "HAVE_LIB" . uc($lib);
  $have_name =~ tr/_A-Za-z0-9/_/c;
  return $have_name;
}

=head2 _check_perl_api_program

This method provides the program source which is suitable to do basic
compile/link tests to prove perl development environment.

=cut

sub _check_perl_api_program {
  my $self = shift;

  my $includes = $self->_default_includes_with_perl();
  my $perl_check_body = <<'EOB';
  I32 rc;
  SV *foo = newSVpv("Perl rocks", 11);
  rc = SvCUR(foo);
EOB
  $self->lang_build_program( $includes, $perl_check_body );
}

=head2 _check_compile_perl_api

This method can be used from other checks to prove whether we have a perl
development environment or not (perl.h, reasonable basic checks - types, etc.)

=cut

sub _check_compile_perl_api {
  my $self = shift;

  my $conftest = $self->_check_perl_api_program();
  $self->compile_if_else($conftest);
}

=head2 check_compile_perl_api

This method can be used from other checks to prove whether we have a perl
development environment or not (perl.h, reasonable basic checks - types, etc.)

=cut

sub check_compile_perl_api {
  my $self = shift->_get_instance;
  my $cache_name = $self->_cache_name(qw(compile perl api));

  $self->check_cached( $cache_name,
    "whether perl api is accessible",
    sub { $self->_check_compile_perl_api } );
}

=head2 _check_link_perl_api

This method can be used from other checks to prove whether we have a perl
development environment including a suitable libperl or not (perl.h,
reasonable basic checks - types, etc.)

Caller must ensure that the linker flags are set appropriate (C<-lperl>
or similar).

=cut

sub _check_link_perl_api {
  my $self = shift;

  my $conftest = $self->_check_perl_api_program();
  my @save_libs = @{$self->{extra_libs}};
  my @save_extra_link_flags = @{$self->{extra_link_flags}};

  push @{$self->{extra_link_flags}}, "-L" . File::Spec->catdir($Config{installarchlib}, "CORE");
  push @{$self->{extra_libs}}, "perl";
  if($Config{perllibs}) {
    foreach my $perllib (split(" ", $Config{perllibs})) {
      $perllib =~ m/^\-l(\w+)$/ and push @{$self->{extra_libs}}, "$1" and next;
      push @{$self->{extra_link_flags}}, $perllib;
    }
  }

  my $have_libperl = $self->link_if_else( $conftest );

  $self->{extra_libs} = [ @save_libs ];
  $self->{extra_link_flags} = [ @save_extra_link_flags ];

  $have_libperl;
}

=head2 check_link_perl_api

This method can be used from other checks to prove whether we have a perl
development environment or not (perl.h, libperl.la, reasonable basic
checks - types, etc.)

=cut

sub check_link_perl_api {
  my $self = shift->_get_instance;
  my $cache_name = $self->_cache_name(qw(link perl api));

  $self->check_cached( $cache_name,
    "whether perl api is linkable",
    sub { $self->_check_link_perl_api } );
}

=head2 check_lm( [ action-if-found ], [ action-if-not-found ] )

This method is used to check if some common C<math.h> functions are
available, and if C<-lm> is needed. Returns the empty string if no
library is needed, or the "-lm" string if libm is needed.

Actions are only called at the end of the list of tests. If one fails,
I<action-if-not-found> is run. Otherwise, I<action-if-found> is run.

=cut

sub check_lm {
  my ($self, $aif, $ainf) = @_;
  ref($self) or $self = $self->_get_instance();

  my $fail = 0;
  my $required = "";
  for my $func (qw(log2 pow log10 log exp sqrt)) {
    my $ans = $self->search_libs( $func, ['m'] );

    $ans or $fail = 1;
    ($ans ne "none required") and $required = $ans;
  }

  if ($fail) { $ainf && $ainf->() }
  else       { $aif  && $aif->() }

  $required;
}

=head2 check_lib( lib, func, [ action-if-found ], [ action-if-not-found ], [ @other-libs ] )

This function is used to check if a specific library includes some
function. Call it with the library name (without the lib portion), and
the name of the function you want to test:

  Config::AutoConf->check_lib("z", "gzopen");

It returns 1 if the function exist, 0 otherwise.

I<action-if-found> and I<action-if-not-found> can be CODE references
whereby the default action in case of function found is to define
the HAVE_LIBlibrary (all in capitals) preprocessor macro with 1 and
add $lib to the list of libraries to link.

If linking with library results in unresolved symbols that would be
resolved by linking with additional libraries, give those libraries
as the I<other-libs> argument: e.g., C<[qw(Xt X11)]>.
Otherwise, this routine may fail to detect that library is present,
because linking the test program can fail with unresolved symbols.
The other-libraries argument should be limited to cases where it is
desirable to test for one library in the presence of another that
is not already in LIBS. 

It's recommended to use L<search_libs> instead of check_lib these days.

=cut

sub check_lib {
  my ( $self, $lib, $func, $action_if_found, $action_if_not_found, @other_libs ) = @_;
  ref($self) or $self = $self->_get_instance();

  return 0 unless $lib;
  return 0 unless $func;

  scalar( @other_libs ) == 1 and ref( $other_libs[0] ) eq "ARRAY"
    and @other_libs = @{ $other_libs[0] };

  my $cache_name = $self->_cache_name( "lib", $lib, $func );
  my $check_sub = sub {
    my $conftest = $self->lang_call( "", $func );

    my @save_libs = @{$self->{extra_libs}};
    push( @{$self->{extra_libs}}, $lib, @other_libs );
    my $have_lib = $self->link_if_else( $conftest );
    $self->{extra_libs} = [ @save_libs ];

    if( $have_lib ) {
      if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
	&{$action_if_found}();
      }
      else {
	$self->define_var( _have_lib_define_name( $lib ), $have_lib,
			   "defined when library $lib is available" );
	push( @{$self->{extra_libs}}, $lib );
      }
    }
    else {
      if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
	&{$action_if_not_found}();
      }
      else {
	$self->define_var( _have_lib_define_name( $lib ), undef,
			   "defined when library $lib is available" );
      }
    }
    $have_lib;
  };

  $self->check_cached( $cache_name, "for $func in -l$lib", $check_sub );
}

=head2 search_libs( function, search-libs, [action-if-found], [action-if-not-found], [other-libs] )

Search for a library defining function if it's not already available.
This equates to calling

    Config::AutoConf->link_if_else(
        Config::AutoConf->lang_call( "", "$function" ) );

first with no libraries, then for each library listed in search-libs.
I<search-libs> must be specified as an array reference to avoid
confusion in argument order.

Prepend -llibrary to LIBS for the first library found to contain function,
and run I<action-if-found>. If the function is not found, run
I<action-if-not-found>.

If linking with library results in unresolved symbols that would be
resolved by linking with additional libraries, give those libraries as
the I<other-libraries> argument: e.g., C<[qw(Xt X11)]>. Otherwise, this
method fails to detect that function is present, because linking the
test program always fails with unresolved symbols.

The result of this test is cached in the ac_cv_search_function variable
as "none required" if function is already available, as C<0> if no
library containing function was found, otherwise as the -llibrary option
that needs to be prepended to LIBS.

=cut

sub search_libs {
  my ( $self, $func, $libs, $action_if_found, $action_if_not_found, @other_libs ) = @_;
  ref($self) or $self = $self->_get_instance();

  ( defined( $libs ) and "ARRAY" eq ref( $libs ) and scalar( @{$libs} ) > 0 )
    or return 0; # XXX would prefer croak
  return 0 unless $func;

  scalar( @other_libs ) == 1 and ref( $other_libs[0] ) eq "ARRAY"
    and @other_libs = @{ $other_libs[0] };

  my $cache_name = $self->_cache_name( "search", $func );
  my $check_sub = sub {

    my $conftest = $self->lang_call( "", $func );

    my @save_libs = @{$self->{extra_libs}};
    my $have_lib = 0;
    foreach my $libstest ( undef, @$libs ) {
      # XXX would local work on array refs? can we omit @save_libs?
      $self->{extra_libs} = [ @save_libs ];
      defined( $libstest ) and unshift( @{$self->{extra_libs}}, $libstest, @other_libs );
      $self->link_if_else( $conftest ) and ( $have_lib = defined( $libstest ) ? $libstest : "none required" ) and last;
    }
    $self->{extra_libs} = [ @save_libs ];
    if( $have_lib ) {
      $have_lib eq "none required" or unshift( @{$self->{extra_libs}}, $have_lib );

      if( defined( $action_if_found ) and "CODE" eq ref( $action_if_found ) ) {
	&{$action_if_found}();
      }
    }
    else {
      if( defined( $action_if_not_found ) and "CODE" eq ref( $action_if_not_found ) ) {
	&{$action_if_not_found}();
      }
    }

    return $have_lib;
  };

  return $self->check_cached( $cache_name, "for library containing $func", $check_sub );
}

=head2 pkg_config_package_flags($package, [action-if-found], [action-if-not-found])

Search for pkg-config flags for package as specified. The flags which are
extracted are C<--cflags> and C<--libs>. The extracted flags are appended
to the global C<extra_compile_flags> and C<extra_link_flags>, respectively.

Call it with the package you're looking for and optional callback whether
found or not.

=cut

my $_pkg_config_prog;

sub _pkg_config_flag {
  defined $_pkg_config_prog or croak("pkg_config_prog required");
  my @pkg_config_args = @_;
  my ( $stdout, $stderr, $exit ) =
    capture { system( $_pkg_config_prog, @pkg_config_args ); };
  chomp $stdout;
  0 == $exit and return $stdout;
  return;
}

sub pkg_config_package_flags {
  my ( $self, $package, $action_if_found, $action_if_not_found ) = @_;
  $self = $self->_get_instance();
  (my $pkgpfx = $package) =~ s/^(\w+).*?$/$1/;
  my $cache_name = $self->_cache_name( "pkg", $pkgpfx );
  defined $_pkg_config_prog or $_pkg_config_prog = $self->check_prog_pkg_config;
  my $check_sub = sub {
    my ( @pkg_cflags, @pkg_libs );

    (my $ENV_CFLAGS = $package) =~ s/^(\w+).*?$/$1_CFLAGS/;
    my $CFLAGS = defined $ENV{$ENV_CFLAGS} ? $ENV{$ENV_CFLAGS}
					   : _pkg_config_flag($package, "--cflags");
    $CFLAGS and @pkg_cflags = (
      map { $_ =~ s/^\s+//; $_ =~ s/\s+$//; Text::ParseWords::shellwords $_; }
      split( m/\n/, $CFLAGS )
    ) and push @{ $self->{extra_preprocess_flags} }, @pkg_cflags;

    (my $ENV_LIBS = $package) =~ s/^(\w+).*?$/$1_LIBS/;
    # do not separate between libs and extra (for now) - they come with -l prepended
    my $LIBS = defined $ENV{$ENV_LIBS} ? $ENV{$ENV_LIBS}
				       : _pkg_config_flag($package, "--libs");
    $LIBS and @pkg_libs = (
      map { $_ =~ s/^\s+//; $_ =~ s/\s+$//; Text::ParseWords::shellwords $_; }
      split( m/\n/, $LIBS )
    ) and push @{ $self->{extra_link_flags} }, @pkg_libs;

    join(" ", @pkg_cflags, @pkg_libs);
  };

  $self->check_cached( $cache_name, "for pkg-config package of $package", $check_sub );
}

=head2 _check_pureperl_build_wanted

This method proves the C<_argv> attribute and (when set) the C<PERL_MM_OPT>
whether they contain I<PUREPERL_ONLY=(0|1)> or not. The attribute C<_force_xs>
is set appropriate, which allows a compile test to bail out when C<Makefile.PL>
is called with I<PUREPERL_ONLY=0>.

=cut

sub _check_mm_pureperl_build_wanted {
  my $self = shift->_get_instance;

  defined $ENV{PERL_MM_OPT} and my @env_args = split " ", $ENV{PERL_MM_OPT};

  foreach my $arg ( @{$self->{_argv}}, @env_args ) {
    $arg =~ m/^PUREPERL_ONLY=(.*)$/ and return int($1);
  }

  0;
}

=head2 _check_pureperl_build_wanted

This method proves the C<_argv> attribute and (when set) the C<PERL_MB_OPT>
whether they contain I<--pureperl-only> or not.

=cut

sub _check_mb_pureperl_build_wanted {
  my $self = shift->_get_instance;

  defined $ENV{PERL_MB_OPT} and my @env_args = split " ", $ENV{PERL_MB_OPT};

  foreach my $arg ( @{$self->{_argv}}, @env_args ) {
    $arg eq "--pureperl-only" and return 1;
  }

  0;
}

=head2 _check_pureperl_build_wanted

This method calls C<_check_mm_pureperl_build_wanted> when running under
L<ExtUtils::MakeMaker> (C<Makefile.PL>) or C<_check_mb_pureperl_build_wanted>
when running under a C<Build.PL> (L<Module::Build> compatible) environment.

When neither is found (C<$0> contains neither C<Makefile.PL> nor C<Build.PL>),
simply 0 is returned.

=cut

sub _check_pureperl_build_wanted {
  $0 =~ m/Makefile\.PL$/i and goto \&_check_mm_pureperl_build_wanted;
  $0 =~ m/Build\.PL$/i and goto \&_check_mb_pureperl_build_wanted;

  0;
}

=head2 check_pureperl_build_wanted

This check method proves whether a pureperl build is wanted or not by
cached-checking C<< $self->_check_pureperl_build_wanted >>. The result
might lead to further checks, eg. L</_check_compile_perl_api>.

=cut

sub check_pureperl_build_wanted {
  my $self = shift->_get_instance;
  my $cache_name = $self->_cache_name(qw(pureperl only wanted));
  $self->check_cached( $cache_name,
    "whether pureperl shall be forced",
    sub { $self->_check_pureperl_build_wanted } );
}

=head2 check_sane_xs

This routine checks whether XS can be sanely used. Therefore it does
following checks in given order:

=over 4

=item *

check pureperl environment variables or command line arguments and disable
XS when pure perl is wanted in any way

=item *

check whether a compiler is available (C<check_cc>) and disable XS if none found

=item *

check whether a test program accessing Perl API can be compiled and
die with error if not

=item *

when C<ExtensivePerlAPI> is enabled, check wether perl extensions can
be linked or die with error otherwise

=item *

I<TODO> check whether a trivial XS can be loaded and die hard on error

=back

When all checks passed successfully, return a true value.

=cut

sub check_sane_xs {
  my $self = shift->_get_instance;
  my $pp = $self->check_pureperl_build_wanted();
  $pp and return 0;
  $self->check_cc or return 0;
  # XXX necessary check for $Config{useshrlib}?
  $self->check_compile_perl_api() or return $self->msg_error("Cannot use Perl API - giving up");
  if( $self->{c_ac_flags}->{ExtensivePerlAPI} ) {
    $self->check_compile_perl_api() or return $self->msg_error("Cannot link Perl API - giving up");
    # XXX add a reasonable check compiling and trying to load an XS module
  }
  return 1;
}


#
#
# Auxiliary funcs
#

=head2 _set_argv

Intended to act as a helper for evaluating given command line arguments.
Stores given arguments in instances C<_argv> attribute.

Call once at very begin of C<Makefile.PL> or C<Build.PL>:

  Your::Pkg::Config::AutoConf->_set_args(@ARGV);

=cut

sub _set_argv {
  my ( $self, @argv ) = @_;
  $self = $self->_get_instance;
  $self->{_argv} = \@argv;
  return;
}

sub _sanitize {
  # This is hard coded, and maybe a little stupid...
  my $x = shift;
  $x =~ s/ //g;
  $x =~ s/\///g;
  $x =~ s/\\//g;
  $x;
}

sub _get_instance {
  ref $_[0] and return $_[0];
  defined $glob_instance or $glob_instance = $_[0]->new();
  $glob_instance;
}

sub _get_builder {
  my $self = $_[0]->_get_instance();
  defined( $self->{lang_supported}->{ $self->{lang} } ) or croak( "Unsupported compile language \"" . $self->{lang} . "\"" );

  my $builder = $self->{lang_supported}->{ $self->{lang} }->new();

  ## XXX - Temporarily. Will try to send upstream
  if ($self->{lang} eq "C") {
      $builder->{config}{ccflags} =~ s/-arch \S+//g;
      $builder->{config}{lddlflags} =~ s/-arch \S+//g;
      $builder->{config}{ldflags} =~ s/-arch \S+//g;
  }
  $builder;
}

sub _set_language {
  my $self = shift->_get_instance();
  my ($lang, $impl) = @_;

  defined( $lang ) or croak( "Missing language" );

  defined( $impl ) and defined( $self->{lang_supported}->{$lang} )
    and $impl ne $self->{lang_supported}->{$lang}
    and croak( "Language implementor ($impl) doesn't match exisiting one (" . $self->{lang_supported}->{$lang} . ")" );

  defined( $impl ) and !defined( $self->{lang_supported}->{$lang} )
    and $self->{lang_supported}->{$lang} = $impl;

  defined( $self->{lang_supported}->{$lang} ) or croak( "Unsupported language \"$lang\"" );

  defined( $self->{extra_compile_flags}->{$lang} ) or $self->{extra_compile_flags}->{$lang} = [];

  $self->{lang} = $lang;

  return;
}

sub _fill_defines {
  my ($self, $src, $action_if_true, $action_if_false) = @_;
  ref $self or $self = $self->_get_instance();

  my $conftest = "";
  while( my ($defname, $defcnt) = each( %{ $self->{defines} } ) ) {
    $defcnt->[0] or next;
    defined $defcnt->[1] and $conftest .= "/* " . $defcnt->[1] . " */\n";
    $conftest .= join( " ", "#define", $defname, $defcnt->[0] ) . "\n";
  }
  $conftest .= "/* end of conftest.h */\n";

  $conftest;
}

#
# default includes taken from autoconf/headers.m4
#

=head2 _default_includes

returns a string containing default includes for program prologue taken
from autoconf/headers.m4:

  #include <stdio.h>
  #ifdef HAVE_SYS_TYPES_H
  # include <sys/types.h>
  #endif
  #ifdef HAVE_SYS_STAT_H
  # include <sys/stat.h>
  #endif
  #ifdef STDC_HEADERS
  # include <stdlib.h>
  # include <stddef.h>
  #else
  # ifdef HAVE_STDLIB_H
  #  include <stdlib.h>
  # endif
  #endif
  #ifdef HAVE_STRING_H
  # if !defined STDC_HEADERS && defined HAVE_MEMORY_H
  #  include <memory.h>
  # endif
  # include <string.h>
  #endif
  #ifdef HAVE_STRINGS_H
  # include <strings.h>
  #endif
  #ifdef HAVE_INTTYPES_H
  # include <inttypes.h>
  #endif
  #ifdef HAVE_STDINT_H
  # include <stdint.h>
  #endif
  #ifdef HAVE_UNISTD_H
  # include <unistd.h>
  #endif

=cut

my $_default_includes = <<"_ACEOF";
#include <stdio.h>
#ifdef HAVE_SYS_TYPES_H
# include <sys/types.h>
#endif
#ifdef HAVE_SYS_STAT_H
# include <sys/stat.h>
#endif
#ifdef STDC_HEADERS
# include <stdlib.h>
# include <stddef.h>
#else
# ifdef HAVE_STDLIB_H
#  include <stdlib.h>
# endif
#endif
#ifdef HAVE_STRING_H
# if !defined STDC_HEADERS && defined HAVE_MEMORY_H
#  include <memory.h>
# endif
# include <string.h>
#endif
#ifdef HAVE_STRINGS_H
# include <strings.h>
#endif
#ifdef HAVE_INTTYPES_H
# include <inttypes.h>
#endif
#ifdef HAVE_STDINT_H
# include <stdint.h>
#endif
#ifdef HAVE_UNISTD_H
# include <unistd.h>
#endif
_ACEOF


sub _default_includes { $_default_includes }

sub _default_main { $_[0]->_build_main("") }

my $_main_tpl = <<"_ACEOF";
  int
  main ()
  {
    %s;
    return 0;
  }
_ACEOF


sub _build_main {
  my $self = shift->_get_instance();
  my $body = shift || "";
  sprintf($_main_tpl, $body);
}

=head2 _default_includes_with_perl

returns a string containing default includes for program prologue containing
I<_default_includes> plus

  #include <EXTERN.h>
  #include <perl.h>

=cut

my $_include_perl = <<"_ACEOF";
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h> /* for perl context in threaded perls */
_ACEOF

sub _default_includes_with_perl {
  join( "\n", $_[0]->_default_includes, $_include_perl );
}

sub _cache_prefix { "ac" }

sub _cache_name {
  my ($self, @names) = @_;
  my $cache_name = join( "_", $self->_cache_prefix(), "cv", @names );
     $cache_name =~ tr/_A-Za-z0-9/_/c;
  $cache_name;
}

sub _get_log_fh {
  my $self = $_[0]->_get_instance();
  unless( defined( $self->{logfh} ) ) {
    my $open_mode = defined $self->{logfile_mode} ? $self->{logfile_mode} : ">";
    open( my $fh, $open_mode, $self->{logfile} ) or croak "Could not open file $self->{logfile}: $!";
    $self->{logfh} = [ $fh ];
  }

  $self->{logfh};
}

sub _add_log_entry {
  my ($self, @logentries) = @_;
  ref($self) or $self = $self->_get_instance();
  $self->_get_log_fh();
  foreach my $logentry (@logentries) {
    foreach my $fh (@{$self->{logfh}}) {
      print {$fh} "$logentry";
    }
  }

  return;
}

sub _add_log_lines {
  my ($self, @logentries) = @_;
  ref($self) or $self = $self->_get_instance();
  $self->_get_log_fh();
  my $logmsg = join("\n", @logentries) . "\n";
  foreach my $fh (@{$self->{logfh}}) {
    print {$fh} $logmsg;
  }

  return;
}

=head2 add_log_fh

Push new file handles at end of log-handles to allow tee-ing log-output

=cut

sub add_log_fh {
  my ($self, @newh) = @_;
  $self->_get_log_fh();
SKIP_DUP:
  foreach my $fh (@newh) {
    foreach my $eh (@{$self->{logfh}}) {
      $fh == $eh and next SKIP_DUP;
    }
    push @{$self->{logfh}}, $fh;
  }
  return;
}

=head2 delete_log_fh

Removes specified log file handles. This method allows you to shoot you
in your foot - it doesn't prove whether the primary nor the last handle
is removed. Use with caution.

=cut

sub delete_log_fh {
  my ($self, @xh) = @_;
  $self->_get_log_fh();
SKIP_DUP:
  foreach my $fh (@xh) {
    foreach my $ih (0 .. $#{$self->{logfh}}) {
      $fh == $self->{logfh}->[$ih] or next;
      splice @{$self->{logfh}}, $ih, 1;
      last;
    }
  }
  return;
}

sub _cache_type_name  {
  my ($self, @names) = @_;
  $self->_cache_name( map { $_ =~ tr/*/p/; $_ } @names );
}

sub _get_extra_compiler_flags {
  my $self = shift->_get_instance();
  my @ppflags = @{$self->{extra_preprocess_flags}};
  my @cflags = @{$self->{extra_compile_flags}->{ $self->{lang} }};
  join( " ", @ppflags, @cflags );
}

sub _get_extra_linker_flags {
  my $self = shift->_get_instance();
  my @libs = @{$self->{extra_libs}};
  my @ldflags = @{$self->{extra_link_flags}};
  join( " ", @ldflags, map { "-l$_" } @libs );
}

=head1 AUTHOR

Alberto Simões, C<< <ambs@cpan.org> >>

Jens Rehsack, C<< <rehsack@cpan.org> >>

=head1 NEXT STEPS

Although a lot of work needs to be done, this is the next steps I
intent to take.

  - detect flex/lex
  - detect yacc/bison/byacc
  - detect ranlib (not sure about its importance)

These are the ones I think not too much important, and will be
addressed later, or by request.

  - detect an 'install' command
  - detect a 'ln -s' command -- there should be a module doing
    this kind of task.

=head1 BUGS

A lot. Portability is a pain. B<<Patches welcome!>>.

Please report any bugs or feature requests to
C<bug-extutils-autoconf@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.  I will be notified, and then you'll automatically
be notified of progress on your bug as I make changes.

=head1 ACKNOWLEDGEMENTS

Michael Schwern for kind MacOS X help.

Ken Williams for ExtUtils::CBuilder

=head1 COPYRIGHT & LICENSE

Copyright 2004-2011 by the Authors

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

ExtUtils::CBuilder(3)

=cut

1; # End of Config::AutoConf
