package PerlIO;

our $VERSION = '1.09';

our %alias;

sub import
{
 my $class = shift;
 while (@_)
  {
   my $layer = shift;
   if (exists $alias{$layer})
    {
     $layer = $alias{$layer}
    }
   else
    {
     $layer = "${class}::$layer";
    }
   eval { require $layer =~ s{::}{/}gr . '.pm' };
   warn $@ if $@;
  }
}

sub F_UTF8 () { 0x8000 }

1;
__END__

