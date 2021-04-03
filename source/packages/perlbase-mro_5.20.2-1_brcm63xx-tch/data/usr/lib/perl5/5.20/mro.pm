package mro;
use strict;
use warnings;

our $VERSION = '1.16';

sub import {
    mro::set_mro(scalar(caller), $_[1]) if $_[1];
}

package # hide me from PAUSE
    next;

sub can { mro::_nextcan($_[0], 0) }

sub method {
    my $method = mro::_nextcan($_[0], 1);
    goto &$method;
}

package # hide me from PAUSE
    maybe::next;

sub method {
    my $method = mro::_nextcan($_[0], 0);
    goto &$method if defined $method;
    return;
}

require XSLoader;
XSLoader::load('mro');

1;

__END__

