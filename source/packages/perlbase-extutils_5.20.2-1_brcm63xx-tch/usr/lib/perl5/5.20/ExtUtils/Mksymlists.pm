package ExtUtils::Mksymlists;

use 5.006;
use strict qw[ subs refs ];

use Carp;
use Exporter;
use Config;

our @ISA = qw(Exporter);
our @EXPORT = qw(&Mksymlists);
our $VERSION = '6.98';

sub Mksymlists {
    my(%spec) = @_;
    my($osname) = $^O;

    croak("Insufficient information specified to Mksymlists")
        unless ( $spec{NAME} or
                 ($spec{FILE} and ($spec{DL_FUNCS} or $spec{FUNCLIST})) );

    $spec{DL_VARS} = [] unless $spec{DL_VARS};
    ($spec{FILE} = $spec{NAME}) =~ s/.*::// unless $spec{FILE};
    $spec{FUNCLIST} = [] unless $spec{FUNCLIST};
    $spec{DL_FUNCS} = { $spec{NAME} => [] }
        unless ( ($spec{DL_FUNCS} and keys %{$spec{DL_FUNCS}}) or
                 @{$spec{FUNCLIST}});
    if (defined $spec{DL_FUNCS}) {
        foreach my $package (sort keys %{$spec{DL_FUNCS}}) {
            my($packprefix,$bootseen);
            ($packprefix = $package) =~ s/\W/_/g;
            foreach my $sym (@{$spec{DL_FUNCS}->{$package}}) {
                if ($sym =~ /^boot_/) {
                    push(@{$spec{FUNCLIST}},$sym);
                    $bootseen++;
                }
                else {
                    push(@{$spec{FUNCLIST}},"XS_${packprefix}_$sym");
                }
            }
            push(@{$spec{FUNCLIST}},"boot_$packprefix") unless $bootseen;
        }
    }

    if (defined &DynaLoader::mod2fname and not $spec{DLBASE}) {
        $spec{DLBASE} = DynaLoader::mod2fname([ split(/::/,$spec{NAME}) ]);
    }

    if    ($osname eq 'aix') { _write_aix(\%spec); }
    elsif ($osname eq 'MacOS'){ _write_aix(\%spec) }
    elsif ($osname eq 'VMS') { _write_vms(\%spec) }
    elsif ($osname eq 'os2') { _write_os2(\%spec) }
    elsif ($osname eq 'MSWin32') { _write_win32(\%spec) }
    else {
        croak("Don't know how to create linker option file for $osname\n");
    }
}


sub _write_aix {
    my($data) = @_;

    rename "$data->{FILE}.exp", "$data->{FILE}.exp_old";

    open( my $exp, ">", "$data->{FILE}.exp")
        or croak("Can't create $data->{FILE}.exp: $!\n");
    print $exp join("\n",@{$data->{DL_VARS}}, "\n") if @{$data->{DL_VARS}};
    print $exp join("\n",@{$data->{FUNCLIST}}, "\n") if @{$data->{FUNCLIST}};
    close $exp;
}


sub _write_os2 {
    my($data) = @_;
    require Config;
    my $threaded = ($Config::Config{archname} =~ /-thread/ ? " threaded" : "");

    if (not $data->{DLBASE}) {
        ($data->{DLBASE} = $data->{NAME}) =~ s/.*:://;
        $data->{DLBASE} = substr($data->{DLBASE},0,7) . '_';
    }
    my $distname = $data->{DISTNAME} || $data->{NAME};
    $distname = "Distribution $distname";
    my $patchlevel = " pl$Config{perl_patchlevel}" || '';
    my $comment = sprintf "Perl (v%s%s%s) module %s",
      $Config::Config{version}, $threaded, $patchlevel, $data->{NAME};
    chomp $comment;
    if ($data->{INSTALLDIRS} and $data->{INSTALLDIRS} eq 'perl') {
        $distname = 'perl5-porters@perl.org';
        $comment = "Core $comment";
    }
    $comment = "$comment (Perl-config: $Config{config_args})";
    $comment = substr($comment, 0, 200) . "...)" if length $comment > 203;
    rename "$data->{FILE}.def", "$data->{FILE}_def.old";

    open(my $def, ">", "$data->{FILE}.def")
        or croak("Can't create $data->{FILE}.def: $!\n");
    print $def "LIBRARY '$data->{DLBASE}' INITINSTANCE TERMINSTANCE\n";
    print $def "DESCRIPTION '\@#$distname:$data->{VERSION}#\@ $comment'\n";
    print $def "CODE LOADONCALL\n";
    print $def "DATA LOADONCALL NONSHARED MULTIPLE\n";
    print $def "EXPORTS\n  ";
    print $def join("\n  ",@{$data->{DL_VARS}}, "\n") if @{$data->{DL_VARS}};
    print $def join("\n  ",@{$data->{FUNCLIST}}, "\n") if @{$data->{FUNCLIST}};
    _print_imports($def, $data);
    close $def;
}

sub _print_imports {
    my ($def, $data)= @_;
    my $imports= $data->{IMPORTS}
        or return;
    if ( keys %$imports ) {
        print $def "IMPORTS\n";
        foreach my $name (sort keys %$imports) {
            print $def "  $name=$imports->{$name}\n";
        }
    }
}

sub _write_win32 {
    my($data) = @_;

    require Config;
    if (not $data->{DLBASE}) {
        ($data->{DLBASE} = $data->{NAME}) =~ s/.*:://;
        $data->{DLBASE} = substr($data->{DLBASE},0,7) . '_';
    }
    rename "$data->{FILE}.def", "$data->{FILE}_def.old";

    open( my $def, ">", "$data->{FILE}.def" )
        or croak("Can't create $data->{FILE}.def: $!\n");
    # put library name in quotes (it could be a keyword, like 'Alias')
    if ($Config::Config{'cc'} !~ /^gcc/i) {
        print $def "LIBRARY \"$data->{DLBASE}\"\n";
    }
    print $def "EXPORTS\n  ";
    my @syms;
    # Export public symbols both with and without underscores to
    # ensure compatibility between DLLs from different compilers
    # NOTE: DynaLoader itself only uses the names without underscores,
    # so this is only to cover the case when the extension DLL may be
    # linked to directly from C. GSAR 97-07-10
    if ($Config::Config{'cc'} =~ /^bcc/i) {
        for (@{$data->{DL_VARS}}, @{$data->{FUNCLIST}}) {
            push @syms, "_$_", "$_ = _$_";
        }
    }
    else {
        for (@{$data->{DL_VARS}}, @{$data->{FUNCLIST}}) {
            push @syms, "$_", "_$_ = $_";
        }
    }
    print $def join("\n  ",@syms, "\n") if @syms;
    _print_imports($def, $data);
    close $def;
}


sub _write_vms {
    my($data) = @_;

    require Config; # a reminder for once we do $^O
    require ExtUtils::XSSymSet;

    my($isvax) = $Config::Config{'archname'} =~ /VAX/i;
    my($set) = new ExtUtils::XSSymSet;

    rename "$data->{FILE}.opt", "$data->{FILE}.opt_old";

    open(my $opt,">", "$data->{FILE}.opt")
        or croak("Can't create $data->{FILE}.opt: $!\n");

    # Options file declaring universal symbols
    # Used when linking shareable image for dynamic extension,
    # or when linking PerlShr into which we've added this package
    # as a static extension
    # We don't do anything to preserve order, so we won't relax
    # the GSMATCH criteria for a dynamic extension

    print $opt "case_sensitive=yes\n"
        if $Config::Config{d_vms_case_sensitive_symbols};

    foreach my $sym (@{$data->{FUNCLIST}}) {
        my $safe = $set->addsym($sym);
        if ($isvax) { print $opt "UNIVERSAL=$safe\n" }
        else        { print $opt "SYMBOL_VECTOR=($safe=PROCEDURE)\n"; }
    }

    foreach my $sym (@{$data->{DL_VARS}}) {
        my $safe = $set->addsym($sym);
        print $opt "PSECT_ATTR=${sym},PIC,OVR,RD,NOEXE,WRT,NOSHR\n";
        if ($isvax) { print $opt "UNIVERSAL=$safe\n" }
        else        { print $opt "SYMBOL_VECTOR=($safe=DATA)\n"; }
    }

    close $opt;
}

1;

__END__

