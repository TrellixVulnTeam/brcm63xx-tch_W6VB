package Search::Dict;
require 5.000;
require Exporter;

my $fc_available;
BEGIN {
  $fc_available = '5.015008';
  if ( $] ge $fc_available ) {
    require feature;
    'feature'->import('fc'); # string avoids warning on old Perls <sigh>
  }
}

use strict;

our $VERSION = '1.07';
our @ISA = qw(Exporter);
our @EXPORT = qw(look);


sub look {
    my($fh,$key,$dict,$fold) = @_;
    my ($comp, $xfrm);
    if (@_ == 3 && ref $dict eq 'HASH') {
	my $params = $dict;
	$dict = 0;
	$dict = $params->{dict} if exists $params->{dict};
	$fold = $params->{fold} if exists $params->{fold};
	$comp = $params->{comp} if exists $params->{comp};
	$xfrm = $params->{xfrm} if exists $params->{xfrm};
    }
    $comp = sub { $_[0] cmp $_[1] } unless defined $comp;
    local($_);
    my $fno = fileno $fh;
    my @stat;
    if ( defined $fno && $fno >= 0 && ! tied *{$fh} ) { # real, open file
      @stat = eval { stat($fh) }; # in case fileno lies
    }
    my($size, $blksize) = @stat[7,11];
    $size = do { seek($fh,0,2); my $s = tell($fh); seek($fh,0,0); $s }
        unless defined $size;
    $blksize ||= 8192;
    $key =~ s/[^\w\s]//g if $dict;
    if ( $fold ) {
      $key = $] ge $fc_available ? fc($key) : lc($key);
    }
    # find the right block
    my($min, $max) = (0, int($size / $blksize));
    my $mid;
    while ($max - $min > 1) {
	$mid = int(($max + $min) / 2);
	seek($fh, $mid * $blksize, 0)
	    or return -1;
	<$fh> if $mid;			# probably a partial line
	$_ = <$fh>;
	$_ = $xfrm->($_) if defined $xfrm;
	chomp;
	s/[^\w\s]//g if $dict;
        if ( $fold ) {
          $_ = $] ge $fc_available ? fc($_) : lc($_);
        }
	if (defined($_) && $comp->($_, $key) < 0) {
	    $min = $mid;
	}
	else {
	    $max = $mid;
	}
    }
    # find the right line
    $min *= $blksize;
    seek($fh,$min,0)
	or return -1;
    <$fh> if $min;
    for (;;) {
	$min = tell($fh);
	defined($_ = <$fh>)
	    or last;
	$_ = $xfrm->($_) if defined $xfrm;
	chomp;
	s/[^\w\s]//g if $dict;
        if ( $fold ) {
          $_ = $] ge $fc_available ? fc($_) : lc($_);
        }
	last if $comp->($_, $key) >= 0;
    }
    seek($fh,$min,0);
    $min;
}

1;
