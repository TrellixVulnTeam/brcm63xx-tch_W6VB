
require 5;
use 5.008;

package Pod::Simple::TranscodeSmart;
use strict;
use Pod::Simple;
require Encode;
use vars qw($VERSION );
$VERSION = '3.28';

sub is_dumb  {0}
sub is_smart {1}

sub all_encodings {
  return Encode::->encodings(':all');
}

sub encoding_is_available {
  return Encode::resolve_alias($_[1]);
}

sub encmodver {
  return "Encode.pm v" .($Encode::VERSION || '?');
}

sub make_transcoder {
  my $e = Encode::find_encoding($_[1]);
  die "WHAT ENCODING!?!?" unless $e;
  my $x;
  return sub {
    foreach $x (@_) {
      $x = $e->decode($x) unless Encode::is_utf8($x);
    }
    return;
  };
}


1;


