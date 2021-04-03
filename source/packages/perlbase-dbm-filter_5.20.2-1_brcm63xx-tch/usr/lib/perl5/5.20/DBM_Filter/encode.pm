package DBM_Filter::encode ;

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


sub Filter
{
    my $encoding_name = shift || "utf8";

    my $encoding = Encode::find_encoding($encoding_name) ;

    croak "Encoding '$encoding_name' is not available"
        unless $encoding;

    return {
        Store   => sub {
			 $_ = $encoding->encode($_)
			     if defined $_ ;
		   },
        Fetch   => sub {
			 $_ = $encoding->decode($_)
			     if defined $_ ;
			}
        } ;
}

1;

__END__

