package NEXT;
$VERSION = '0.65';
use Carp;
use strict;
use overload ();

sub NEXT::ELSEWHERE::ancestors
{
	my @inlist = shift;
	my @outlist = ();
	while (my $next = shift @inlist) {
		push @outlist, $next;
		no strict 'refs';
		unshift @inlist, @{"$outlist[-1]::ISA"};
	}
	return @outlist;
}

sub NEXT::ELSEWHERE::ordered_ancestors
{
	my @inlist = shift;
	my @outlist = ();
	while (my $next = shift @inlist) {
		push @outlist, $next;
		no strict 'refs';
		push @inlist, @{"$outlist[-1]::ISA"};
	}
	return sort { $a->isa($b) ? -1
	            : $b->isa($a) ? +1
	            :                0 } @outlist;
}

sub NEXT::ELSEWHERE::buildAUTOLOAD
{
    my $autoload_name = caller() . '::AUTOLOAD';

    no strict 'refs';
    *{$autoload_name} = sub {
        my ($self) = @_;
        my $depth = 1;
        until (((caller($depth))[3]||q{}) !~ /^\(eval\)$/) { $depth++ }
        my $caller = (caller($depth))[3];
        my $wanted = $NEXT::AUTOLOAD || $autoload_name;
        undef $NEXT::AUTOLOAD;
        my ($caller_class, $caller_method) = do { $caller =~ m{(.*)::(.*)}g };
        my ($wanted_class, $wanted_method) = do { $wanted =~ m{(.*)::(.*)}g };
        croak "Can't call $wanted from $caller"
            unless $caller_method eq $wanted_method;

        my $key = ref $self && overload::Overloaded($self)
            ? overload::StrVal($self) : $self;

        local ($NEXT::NEXT{$key,$wanted_method}, $NEXT::SEEN) =
            ($NEXT::NEXT{$key,$wanted_method}, $NEXT::SEEN);

        unless ($NEXT::NEXT{$key,$wanted_method}) {
            my @forebears =
                NEXT::ELSEWHERE::ancestors ref $self || $self,
                            $wanted_class;
            while (@forebears) {
                last if shift @forebears eq $caller_class
            }
            no strict 'refs';
            @{$NEXT::NEXT{$key,$wanted_method}} =
                map {
                    my $stash = \%{"${_}::"};
                    ($stash->{$caller_method} && (*{$stash->{$caller_method}}{CODE}))
                        ? *{$stash->{$caller_method}}{CODE}
                        : () } @forebears
                    unless $wanted_method eq 'AUTOLOAD';
            @{$NEXT::NEXT{$key,$wanted_method}} =
                map {
                    my $stash = \%{"${_}::"};
                    ($stash->{AUTOLOAD} && (*{$stash->{AUTOLOAD}}{CODE}))
                        ? "${_}::AUTOLOAD"
                        : () } @forebears
                    unless @{$NEXT::NEXT{$key,$wanted_method}||[]};
            $NEXT::SEEN->{$key,*{$caller}{CODE}}++;
        }
        my $call_method = shift @{$NEXT::NEXT{$key,$wanted_method}};
        while (do { $wanted_class =~ /^NEXT\b.*\b(UNSEEN|DISTINCT)\b/ }
            && defined $call_method
            && $NEXT::SEEN->{$key,$call_method}++) {
            $call_method = shift @{$NEXT::NEXT{$key,$wanted_method}};
        }
        unless (defined $call_method) {
            return unless do { $wanted_class =~ /^NEXT:.*:ACTUAL/ };
            (local $Carp::CarpLevel)++;
            croak qq(Can't locate object method "$wanted_method" ),
                qq(via package "$caller_class");
        };
        return $self->$call_method(@_[1..$#_]) if ref $call_method eq 'CODE';
        no strict 'refs';
        do { ($wanted_method=${$caller_class."::AUTOLOAD"}) =~ s/.*::// }
            if $wanted_method eq 'AUTOLOAD';
        $$call_method = $caller_class."::NEXT::".$wanted_method;
        return $call_method->(@_);
    };
}

no strict 'vars';
package NEXT;                                  NEXT::ELSEWHERE::buildAUTOLOAD();
package NEXT::UNSEEN;		@ISA = 'NEXT';     NEXT::ELSEWHERE::buildAUTOLOAD();
package NEXT::DISTINCT;		@ISA = 'NEXT';     NEXT::ELSEWHERE::buildAUTOLOAD();
package NEXT::ACTUAL;		@ISA = 'NEXT';     NEXT::ELSEWHERE::buildAUTOLOAD();
package NEXT::ACTUAL::UNSEEN;	@ISA = 'NEXT'; NEXT::ELSEWHERE::buildAUTOLOAD();
package NEXT::ACTUAL::DISTINCT;	@ISA = 'NEXT'; NEXT::ELSEWHERE::buildAUTOLOAD();
package NEXT::UNSEEN::ACTUAL;	@ISA = 'NEXT'; NEXT::ELSEWHERE::buildAUTOLOAD();
package NEXT::DISTINCT::ACTUAL;	@ISA = 'NEXT'; NEXT::ELSEWHERE::buildAUTOLOAD();

package EVERY;

sub EVERY::ELSEWHERE::buildAUTOLOAD {
    my $autoload_name = caller() . '::AUTOLOAD';

    no strict 'refs';
    *{$autoload_name} = sub {
        my ($self) = @_;
        my $depth = 1;
        until (((caller($depth))[3]||q{}) !~ /^\(eval\)$/) { $depth++ }
        my $caller = (caller($depth))[3];
        my $wanted = $EVERY::AUTOLOAD || $autoload_name;
        undef $EVERY::AUTOLOAD;
        my ($wanted_class, $wanted_method) = do { $wanted =~ m{(.*)::(.*)}g };

        my $key = ref($self) && overload::Overloaded($self)
            ? overload::StrVal($self) : $self;

        local $NEXT::ALREADY_IN_EVERY{$key,$wanted_method} =
            $NEXT::ALREADY_IN_EVERY{$key,$wanted_method};

        return if $NEXT::ALREADY_IN_EVERY{$key,$wanted_method}++;

        my @forebears = NEXT::ELSEWHERE::ordered_ancestors ref $self || $self,
                                        $wanted_class;
        @forebears = reverse @forebears if do { $wanted_class =~ /\bLAST\b/ };
        no strict 'refs';
        my %seen;
        my @every = map { my $sub = "${_}::$wanted_method";
                    !*{$sub}{CODE} || $seen{$sub}++ ? () : $sub
                    } @forebears
                    unless $wanted_method eq 'AUTOLOAD';

        my $want = wantarray;
        if (@every) {
            if ($want) {
                return map {($_, [$self->$_(@_[1..$#_])])} @every;
            }
            elsif (defined $want) {
                return { map {($_, scalar($self->$_(@_[1..$#_])))}
                        @every
                    };
            }
            else {
                $self->$_(@_[1..$#_]) for @every;
                return;
            }
        }

        @every = map { my $sub = "${_}::AUTOLOAD";
                !*{$sub}{CODE} || $seen{$sub}++ ? () : "${_}::AUTOLOAD"
                } @forebears;
        if ($want) {
            return map { $$_ = ref($self)."::EVERY::".$wanted_method;
                    ($_, [$self->$_(@_[1..$#_])]);
                } @every;
        }
        elsif (defined $want) {
            return { map { $$_ = ref($self)."::EVERY::".$wanted_method;
                    ($_, scalar($self->$_(@_[1..$#_])))
                    } @every
                };
        }
        else {
            for (@every) {
                $$_ = ref($self)."::EVERY::".$wanted_method;
                $self->$_(@_[1..$#_]);
            }
            return;
        }
    };
}

package EVERY::LAST;   @ISA = 'EVERY';   EVERY::ELSEWHERE::buildAUTOLOAD();
package EVERY;         @ISA = 'NEXT';    EVERY::ELSEWHERE::buildAUTOLOAD();

1;

__END__

