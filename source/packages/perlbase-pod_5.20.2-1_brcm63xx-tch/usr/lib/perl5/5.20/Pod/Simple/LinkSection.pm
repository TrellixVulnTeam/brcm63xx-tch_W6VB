
require 5;
package Pod::Simple::LinkSection;
  # Based somewhat dimly on Array::Autojoin
use vars qw($VERSION );
$VERSION = '3.28';

use strict;
use Pod::Simple::BlackBox;
use vars qw($VERSION );
$VERSION = '3.28';

use overload( # So it'll stringify nice
  '""'   => \&Pod::Simple::BlackBox::stringify_lol,
  'bool' => \&Pod::Simple::BlackBox::stringify_lol,
  # '.='   => \&tack_on,  # grudgingly support
  
  'fallback' => 1,         # turn on cleverness
);

sub tack_on {
  $_[0] = ['', {}, "$_[0]" ];
  return $_[0][2] .= $_[1];
}

sub as_string {
  goto &Pod::Simple::BlackBox::stringify_lol;
}
sub stringify {
  goto &Pod::Simple::BlackBox::stringify_lol;
}

sub new {
  my $class = shift;
  $class = ref($class) || $class;
  my $new;
  if(@_ == 1) {
    if (!ref($_[0] || '')) { # most common case: one bare string
      return bless ['', {}, $_[0] ], $class;
    } elsif( ref($_[0] || '') eq 'ARRAY') {
      $new = [ @{ $_[0] } ];
    } else {
      Carp::croak( "$class new() doesn't know to clone $new" );
    }
  } else { # misc stuff
    $new = [ '', {}, @_ ];
  }

  # By now it's a treelet:  [ 'foo', {}, ... ]
  foreach my $x (@$new) {
    if(ref($x || '') eq 'ARRAY') {
      $x = $class->new($x); # recurse
    } elsif(ref($x || '') eq 'HASH') {
      $x = { %$x };
    }
     # otherwise leave it.
  }

  return bless $new, $class;
}


1;

__END__



__END__

