package FileCache;

our $VERSION = '1.09';


require 5.006;
use Carp;
use strict;
no strict 'refs';

use vars qw(%saw $cacheout_maxopen);
$cacheout_maxopen = 16;

use parent 'Exporter';
our @EXPORT = qw[cacheout cacheout_close];


my %isopen;
my $cacheout_seq = 0;

sub import {
    my ($pkg,%args) = @_;

    # Use Exporter. %args are for us, not Exporter.
    # Make sure to up export_to_level, or we will import into ourselves,
    # rather than our calling package;

    __PACKAGE__->export_to_level(1);
    Exporter::import( $pkg );

    # Truth is okay here because setting maxopen to 0 would be bad
    return $cacheout_maxopen = $args{maxopen} if $args{maxopen};

    # XXX This code is crazy.  Why is it a one element foreach loop?
    # Why is it using $param both as a filename and filehandle?
    foreach my $param ( '/usr/include/sys/param.h' ){
      if (open($param, '<', $param)) {
	local ($_, $.);
	while (<$param>) {
	  if( /^\s*#\s*define\s+NOFILE\s+(\d+)/ ){
	    $cacheout_maxopen = $1 - 4;
	    close($param);
	    last;
	  }
	}
	close $param;
      }
    }
    $cacheout_maxopen ||= 16;
}

sub cacheout_open {
  return open(*{caller(1) . '::' . $_[1]}, $_[0], $_[1]) && $_[1];
}

sub cacheout_close {
  # Short-circuit in case the filehandle disappeared
  my $pkg = caller($_[1]||0);
  defined fileno(*{$pkg . '::' . $_[0]}) &&
    CORE::close(*{$pkg . '::' . $_[0]});
  delete $isopen{$_[0]};
}

sub cacheout {
    my($mode, $file, $class, $ret, $ref, $narg);
    croak "Not enough arguments for cacheout"  unless $narg = scalar @_;
    croak "Too many arguments for cacheout"    if $narg > 2;

    ($mode, $file) = @_;
    ($file, $mode) = ($mode, $file) if $narg == 1;
    croak "Invalid mode for cacheout" if $mode &&
      ( $mode !~ /^\s*(?:>>|\+?>|\+?<|\|\-|)|\-\|\s*$/ );

    # Mode changed?
    if( $isopen{$file} && ($mode||'>') ne $isopen{$file}->[1] ){
      &cacheout_close($file, 1);
    }

    if( $isopen{$file}) {
      $ret = $file;
      $isopen{$file}->[0]++;
    }
    else{
      if( scalar keys(%isopen) > $cacheout_maxopen -1 ) {
	my @lru = sort{ $isopen{$a}->[0] <=> $isopen{$b}->[0] } keys(%isopen);
	$cacheout_seq = 0;
	$isopen{$_}->[0] = $cacheout_seq++ for
	  splice(@lru, int($cacheout_maxopen / 3)||$cacheout_maxopen);
	&cacheout_close($_, 1) for @lru;
      }

      unless( $ref ){
	$mode ||= $saw{$file} ? '>>' : ($saw{$file}=1, '>');
      }
      #XXX should we just return the value from cacheout_open, no croak?
      $ret = cacheout_open($mode, $file) or croak("Can't create $file: $!");

      $isopen{$file} = [++$cacheout_seq, $mode];
    }
    return $ret;
}
1;
