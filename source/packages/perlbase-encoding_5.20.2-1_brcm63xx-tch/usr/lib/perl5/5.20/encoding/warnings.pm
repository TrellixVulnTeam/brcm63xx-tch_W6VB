package encoding::warnings;
$encoding::warnings::VERSION = '0.11';

use strict;
use 5.007;


sub ASCII  () { 0 }
sub LATIN1 () { 1 }
sub FATAL  () { 2 }

sub import {
    my $class = shift;
    my $fatal = shift || '';

    local $@;
    return if ${^ENCODING} and ref(${^ENCODING}) ne $class;
    return unless eval { require Encode; 1 };

    my $ascii  = Encode::find_encoding('us-ascii') or return;
    my $latin1 = Encode::find_encoding('iso-8859-1') or return;

    # Have to undef explicitly here
    undef ${^ENCODING};

    # Install a warning handler for decode()
    my $decoder = bless(
	[
	    $ascii,
	    $latin1,
	    (($fatal eq 'FATAL') ? 'Carp::croak' : 'Carp::carp'),
	], $class,
    );

    ${^ENCODING} = $decoder;
    $^H{$class} = 1;
}

sub unimport {
    my $class = shift;
    $^H{$class} = undef;
    undef ${^ENCODING};
}

sub cat_decode {
    my $self = shift;
    return $self->[LATIN1]->cat_decode(@_);
}

sub decode {
    my $self = shift;

    DO_WARN: {
        if ($] >= 5.009004) {
            my $hints = (caller(0))[10];
            $hints->{ref($self)} or last DO_WARN;
        }

        local $@;
        my $rv = eval { $self->[ASCII]->decode($_[0], Encode::FB_CROAK()) };
        return $rv unless $@;

        require Carp;
        no strict 'refs';
        $self->[FATAL]->(
            "Bytes implicitly upgraded into wide characters as iso-8859-1"
        );

    }

    return $self->[LATIN1]->decode(@_);
}

sub name { 'iso-8859-1' }

1;

__END__

