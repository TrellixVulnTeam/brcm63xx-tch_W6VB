package DBM_Filter::null ;

use strict;
use warnings;

our $VERSION = '0.03';

sub Store
{
    no warnings 'uninitialized';
    $_ .= "\x00" ;
}

sub Fetch
{
    no warnings 'uninitialized';
    s/\x00$// ;
}

1;

__END__

