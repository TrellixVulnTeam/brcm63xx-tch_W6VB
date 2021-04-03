package less;
use strict;
use warnings;

our $VERSION = '0.03';

sub _pack_tags {
    return join ' ', @_;
}

sub _unpack_tags {
    return grep { defined and length }
        map  { split ' ' }
        grep {defined} @_;
}

sub stash_name { $_[0] }

sub of {
    my $class = shift @_;

    # If no one wants the result, don't bother computing it.
    return unless defined wantarray;

    my $hinthash = ( caller 0 )[10];
    my %tags;
    @tags{ _unpack_tags( $hinthash->{ $class->stash_name } ) } = ();

    if (@_) {
        exists $tags{$_} and return !!1 for @_;
        return;
    }
    else {
        return keys %tags;
    }
}

sub import {
    my $class = shift @_;
    my $stash = $class->stash_name;

    @_ = 'please' if not @_;
    my %tags;
    @tags{ _unpack_tags( @_, $^H{ $stash } ) } = ();

    $^H{$stash} = _pack_tags( keys %tags );
    return;
}

sub unimport {
    my $class = shift @_;

    if (@_) {
        my %tags;
        @tags{ _unpack_tags( $^H{$class} ) } = ();
        delete @tags{ _unpack_tags(@_) };
        my $new = _pack_tags( keys %tags );

        if ( not length $new ) {
            delete $^H{ $class->stash_name };
        }
        else {
            $^H{ $class->stash_name } = $new;
        }
    }
    else {
        delete $^H{ $class->stash_name };
    }

    return;
}

1;

__END__

