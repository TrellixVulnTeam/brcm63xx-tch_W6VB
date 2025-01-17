package AnyDBM_File;
use warnings;
use strict;

use 5.006_001;
our $VERSION = '1.01';
our @ISA = qw(NDBM_File DB_File GDBM_File SDBM_File ODBM_File) unless @ISA;

my $mod;
for $mod (@ISA) {
    if (eval "require $mod") {
	@ISA = ($mod);	# if we leave @ISA alone, warnings abound
	return 1;
    }
}

die "No DBM package was successfully found or installed";

__END__

