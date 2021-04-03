package SDBM_File;

use strict;
use warnings;

require Tie::Hash;
require XSLoader;

our @ISA = qw(Tie::Hash);
our $VERSION = "1.11";

our @EXPORT_OK = qw(PAGFEXT DIRFEXT PAIRMAX);
use Exporter "import";

XSLoader::load();

1;

__END__

