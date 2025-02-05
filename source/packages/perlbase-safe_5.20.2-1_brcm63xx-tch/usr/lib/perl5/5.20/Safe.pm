package Safe;

use 5.003_11;
use Scalar::Util qw(reftype refaddr);

$Safe::VERSION = "2.37";


sub lexless_anon_sub {
                 # $_[0] is package;
                 # $_[1] is strict flag;
    my $__ExPr__ = $_[2];   # must be a lexical to create the closure that
                            # can be used to pass the value into the safe
                            # world

    # Create anon sub ref in root of compartment.
    # Uses a closure (on $__ExPr__) to pass in the code to be executed.
    # (eval on one line to keep line numbers as expected by caller)
    eval sprintf
    'package %s; %s sub { @_=(); eval q[local *SIG; my $__ExPr__;] . $__ExPr__; }',
                $_[0], $_[1] ? 'use strict;' : '';
}

use strict;
use Carp;
BEGIN { eval q{
    use Carp::Heavy;
} }

use B ();
BEGIN {
    no strict 'refs';
    if (defined &B::sub_generation) {
        *sub_generation = \&B::sub_generation;
    }
    else {
        # fake sub generation changing for perls < 5.8.9
        my $sg; *sub_generation = sub { ++$sg };
    }
}

use Opcode 1.01, qw(
    opset opset_to_ops opmask_add
    empty_opset full_opset invert_opset verify_opset
    opdesc opcodes opmask define_optag opset_to_hex
);

*ops_to_opset = \&opset;   # Temporary alias for old Penguins

require utf8;
do { my $a = pack('U',0x100); my $b = chr 0x101; utf8::upgrade $b; $a =~ /$b/i };

my $default_root  = 0;
my $default_share = [qw[
    *_
    &PerlIO::get_layers
    &UNIVERSAL::isa
    &UNIVERSAL::can
    &UNIVERSAL::VERSION
    &utf8::is_utf8
    &utf8::valid
    &utf8::encode
    &utf8::decode
    &utf8::upgrade
    &utf8::downgrade
    &utf8::native_to_unicode
    &utf8::unicode_to_native
    &utf8::SWASHNEW
    $version::VERSION
    $version::CLASS
    $version::STRICT
    $version::LAX
    @version::ISA
], ($] < 5.010 && qw[
    &utf8::SWASHGET
]), ($] >= 5.008001 && qw[
    &Regexp::DESTROY
]), ($] >= 5.010 && qw[
    &re::is_regexp
    &re::regname
    &re::regnames
    &re::regnames_count
    &UNIVERSAL::DOES
    &version::()
    &version::new
    &version::(""
    &version::stringify
    &version::(0+
    &version::numify
    &version::normal
    &version::(cmp
    &version::(<=>
    &version::vcmp
    &version::(bool
    &version::boolean
    &version::(nomethod
    &version::noop
    &version::is_alpha
    &version::qv
    &version::vxs::declare
    &version::vxs::qv
    &version::vxs::_VERSION
    &version::vxs::stringify
    &version::vxs::new
    &version::vxs::parse
    &version::vxs::VCMP
]), ($] >= 5.011 && qw[
    &re::regexp_pattern
]), ($] >= 5.010 && $] < 5.014 && qw[
    &Tie::Hash::NamedCapture::FETCH
    &Tie::Hash::NamedCapture::STORE
    &Tie::Hash::NamedCapture::DELETE
    &Tie::Hash::NamedCapture::CLEAR
    &Tie::Hash::NamedCapture::EXISTS
    &Tie::Hash::NamedCapture::FIRSTKEY
    &Tie::Hash::NamedCapture::NEXTKEY
    &Tie::Hash::NamedCapture::SCALAR
    &Tie::Hash::NamedCapture::flags
])];
if (defined $Devel::Cover::VERSION) {
    push @$default_share, '&Devel::Cover::use_file';
}

sub new {
    my($class, $root, $mask) = @_;
    my $obj = {};
    bless $obj, $class;

    if (defined($root)) {
        croak "Can't use \"$root\" as root name"
            if $root =~ /^main\b/ or $root !~ /^\w[:\w]*$/;
        $obj->{Root}  = $root;
        $obj->{Erase} = 0;
    }
    else {
        $obj->{Root}  = "Safe::Root".$default_root++;
        $obj->{Erase} = 1;
    }

    # use permit/deny methods instead till interface issues resolved
    # XXX perhaps new Safe 'Root', mask => $mask, foo => bar, ...;
    croak "Mask parameter to new no longer supported" if defined $mask;
    $obj->permit_only(':default');

    # We must share $_ and @_ with the compartment or else ops such
    # as split, length and so on won't default to $_ properly, nor
    # will passing argument to subroutines work (via @_). In fact,
    # for reasons I don't completely understand, we need to share
    # the whole glob *_ rather than $_ and @_ separately, otherwise
    # @_ in non default packages within the compartment don't work.
    $obj->share_from('main', $default_share);

    Opcode::_safe_pkg_prep($obj->{Root}) if($Opcode::VERSION > 1.04);

    return $obj;
}

sub DESTROY {
    my $obj = shift;
    $obj->erase('DESTROY') if $obj->{Erase};
}

sub erase {
    my ($obj, $action) = @_;
    my $pkg = $obj->root();
    my ($stem, $leaf);

    no strict 'refs';
    $pkg = "main::$pkg\::";     # expand to full symbol table name
    ($stem, $leaf) = $pkg =~ m/(.*::)(\w+::)$/;

    # The 'my $foo' is needed! Without it you get an
    # 'Attempt to free unreferenced scalar' warning!
    my $stem_symtab = *{$stem}{HASH};

    #warn "erase($pkg) stem=$stem, leaf=$leaf";
    #warn " stem_symtab hash ".scalar(%$stem_symtab)."\n";
    # ", join(', ', %$stem_symtab),"\n";


    my $leaf_glob   = $stem_symtab->{$leaf};
    my $leaf_symtab = *{$leaf_glob}{HASH};
    %$leaf_symtab = ();
    #delete $leaf_symtab->{'__ANON__'};
    #delete $leaf_symtab->{'foo'};
    #delete $leaf_symtab->{'main::'};

    if ($action and $action eq 'DESTROY') {
        delete $stem_symtab->{$leaf};
    } else {
        $obj->share_from('main', $default_share);
    }
    1;
}


sub reinit {
    my $obj= shift;
    $obj->erase;
    $obj->share_redo;
}

sub root {
    my $obj = shift;
    croak("Safe root method now read-only") if @_;
    return $obj->{Root};
}


sub mask {
    my $obj = shift;
    return $obj->{Mask} unless @_;
    $obj->deny_only(@_);
}

sub trap   { shift->deny(@_)   }
sub untrap { shift->permit(@_) }

sub deny {
    my $obj = shift;
    $obj->{Mask} |= opset(@_);
}
sub deny_only {
    my $obj = shift;
    $obj->{Mask} = opset(@_);
}

sub permit {
    my $obj = shift;
    # XXX needs testing
    $obj->{Mask} &= invert_opset opset(@_);
}
sub permit_only {
    my $obj = shift;
    $obj->{Mask} = invert_opset opset(@_);
}


sub dump_mask {
    my $obj = shift;
    print opset_to_hex($obj->{Mask}),"\n";
}


sub share {
    my($obj, @vars) = @_;
    $obj->share_from(scalar(caller), \@vars);
}


sub share_from {
    my $obj = shift;
    my $pkg = shift;
    my $vars = shift;
    my $no_record = shift || 0;
    my $root = $obj->root();
    croak("vars not an array ref") unless ref $vars eq 'ARRAY';
    no strict 'refs';
    # Check that 'from' package actually exists
    croak("Package \"$pkg\" does not exist")
        unless keys %{"$pkg\::"};
    my $arg;
    foreach $arg (@$vars) {
        # catch some $safe->share($var) errors:
        my ($var, $type);
        $type = $1 if ($var = $arg) =~ s/^(\W)//;
        # warn "share_from $pkg $type $var";
        for (1..2) { # assign twice to avoid any 'used once' warnings
            *{$root."::$var"} = (!$type)   ? \&{$pkg."::$var"}
                          : ($type eq '&') ? \&{$pkg."::$var"}
                          : ($type eq '$') ? \${$pkg."::$var"}
                          : ($type eq '@') ? \@{$pkg."::$var"}
                          : ($type eq '%') ? \%{$pkg."::$var"}
                          : ($type eq '*') ?  *{$pkg."::$var"}
                          : croak(qq(Can't share "$type$var" of unknown type));
        }
    }
    $obj->share_record($pkg, $vars) unless $no_record or !$vars;
}


sub share_record {
    my $obj = shift;
    my $pkg = shift;
    my $vars = shift;
    my $shares = \%{$obj->{Shares} ||= {}};
    # Record shares using keys of $obj->{Shares}. See reinit.
    @{$shares}{@$vars} = ($pkg) x @$vars if @$vars;
}


sub share_redo {
    my $obj = shift;
    my $shares = \%{$obj->{Shares} ||= {}};
    my($var, $pkg);
    while(($var, $pkg) = each %$shares) {
        # warn "share_redo $pkg\:: $var";
        $obj->share_from($pkg,  [ $var ], 1);
    }
}


sub share_forget {
    delete shift->{Shares};
}


sub varglob {
    my ($obj, $var) = @_;
    no strict 'refs';
    return *{$obj->root()."::$var"};
}

sub _clean_stash {
    my ($root, $saved_refs) = @_;
    $saved_refs ||= [];
    no strict 'refs';
    foreach my $hook (qw(DESTROY AUTOLOAD), grep /^\(/, keys %$root) {
        push @$saved_refs, \*{$root.$hook};
        delete ${$root}{$hook};
    }

    for (grep /::$/, keys %$root) {
        next if \%{$root.$_} eq \%$root;
        _clean_stash($root.$_, $saved_refs);
    }
}

sub reval {
    my ($obj, $expr, $strict) = @_;
    die "Bad Safe object" unless $obj->isa('Safe');

    my $root = $obj->{Root};

    my $evalsub = lexless_anon_sub($root, $strict, $expr);
    # propagate context
    my $sg = sub_generation();
    my @subret = (wantarray)
               ?        Opcode::_safe_call_sv($root, $obj->{Mask}, $evalsub)
               : scalar Opcode::_safe_call_sv($root, $obj->{Mask}, $evalsub);
    _clean_stash($root.'::') if $sg != sub_generation();
    $obj->wrap_code_refs_within(@subret);
    return (wantarray) ? @subret : $subret[0];
}

my %OID;

sub wrap_code_refs_within {
    my $obj = shift;

    %OID = ();
    $obj->_find_code_refs('wrap_code_ref', @_);
}


sub _find_code_refs {
    my $obj = shift;
    my $visitor = shift;

    for my $item (@_) {
        my $reftype = $item && reftype $item
            or next;

        # skip references already seen
        next if ++$OID{refaddr $item} > 1;

        if ($reftype eq 'ARRAY') {
            $obj->_find_code_refs($visitor, @$item);
        }
        elsif ($reftype eq 'HASH') {
            $obj->_find_code_refs($visitor, values %$item);
        }
        # XXX GLOBs?
        elsif ($reftype eq 'CODE') {
            $item = $obj->$visitor($item);
        }
    }
}


sub wrap_code_ref {
    my ($obj, $sub) = @_;
    die "Bad safe object" unless $obj->isa('Safe');

    # wrap code ref $sub with _safe_call_sv so that, when called, the
    # execution will happen with the compartment fully 'in effect'.

    croak "Not a CODE reference"
        if reftype $sub ne 'CODE';

    my $ret = sub {
        my @args = @_; # lexical to close over
        my $sub_with_args = sub { $sub->(@args) };

        my @subret;
        my $error;
        do {
            local $@;  # needed due to perl_call_sv(sv, G_EVAL|G_KEEPERR)
            my $sg = sub_generation();
            @subret = (wantarray)
                ?        Opcode::_safe_call_sv($obj->{Root}, $obj->{Mask}, $sub_with_args)
                : scalar Opcode::_safe_call_sv($obj->{Root}, $obj->{Mask}, $sub_with_args);
            $error = $@;
            _clean_stash($obj->{Root}.'::') if $sg != sub_generation();
        };
        if ($error) { # rethrow exception
            $error =~ s/\t\(in cleanup\) //; # prefix added by G_KEEPERR
            die $error;
        }
        return (wantarray) ? @subret : $subret[0];
    };

    return $ret;
}


sub rdo {
    my ($obj, $file) = @_;
    die "Bad Safe object" unless $obj->isa('Safe');

    my $root = $obj->{Root};

    my $sg = sub_generation();
    my $evalsub = eval
            sprintf('package %s; sub { @_ = (); do $file }', $root);
    my @subret = (wantarray)
               ?        Opcode::_safe_call_sv($root, $obj->{Mask}, $evalsub)
               : scalar Opcode::_safe_call_sv($root, $obj->{Mask}, $evalsub);
    _clean_stash($root.'::') if $sg != sub_generation();
    $obj->wrap_code_refs_within(@subret);
    return (wantarray) ? @subret : $subret[0];
}


1;

__END__


