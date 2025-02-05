package File::Listing;

sub Version { $VERSION; }
$VERSION = "5.837";

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(parse_dir);

use strict;

use Carp ();
use HTTP::Date qw(str2time);



sub parse_dir ($;$$$)
{
   my($dir, $tz, $fstype, $error) = @_;

   $fstype ||= 'unix';
   $fstype = "File::Listing::" . lc $fstype;

   my @args = $_[0];
   push(@args, $tz) if(@_ >= 2);
   push(@args, $error) if(@_ >= 4);

   $fstype->parse(@args);
}


sub line { Carp::croak("Not implemented yet"); }
sub init { } # Dummy sub


sub file_mode ($)
{
    # This routine was originally borrowed from Graham Barr's
    # Net::FTP package.

    local $_ = shift;
    my $mode = 0;
    my($type,$ch);

    s/^(.)// and $type = $1;

    while (/(.)/g) {
	$mode <<= 1;
	$mode |= 1 if $1 ne "-" &&
		      $1 ne 'S' &&
		      $1 ne 't' &&
		      $1 ne 'T';
    }

    $type eq "d" and $mode |= 0040000 or	# Directory
      $type eq "l" and $mode |= 0120000 or	# Symbolic Link
	$mode |= 0100000;			# Regular File

    $mode |= 0004000 if /^...s....../i;
    $mode |= 0002000 if /^......s.../i;
    $mode |= 0001000 if /^.........t/i;

    $mode;
}


sub parse
{
   my($pkg, $dir, $tz, $error) = @_;

   # First let's try to determine what kind of dir parameter we have
   # received.  We allow both listings, reference to arrays and
   # file handles to read from.

   if (ref($dir) eq 'ARRAY') {
       # Already splitted up
   }
   elsif (ref($dir) eq 'GLOB') {
       # A file handle
   }
   elsif (ref($dir)) {
      Carp::croak("Illegal argument to parse_dir()");
   }
   elsif ($dir =~ /^\*\w+(::\w+)+$/) {
      # This scalar looks like a file handle, so we assume it is
   }
   else {
      # A normal scalar listing
      $dir = [ split(/\n/, $dir) ];
   }

   $pkg->init();

   my @files = ();
   if (ref($dir) eq 'ARRAY') {
       for (@$dir) {
	   push(@files, $pkg->line($_, $tz, $error));
       }
   }
   else {
       local($_);
       while (<$dir>) {
	   chomp;
	   push(@files, $pkg->line($_, $tz, $error));
       }
   }
   wantarray ? @files : \@files;
}



package File::Listing::unix;

use HTTP::Date qw(str2time);

use vars qw($curdir @ISA);

@ISA = qw(File::Listing);



sub init
{
    $curdir = '';
}


sub line
{
    shift; # package name
    local($_) = shift;
    my($tz, $error) = @_;

    s/\015//g;
    #study;

    my ($kind, $size, $date, $name);
    if (($kind, $size, $date, $name) =
	/^([\-FlrwxsStTdD]{10})                   # Type and permission bits
	 .*                                       # Graps
	 \D(\d+)                                  # File size
	 \s+                                      # Some space
	 (\w{3}\s+\d+\s+(?:\d{1,2}:\d{2}|\d{4})|\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2})  # Date
	 \s+                                      # Some more space
	 (.*)$                                    # File name
	/x )

    {
	return if $name eq '.' || $name eq '..';
	$name = "$curdir/$name" if length $curdir;
	my $type = '?';
	if ($kind =~ /^l/ && $name =~ /(.*) -> (.*)/ ) {
	    $name = $1;
	    $type = "l $2";
	}
	elsif ($kind =~ /^[\-F]/) { # (hopefully) a regular file
	    $type = 'f';
	}
	elsif ($kind =~ /^[dD]/) {
	    $type = 'd';
	    $size = undef;  # Don't believe the reported size
	}
	return [$name, $type, $size, str2time($date, $tz), 
              File::Listing::file_mode($kind)];

    }
    elsif (/^(.+):$/ && !/^[dcbsp].*\s.*\s.*:$/ ) {
	my $dir = $1;
	return () if $dir eq '.';
	$curdir = $dir;
	return ();
    }
    elsif (/^[Tt]otal\s+(\d+)$/ || /^\s*$/) {
	return ();
    }
    elsif (/not found/    || # OSF1, HPUX, and SunOS return
             # "$file not found"
             /No such file/ || # IRIX returns
             # "UX:ls: ERROR: Cannot access $file: No such file or directory"
                               # Solaris returns
             # "$file: No such file or directory"
             /cannot find/     # Windows NT returns
             # "The system cannot find the path specified."
             ) {
	return () unless defined $error;
	&$error($_) if ref($error) eq 'CODE';
	warn "Error: $_\n" if $error eq 'warn';
	return ();
    }
    elsif ($_ eq '') {       # AIX, and Linux return nothing
	return () unless defined $error;
	&$error("No such file or directory") if ref($error) eq 'CODE';
	warn "Warning: No such file or directory\n" if $error eq 'warn';
	return ();
    }
    else {
        # parse failed, check if the dosftp parse understands it
        File::Listing::dosftp->init();
        return(File::Listing::dosftp->line($_,$tz,$error));
    }

}



package File::Listing::dosftp;

use HTTP::Date qw(str2time);

use vars qw($curdir @ISA);

@ISA = qw(File::Listing);



sub init
{
    $curdir = '';
}


sub line
{
    shift; # package name
    local($_) = shift;
    my($tz, $error) = @_;

    s/\015//g;

    my ($date, $size_or_dir, $name, $size);

    # 02-05-96  10:48AM                 1415 src.slf
    # 09-10-96  09:18AM       <DIR>          sl_util
    if (($date, $size_or_dir, $name) =
        /^(\d\d-\d\d-\d\d\s+\d\d:\d\d\wM)         # Date and time info
         \s+                                      # Some space
         (<\w{3}>|\d+)                            # Dir or Size
         \s+                                      # Some more space
         (.+)$                                    # File name
        /x )
    {
	return if $name eq '.' || $name eq '..';
	$name = "$curdir/$name" if length $curdir;
	my $type = '?';
	if ($size_or_dir eq '<DIR>') {
	    $type = "d";
            $size = ""; # directories have no size in the pc listing
        }
        else {
	    $type = 'f';
            $size = $size_or_dir;
	}
	return [$name, $type, $size, str2time($date, $tz), undef];
    }
    else {
	return () unless defined $error;
	&$error($_) if ref($error) eq 'CODE';
	warn "Can't parse: $_\n" if $error eq 'warn';
	return ();
    }

}



package File::Listing::vms;
@File::Listing::vms::ISA = qw(File::Listing);

package File::Listing::netware;
@File::Listing::netware::ISA = qw(File::Listing);



package File::Listing::apache;

use vars qw(@ISA);

@ISA = qw(File::Listing);


sub init { }


sub line {
    shift; # package name
    local($_) = shift;
    my($tz, $error) = @_; # ignored for now...

    if (m!<A\s+HREF=\"([^\"]+)\">.*</A>.*?(\d+)-([a-zA-Z]+|\d+)-(\d+)\s+(\d+):(\d+)\s+(?:([\d\.]+[kMG]?|-))!i) {
	my($filename, $filesize) = ($1, $7);
	my($d,$m,$y, $H,$M) = ($2,$3,$4,$5,$6);
	if ($m =~ /^\d+$/) {
	    ($d,$y) = ($y,$d) # iso date
	}
	else {
	    $m = _monthabbrev_number($m);
	}

	$filesize = 0 if $filesize eq '-';
	if ($filesize =~ s/k$//i) {
	    $filesize *= 1024;
	}
	elsif ($filesize =~ s/M$//) {
	    $filesize *= 1024*1024;
	}
	elsif ($filesize =~ s/G$//) {
	    $filesize *= 1024*1024*1024;
	}
	$filesize = int $filesize;

	require Time::Local;
	my $filetime = Time::Local::timelocal(0,$M,$H,$d,$m-1,_guess_year($y)-1900);
	my $filetype = ($filename =~ s|/$|| ? "d" : "f");
	return [$filename, $filetype, $filesize, $filetime, undef];
    }

    return ();
}


sub _guess_year {
    my $y = shift;
    if ($y >= 90) {
	$y = 1900+$y;
    }
    elsif ($y < 100) {
	$y = 2000+$y;
    }
    $y;
}


sub _monthabbrev_number {
    my $mon = shift;
    +{'Jan' => 1,
      'Feb' => 2,
      'Mar' => 3,
      'Apr' => 4,
      'May' => 5,
      'Jun' => 6,
      'Jul' => 7,
      'Aug' => 8,
      'Sep' => 9,
      'Oct' => 10,
      'Nov' => 11,
      'Dec' => 12,
     }->{$mon};
}


1;

__END__

