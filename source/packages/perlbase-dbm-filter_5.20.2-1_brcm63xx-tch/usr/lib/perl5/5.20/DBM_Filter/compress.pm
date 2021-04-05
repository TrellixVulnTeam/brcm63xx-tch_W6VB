package DBM_Filter::compress ;

use strict;
use warnings;
use Carp;

our $VERSION = '0.03';

BEGIN
{
    eval { require Compress::Zlib; Compress::Zlib->import() };

    croak "Compress::Zlib module not found.\n"
        if $@;
}



sub Store { $_ = compress($_) }
sub Fetch { $_ = uncompress($_) }

1;

__END__

