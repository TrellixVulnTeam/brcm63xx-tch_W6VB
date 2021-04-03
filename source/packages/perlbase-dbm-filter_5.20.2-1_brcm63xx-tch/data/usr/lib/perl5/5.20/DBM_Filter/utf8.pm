package DBM_Filter::utf8 ;

use strict;
use warnings;
use Carp;

our $VERSION = '0.03';

BEGIN
{
    eval { require Encode; };

    croak "Encode module not found.\n"
        if $@;
}

sub Store { $_ = Encode::encode_utf8($_) if defined $_ }

sub Fetch { $_ = Encode::decode_utf8($_) if defined $_ }

1;

__END__

