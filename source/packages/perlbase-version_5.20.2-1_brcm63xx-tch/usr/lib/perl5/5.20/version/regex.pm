package version::regex;

use strict;

use vars qw($VERSION $CLASS $STRICT $LAX);

$VERSION = 0.9909;



my $FRACTION_PART = qr/\.[0-9]+/;


my $STRICT_INTEGER_PART = qr/0|[1-9][0-9]*/;


my $LAX_INTEGER_PART = qr/[0-9]+/;


my $STRICT_DOTTED_DECIMAL_PART = qr/\.[0-9]{1,3}/;


my $LAX_DOTTED_DECIMAL_PART = qr/\.[0-9]+/;


my $LAX_ALPHA_PART = qr/_[0-9]+/;



my $STRICT_DECIMAL_VERSION =
    qr/ $STRICT_INTEGER_PART $FRACTION_PART? /x;


my $STRICT_DOTTED_DECIMAL_VERSION =
    qr/ v $STRICT_INTEGER_PART $STRICT_DOTTED_DECIMAL_PART{2,} /x;


$STRICT =
    qr/ $STRICT_DECIMAL_VERSION | $STRICT_DOTTED_DECIMAL_VERSION /x;



my $LAX_DECIMAL_VERSION =
    qr/ $LAX_INTEGER_PART (?: \. | $FRACTION_PART $LAX_ALPHA_PART? )?
	|
	$FRACTION_PART $LAX_ALPHA_PART?
    /x;


my $LAX_DOTTED_DECIMAL_VERSION =
    qr/
	v $LAX_INTEGER_PART (?: $LAX_DOTTED_DECIMAL_PART+ $LAX_ALPHA_PART? )?
	|
	$LAX_INTEGER_PART? $LAX_DOTTED_DECIMAL_PART{2,} $LAX_ALPHA_PART?
    /x;


$LAX =
    qr/ undef | $LAX_DECIMAL_VERSION | $LAX_DOTTED_DECIMAL_VERSION /x;


sub is_strict	{ defined $_[0] && $_[0] =~ qr/ \A $STRICT \z /x }
sub is_lax	{ defined $_[0] && $_[0] =~ qr/ \A $LAX \z /x }

1;
