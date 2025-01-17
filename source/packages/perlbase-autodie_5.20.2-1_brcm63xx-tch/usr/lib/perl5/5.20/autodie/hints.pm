package autodie::hints;

use strict;
use warnings;

use constant PERL58 => ( $] < 5.009 );

our $VERSION = '2.23'; # VERSION: Generated by DZP::OurPkg:Version




use constant UNDEF_ONLY       => sub { not defined $_[0] };
use constant EMPTY_OR_UNDEF   => sub {
    ! @_ or
    @_==1 && !defined $_[0]
};

use constant EMPTY_ONLY     => sub { @_ == 0 };
use constant EMPTY_OR_FALSE => sub {
    ! @_ or
    @_==1 && !$_[0]
};

use constant SINGLE_TRUE => sub { @_ == 1 and not $_[0] };

use constant DEFAULT_HINTS => {
    scalar => UNDEF_ONLY,
    list   => EMPTY_OR_UNDEF,
};


use constant HINTS_PROVIDER => 'autodie::hints::provider';

use base qw(Exporter);

our $DEBUG = 0;


my %Hints = (
    'File::Copy::copy' => { scalar => SINGLE_TRUE, list => SINGLE_TRUE },
    'File::Copy::move' => { scalar => SINGLE_TRUE, list => SINGLE_TRUE },
    'File::Copy::cp'   => { scalar => SINGLE_TRUE, list => SINGLE_TRUE },
    'File::Copy::mv'   => { scalar => SINGLE_TRUE, list => SINGLE_TRUE },
);


eval { require Sub::Identify; Sub::Identify->import('get_code_info'); };


if ($@) {
    require B;

    no warnings 'once';

    *get_code_info = sub ($) {

        my ($coderef) = @_;
        ref $coderef or return;
        my $cv = B::svref_2object($coderef);
        $cv->isa('B::CV') or return;
        # bail out if GV is undefined
        $cv->GV->isa('B::SPECIAL') and return;

        return ($cv->GV->STASH->NAME, $cv->GV->NAME);
    };

}

sub sub_fullname {
    return join( '::', get_code_info( $_[1] ) );
}

my %Hints_loaded = ();

sub load_hints {
    my ($class, $sub) = @_;

    my ($package) = ( $sub =~ /(.*)::/ );

    if (not defined $package) {
        require Carp;
        Carp::croak(
            "Internal error in autodie::hints::load_hints - no package found.
        ");
    }

    # Do nothing if we've already tried to load hints for
    # this package.
    return if $Hints_loaded{$package}++;

    my $hints_available = 0;

    {
        no strict 'refs';   ## no critic

        if ($package->can('DOES') and $package->DOES(HINTS_PROVIDER) ) {
            $hints_available = 1;
        }
        elsif ( PERL58 and $package->isa(HINTS_PROVIDER) ) {
            $hints_available = 1;
        }
        elsif ( ${"${package}::DOES"}{HINTS_PROVIDER.""} ) {
            $hints_available = 1;
        }
    }

    return if not $hints_available;

    my %package_hints = %{ $package->AUTODIE_HINTS };

    foreach my $sub (keys %package_hints) {

        my $hint = $package_hints{$sub};

        # Ensure we have a package name.
        $sub = "${package}::$sub" if $sub !~ /::/;

        # TODO - Currently we don't check for conflicts, should we?
        $Hints{$sub} = $hint;

        $class->normalise_hints(\%Hints, $sub);
    }

    return;

}

sub normalise_hints {
    my ($class, $hints, $sub) = @_;

    if ( exists $hints->{$sub}->{fail} ) {

        if ( exists $hints->{$sub}->{scalar} or
             exists $hints->{$sub}->{list}
        ) {
            # TODO: Turn into a proper diagnostic.
            require Carp;
            local $Carp::CarpLevel = 1;
            Carp::croak("fail hints cannot be provided with either scalar or list hints for $sub");
        }

        # Set our scalar and list hints.

        $hints->{$sub}->{scalar} = 
        $hints->{$sub}->{list} = delete $hints->{$sub}->{fail};

        return;

    }

    # Check to make sure all our hints exist.

    foreach my $hint (qw(scalar list)) {
        if ( not exists $hints->{$sub}->{$hint} ) {
            # TODO: Turn into a proper diagnostic.
            require Carp;
            local $Carp::CarpLevel = 1;
            Carp::croak("$hint hint missing for $sub");
        }
    }

    return;
}

sub get_hints_for {
    my ($class, $sub) = @_;

    my $subname = $class->sub_fullname( $sub );

    # If we have hints loaded for a sub, then return them.

    if ( exists $Hints{ $subname } ) {
        return $Hints{ $subname };
    }

    # If not, we try to load them...

    $class->load_hints( $subname );

    # ...and try again!

    if ( exists $Hints{ $subname } ) {
        return $Hints{ $subname };
    }

    # It's the caller's responsibility to use defaults if desired.
    # This allows on autodie to insist on hints if needed.

    return;

}

sub set_hints_for {
    my ($class, $sub, $hints) = @_;

    if (ref $sub) {
        $sub = $class->sub_fullname( $sub );

        require Carp;

        $sub or Carp::croak("Attempts to set_hints_for unidentifiable subroutine");
    }

    if ($DEBUG) {
        warn "autodie::hints: Setting $sub to hints: $hints\n";
    }

    $Hints{ $sub } = $hints;

    $class->normalise_hints(\%Hints, $sub);

    return;
}

1;

__END__


