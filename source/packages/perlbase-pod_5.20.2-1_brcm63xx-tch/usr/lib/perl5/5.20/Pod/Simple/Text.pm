
require 5;
package Pod::Simple::Text;
use strict;
use Carp ();
use Pod::Simple::Methody ();
use Pod::Simple ();
use vars qw( @ISA $VERSION $FREAKYMODE);
$VERSION = '3.28';
@ISA = ('Pod::Simple::Methody');
BEGIN { *DEBUG = defined(&Pod::Simple::DEBUG)
          ? \&Pod::Simple::DEBUG
          : sub() {0}
      }

use Text::Wrap 98.112902 ();
$Text::Wrap::wrap = 'overflow';

sub new {
  my $self = shift;
  my $new = $self->SUPER::new(@_);
  $new->{'output_fh'} ||= *STDOUT{IO};
  $new->accept_target_as_text(qw( text plaintext plain ));
  $new->nix_X_codes(1);
  $new->nbsp_for_S(1);
  $new->{'Thispara'} = '';
  $new->{'Indent'} = 0;
  $new->{'Indentstring'} = '   ';
  return $new;
}


sub handle_text {  $_[0]{'Thispara'} .= $_[1] }

sub start_Para  {  $_[0]{'Thispara'} = '' }
sub start_head1 {  $_[0]{'Thispara'} = '' }
sub start_head2 {  $_[0]{'Thispara'} = '' }
sub start_head3 {  $_[0]{'Thispara'} = '' }
sub start_head4 {  $_[0]{'Thispara'} = '' }

sub start_Verbatim    { $_[0]{'Thispara'} = ''   }
sub start_item_bullet { $_[0]{'Thispara'} = $FREAKYMODE ? '' : '* ' }
sub start_item_number { $_[0]{'Thispara'} = $FREAKYMODE ? '' : "$_[1]{'number'}. "  }
sub start_item_text   { $_[0]{'Thispara'} = ''   }

sub start_over_bullet  { ++$_[0]{'Indent'} }
sub start_over_number  { ++$_[0]{'Indent'} }
sub start_over_text    { ++$_[0]{'Indent'} }
sub start_over_block   { ++$_[0]{'Indent'} }

sub   end_over_bullet  { --$_[0]{'Indent'} }
sub   end_over_number  { --$_[0]{'Indent'} }
sub   end_over_text    { --$_[0]{'Indent'} }
sub   end_over_block   { --$_[0]{'Indent'} }



sub end_head1       { $_[0]->emit_par(-4) }
sub end_head2       { $_[0]->emit_par(-3) }
sub end_head3       { $_[0]->emit_par(-2) }
sub end_head4       { $_[0]->emit_par(-1) }
sub end_Para        { $_[0]->emit_par( 0) }
sub end_item_bullet { $_[0]->emit_par( 0) }
sub end_item_number { $_[0]->emit_par( 0) }
sub end_item_text   { $_[0]->emit_par(-2) }
sub start_L         { $_[0]{'Link'} = $_[1] if $_[1]->{type} eq 'url' }
sub end_L           {
    if (my $link = delete $_[0]{'Link'}) {
        # Append the URL to the output unless it's already present.
        $_[0]{'Thispara'} .= " <$link->{to}>"
            unless $_[0]{'Thispara'} =~ /\b\Q$link->{to}/;
    }
}

sub emit_par {
  my($self, $tweak_indent) = splice(@_,0,2);
  my $indent = ' ' x ( 2 * $self->{'Indent'} + 4 + ($tweak_indent||0) );
   # Yes, 'STRING' x NEGATIVE gives '', same as 'STRING' x 0

  $self->{'Thispara'} =~ tr{\xAD}{}d if Pod::Simple::ASCII;
  my $out = Text::Wrap::wrap($indent, $indent, $self->{'Thispara'} .= "\n");
  $out =~ tr{\xA0}{ } if Pod::Simple::ASCII;
  print {$self->{'output_fh'}} $out, "\n";
  $self->{'Thispara'} = '';
  
  return;
}


sub end_Verbatim  {
  my $self = shift;
  if(Pod::Simple::ASCII) {
    $self->{'Thispara'} =~ tr{\xA0}{ };
    $self->{'Thispara'} =~ tr{\xAD}{}d;
  }

  my $i = ' ' x ( 2 * $self->{'Indent'} + 4);
  #my $i = ' ' x (4 + $self->{'Indent'});
  
  $self->{'Thispara'} =~ s/^/$i/mg;
  
  print { $self->{'output_fh'} }   '', 
    $self->{'Thispara'},
    "\n\n"
  ;
  $self->{'Thispara'} = '';
  return;
}

1;


__END__

