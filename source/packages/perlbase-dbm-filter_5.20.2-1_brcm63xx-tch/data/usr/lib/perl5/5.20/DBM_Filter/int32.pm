package DBM_Filter::int32 ;

use strict;
use warnings;

our $VERSION = '0.03';


sub Store
{
    $_ = 0 if ! defined $_ || $_ eq "" ;
    $_ = pack("i", $_);
}

sub Fetch
{
    no warnings 'uninitialized';
    $_ = unpack("i", $_);
}

1;

__END__

