package DBM_Filter ;

use strict;
use warnings;
our $VERSION = '0.06';

package Tie::Hash ;

use strict;
use warnings;

use Carp;


our %LayerStack = ();
our %origDESTROY = ();

our %Filters = map { $_, undef } qw(
            Fetch_Key
            Fetch_Value
            Store_Key
            Store_Value
	);

our %Options = map { $_, 1 } qw(
            fetch
            store
	);


sub Filtered
{
    my $this = shift;
    return defined $LayerStack{$this} ;
}

sub Filter_Pop
{
    my $this = shift;
    my $stack = $LayerStack{$this} || return undef ;
    my $filter = pop @{ $stack };

    # remove the filter hooks if this is the last filter to pop
    if ( @{ $stack } == 0 ) {
        $this->filter_store_key  ( undef );
        $this->filter_store_value( undef );
        $this->filter_fetch_key  ( undef );
        $this->filter_fetch_value( undef );
        delete $LayerStack{$this};
    }

    return $filter;
}

sub Filter_Key_Push
{
    &_do_Filter_Push;
}

sub Filter_Value_Push
{
    &_do_Filter_Push;
}


sub Filter_Push
{
    &_do_Filter_Push;
}

sub _do_Filter_Push
{
    my $this = shift;
    my %callbacks = ();
    my $caller = (caller(1))[3];
    $caller =~ s/^.*:://;
 
    croak "$caller: no parameters present" unless @_ ;

    if ( ! $Options{lc $_[0]} ) {
        my $class = shift;
        my @params = @_;

        # if $class already contains "::", don't prefix "DBM_Filter::"
        $class = "DBM_Filter::$class" unless $class =~ /::/;
    
        no strict 'refs';
        # does the "DBM_Filter::$class" exist?
	if ( ! %{ "${class}::"} ) {
	    # Nope, so try to load it.
            eval " require $class ; " ;
            croak "$caller: Cannot Load DBM Filter '$class': $@" if $@;
        }
    
        my $fetch  = *{ "${class}::Fetch"  }{CODE};
        my $store  = *{ "${class}::Store"  }{CODE};
        my $filter = *{ "${class}::Filter" }{CODE};
        use strict 'refs';

        my $count = defined($filter) + defined($store) + defined($fetch) ;

        if ( $count == 0 )
          { croak "$caller: No methods (Filter, Fetch or Store) found in class '$class'" }
        elsif ( $count == 1 && ! defined $filter) {
           my $need = defined($fetch) ? 'Store' : 'Fetch';
           croak "$caller: Missing method '$need' in class '$class'" ;
        }
        elsif ( $count >= 2 && defined $filter)
          { croak "$caller: Can't mix Filter with Store and Fetch in class '$class'" }

        if (defined $filter) {
            my $callbacks = &{ $filter }(@params);
            croak "$caller: '${class}::Filter' did not return a hash reference" 
                unless ref $callbacks && ref $callbacks eq 'HASH';
            %callbacks = %{ $callbacks } ;
        }
        else {
            $callbacks{Fetch} = $fetch;
            $callbacks{Store} = $store;
        }
    }
    else {
        croak "$caller: not even params" unless @_ % 2 == 0;
        %callbacks = @_;
    }
    
    my %filters = %Filters ;
    my @got = ();
    while (my ($k, $v) = each %callbacks )
    {
        my $key = $k;
        $k = lc $k;
        if ($k eq 'fetch') {
            push @got, 'Fetch';
            if ($caller eq 'Filter_Push')
              { $filters{Fetch_Key} = $filters{Fetch_Value} = $v }
            elsif ($caller eq 'Filter_Key_Push')
              { $filters{Fetch_Key} = $v }
            elsif ($caller eq 'Filter_Value_Push')
              { $filters{Fetch_Value} = $v }
        }
        elsif ($k eq 'store') {
            push @got, 'Store';
            if ($caller eq 'Filter_Push')
              { $filters{Store_Key} = $filters{Store_Value} = $v }
            elsif ($caller eq 'Filter_Key_Push')
              { $filters{Store_Key} = $v }
            elsif ($caller eq 'Filter_Value_Push')
              { $filters{Store_Value} = $v }
        }
        else
          { croak "$caller: Unknown key '$key'" }

        croak "$caller: value associated with key '$key' is not a code reference"
            unless ref $v && ref $v eq 'CODE';
    }

    if ( @got != 2 ) {
        push @got, 'neither' if @got == 0 ;
        croak "$caller: expected both Store & Fetch - got @got";
    }

    # remember the class
    push @{ $LayerStack{$this} }, \%filters ;

    my $str_this = "$this" ; # Avoid a closure with $this in the subs below

    $this->filter_store_key  ( sub { store_hook($str_this, 'Store_Key')   });
    $this->filter_store_value( sub { store_hook($str_this, 'Store_Value') });
    $this->filter_fetch_key  ( sub { fetch_hook($str_this, 'Fetch_Key')   });
    $this->filter_fetch_value( sub { fetch_hook($str_this, 'Fetch_Value') });

    # Hijack the callers DESTROY method
    $this =~ /^(.*)=/;
    my $type = $1 ;
    no strict 'refs';
    if ( *{ "${type}::DESTROY" }{CODE} ne \&MyDESTROY )
    {
        $origDESTROY{$type} = *{ "${type}::DESTROY" }{CODE};
        no warnings 'redefine';
        *{ "${type}::DESTROY" } = \&MyDESTROY ;
    }
}

sub store_hook
{
    my $this = shift ;
    my $type = shift ;
    foreach my $layer (@{ $LayerStack{$this} })
    {
        &{ $layer->{$type} }() if defined $layer->{$type} ;
    }
}

sub fetch_hook
{
    my $this = shift ;
    my $type = shift ;
    foreach my $layer (reverse @{ $LayerStack{$this} })
    {
        &{ $layer->{$type} }() if defined $layer->{$type} ;
    }
}

sub MyDESTROY
{
    my $this = shift ;
    delete $LayerStack{$this} ;

    # call real DESTROY
    $this =~ /^(.*)=/;
    &{ $origDESTROY{$1} }($this);
}

1;

__END__

