use 5.006_001;			# for (defined ref) and $#$v and our
package Dumpvalue;
use strict;
our $VERSION = '1.17';
our(%address, $stab, @stab, %stab, %subs);





my %defaults = (
		globPrint	      => 0,
		printUndef	      => 1,
		tick		      => "auto",
		unctrl		      => 'quote',
		subdump		      => 1,
		dumpReused	      => 0,
		bareStringify	      => 1,
		hashDepth	      => '',
		arrayDepth	      => '',
		dumpDBFiles	      => '',
		dumpPackages	      => '',
		quoteHighBit	      => '',
		usageOnly	      => '',
		compactDump	      => '',
		veryCompact	      => '',
		stopDbSignal	      => '',
	       );

sub new {
  my $class = shift;
  my %opt = (%defaults, @_);
  bless \%opt, $class;
}

sub set {
  my $self = shift;
  my %opt = @_;
  @$self{keys %opt} = values %opt;
}

sub get {
  my $self = shift;
  wantarray ? @$self{@_} : $$self{pop @_};
}

sub dumpValue {
  my $self = shift;
  die "usage: \$dumper->dumpValue(value)" unless @_ == 1;
  local %address;
  local $^W=0;
  (print "undef\n"), return unless defined $_[0];
  (print $self->stringify($_[0]), "\n"), return unless ref $_[0];
  $self->unwrap($_[0],0);
}

sub dumpValues {
  my $self = shift;
  local %address;
  local $^W=0;
  (print "undef\n"), return unless defined $_[0];
  $self->unwrap(\@_,0);
}


sub unctrl {
  local($_) = @_;

  return \$_ if ref \$_ eq "GLOB";
  s/([\001-\037\177])/'^'.pack('c',ord($1)^64)/eg;
  $_;
}

sub stringify {
  my $self = shift;
  local $_ = shift;
  my $noticks = shift;
  my $tick = $self->{tick};

  return 'undef' unless defined $_ or not $self->{printUndef};
  return $_ . "" if ref \$_ eq 'GLOB';
  { no strict 'refs';
    $_ = &{'overload::StrVal'}($_)
      if $self->{bareStringify} and ref $_
	and %overload:: and defined &{'overload::StrVal'};
  }

  if ($tick eq 'auto') {
    if (/[\000-\011\013-\037\177]/) {
      $tick = '"';
    } else {
      $tick = "'";
    }
  }
  if ($tick eq "'") {
    s/([\'\\])/\\$1/g;
  } elsif ($self->{unctrl} eq 'unctrl') {
    s/([\"\\])/\\$1/g ;
    s/([\000-\037\177])/'^'.pack('c',ord($1)^64)/eg;
    s/([\200-\377])/'\\0x'.sprintf('%2X',ord($1))/eg
      if $self->{quoteHighBit};
  } elsif ($self->{unctrl} eq 'quote') {
    s/([\"\\\$\@])/\\$1/g if $tick eq '"';
    s/\033/\\e/g;
    s/([\000-\037\177])/'\\c'.chr(ord($1)^64)/eg;
  }
  s/([\200-\377])/'\\'.sprintf('%3o',ord($1))/eg if $self->{quoteHighBit};
  ($noticks || /^\d+(\.\d*)?\Z/)
    ? $_
      : $tick . $_ . $tick;
}

sub DumpElem {
  my ($self, $v) = (shift, shift);
  my $short = $self->stringify($v, ref $v);
  my $shortmore = '';
  if ($self->{veryCompact} && ref $v
      && (ref $v eq 'ARRAY' and !grep(ref $_, @$v) )) {
    my $depth = $#$v;
    ($shortmore, $depth) = (' ...', $self->{arrayDepth} - 1)
      if $self->{arrayDepth} and $depth >= $self->{arrayDepth};
    my @a = map $self->stringify($_), @$v[0..$depth];
    print "0..$#{$v}  @a$shortmore\n";
  } elsif ($self->{veryCompact} && ref $v
	   && (ref $v eq 'HASH') and !grep(ref $_, values %$v)) {
    my @a = sort keys %$v;
    my $depth = $#a;
    ($shortmore, $depth) = (' ...', $self->{hashDepth} - 1)
      if $self->{hashDepth} and $depth >= $self->{hashDepth};
    my @b = map {$self->stringify($_) . " => " . $self->stringify($$v{$_})}
      @a[0..$depth];
    local $" = ', ';
    print "@b$shortmore\n";
  } else {
    print "$short\n";
    $self->unwrap($v,shift);
  }
}

sub unwrap {
  my $self = shift;
  return if $DB::signal and $self->{stopDbSignal};
  my ($v) = shift ;
  my ($s) = shift ;		# extra no of spaces
  my $sp;
  my (%v,@v,$address,$short,$fileno);

  $sp = " " x $s ;
  $s += 3 ;

  # Check for reused addresses
  if (ref $v) {
    my $val = $v;
    { no strict 'refs';
      $val = &{'overload::StrVal'}($v)
	if %overload:: and defined &{'overload::StrVal'};
    }
    ($address) = $val =~ /(0x[0-9a-f]+)\)$/ ;
    if (!$self->{dumpReused} && defined $address) {
      $address{$address}++ ;
      if ( $address{$address} > 1 ) {
	print "${sp}-> REUSED_ADDRESS\n" ;
	return ;
      }
    }
  } elsif (ref \$v eq 'GLOB') {
    $address = "$v" . "";	# To avoid a bug with globs
    $address{$address}++ ;
    if ( $address{$address} > 1 ) {
      print "${sp}*DUMPED_GLOB*\n" ;
      return ;
    }
  }

  if (ref $v eq 'Regexp') {
    my $re = "$v";
    $re =~ s,/,\\/,g;
    print "$sp-> qr/$re/\n";
    return;
  }

  if ( UNIVERSAL::isa($v, 'HASH') ) {
    my @sortKeys = sort keys(%$v) ;
    my $more;
    my $tHashDepth = $#sortKeys ;
    $tHashDepth = $#sortKeys < $self->{hashDepth}-1 ? $#sortKeys : $self->{hashDepth}-1
      unless $self->{hashDepth} eq '' ;
    $more = "....\n" if $tHashDepth < $#sortKeys ;
    my $shortmore = "";
    $shortmore = ", ..." if $tHashDepth < $#sortKeys ;
    $#sortKeys = $tHashDepth ;
    if ($self->{compactDump} && !grep(ref $_, values %{$v})) {
      $short = $sp;
      my @keys;
      for (@sortKeys) {
	push @keys, $self->stringify($_) . " => " . $self->stringify($v->{$_});
      }
      $short .= join ', ', @keys;
      $short .= $shortmore;
      (print "$short\n"), return if length $short <= $self->{compactDump};
    }
    for my $key (@sortKeys) {
      return if $DB::signal and $self->{stopDbSignal};
      my $value = $ {$v}{$key} ;
      print $sp, $self->stringify($key), " => ";
      $self->DumpElem($value, $s);
    }
    print "$sp  empty hash\n" unless @sortKeys;
    print "$sp$more" if defined $more ;
  } elsif ( UNIVERSAL::isa($v, 'ARRAY') ) {
    my $tArrayDepth = $#{$v} ;
    my $more ;
    $tArrayDepth = $#$v < $self->{arrayDepth}-1 ? $#$v : $self->{arrayDepth}-1
      unless  $self->{arrayDepth} eq '' ;
    $more = "....\n" if $tArrayDepth < $#{$v} ;
    my $shortmore = "";
    $shortmore = " ..." if $tArrayDepth < $#{$v} ;
    if ($self->{compactDump} && !grep(ref $_, @{$v})) {
      if ($#$v >= 0) {
	$short = $sp . "0..$#{$v}  " .
	  join(" ", 
	       map {exists $v->[$_] ? $self->stringify($v->[$_]) : "empty"} (0..$tArrayDepth)
	      ) . "$shortmore";
      } else {
	$short = $sp . "empty array";
      }
      (print "$short\n"), return if length $short <= $self->{compactDump};
    }
    for my $num (0 .. $tArrayDepth) {
      return if $DB::signal and $self->{stopDbSignal};
      print "$sp$num  ";
      if (exists $v->[$num]) {
        $self->DumpElem($v->[$num], $s);
      } else {
	print "empty slot\n";
      }
    }
    print "$sp  empty array\n" unless @$v;
    print "$sp$more" if defined $more ;
  } elsif (  UNIVERSAL::isa($v, 'SCALAR') or ref $v eq 'REF' ) {
    print "$sp-> ";
    $self->DumpElem($$v, $s);
  } elsif ( UNIVERSAL::isa($v, 'CODE') ) {
    print "$sp-> ";
    $self->dumpsub(0, $v);
  } elsif ( UNIVERSAL::isa($v, 'GLOB') ) {
    print "$sp-> ",$self->stringify($$v,1),"\n";
    if ($self->{globPrint}) {
      $s += 3;
      $self->dumpglob('', $s, "{$$v}", $$v, 1);
    } elsif (defined ($fileno = fileno($v))) {
      print( (' ' x ($s+3)) .  "FileHandle({$$v}) => fileno($fileno)\n" );
    }
  } elsif (ref \$v eq 'GLOB') {
    if ($self->{globPrint}) {
      $self->dumpglob('', $s, "{$v}", $v, 1);
    } elsif (defined ($fileno = fileno(\$v))) {
      print( (' ' x $s) .  "FileHandle({$v}) => fileno($fileno)\n" );
    }
  }
}

sub matchvar {
  $_[0] eq $_[1] or
    ($_[1] =~ /^([!~])(.)([\x00-\xff]*)/) and
      ($1 eq '!') ^ (eval {($_[2] . "::" . $_[0]) =~ /$2$3/});
}

sub compactDump {
  my $self = shift;
  $self->{compactDump} = shift if @_;
  $self->{compactDump} = 6*80-1 
    if $self->{compactDump} and $self->{compactDump} < 2;
  $self->{compactDump};
}

sub veryCompact {
  my $self = shift;
  $self->{veryCompact} = shift if @_;
  $self->compactDump(1) if !$self->{compactDump} and $self->{veryCompact};
  $self->{veryCompact};
}

sub set_unctrl {
  my $self = shift;
  if (@_) {
    my $in = shift;
    if ($in eq 'unctrl' or $in eq 'quote') {
      $self->{unctrl} = $in;
    } else {
      print "Unknown value for 'unctrl'.\n";
    }
  }
  $self->{unctrl};
}

sub set_quote {
  my $self = shift;
  if (@_ and $_[0] eq '"') {
    $self->{tick} = '"';
    $self->{unctrl} = 'quote';
  } elsif (@_ and $_[0] eq 'auto') {
    $self->{tick} = 'auto';
    $self->{unctrl} = 'quote';
  } elsif (@_) {		# Need to set
    $self->{tick} = "'";
    $self->{unctrl} = 'unctrl';
  }
  $self->{tick};
}

sub dumpglob {
  my $self = shift;
  return if $DB::signal and $self->{stopDbSignal};
  my ($package, $off, $key, $val, $all) = @_;
  local(*stab) = $val;
  my $fileno;
  if (($key !~ /^_</ or $self->{dumpDBFiles}) and defined $stab) {
    print( (' ' x $off) . "\$", &unctrl($key), " = " );
    $self->DumpElem($stab, 3+$off);
  }
  if (($key !~ /^_</ or $self->{dumpDBFiles}) and @stab) {
    print( (' ' x $off) . "\@$key = (\n" );
    $self->unwrap(\@stab,3+$off) ;
    print( (' ' x $off) .  ")\n" );
  }
  if ($key ne "main::" && $key ne "DB::" && %stab
      && ($self->{dumpPackages} or $key !~ /::$/)
      && ($key !~ /^_</ or $self->{dumpDBFiles})
      && !($package eq "Dumpvalue" and $key eq "stab")) {
    print( (' ' x $off) . "\%$key = (\n" );
    $self->unwrap(\%stab,3+$off) ;
    print( (' ' x $off) .  ")\n" );
  }
  if (defined ($fileno = fileno(*stab))) {
    print( (' ' x $off) .  "FileHandle($key) => fileno($fileno)\n" );
  }
  if ($all) {
    if (defined &stab) {
      $self->dumpsub($off, $key);
    }
  }
}

sub CvGV_name {
  my $self = shift;
  my $in = shift;
  return if $self->{skipCvGV};	# Backdoor to avoid problems if XS broken...
  $in = \&$in;			# Hard reference...
  eval {require Devel::Peek; 1} or return;
  my $gv = Devel::Peek::CvGV($in) or return;
  *$gv{PACKAGE} . '::' . *$gv{NAME};
}

sub dumpsub {
  my $self = shift;
  my ($off,$sub) = @_;
  my $ini = $sub;
  my $s;
  $sub = $1 if $sub =~ /^\{\*(.*)\}$/;
  my $subref = defined $1 ? \&$sub : \&$ini;
  my $place = $DB::sub{$sub} || (($s = $subs{"$subref"}) && $DB::sub{$s})
    || (($s = $self->CvGV_name($subref)) && $DB::sub{$s})
    || ($self->{subdump} && ($s = $self->findsubs("$subref"))
	&& $DB::sub{$s});
  $s = $sub unless defined $s;
  $place = '???' unless defined $place;
  print( (' ' x $off) .  "&$s in $place\n" );
}

sub findsubs {
  my $self = shift;
  return undef unless %DB::sub;
  my ($addr, $name, $loc);
  while (($name, $loc) = each %DB::sub) {
    $addr = \&$name;
    $subs{"$addr"} = $name;
  }
  $self->{subdump} = 0;
  $subs{ shift() };
}

sub dumpvars {
  my $self = shift;
  my ($package,@vars) = @_;
  local(%address,$^W);
  my ($key,$val);
  $package .= "::" unless $package =~ /::$/;
  *stab = *main::;

  while ($package =~ /(\w+?::)/g) {
    *stab = $ {stab}{$1};
  }
  $self->{TotalStrings} = 0;
  $self->{Strings} = 0;
  $self->{CompleteTotal} = 0;
  while (($key,$val) = each(%stab)) {
    return if $DB::signal and $self->{stopDbSignal};
    next if @vars && !grep( matchvar($key, $_), @vars );
    if ($self->{usageOnly}) {
      $self->globUsage(\$val, $key)
	if ($package ne 'Dumpvalue' or $key ne 'stab')
	   and ref(\$val) eq 'GLOB';
    } else {
      $self->dumpglob($package, 0,$key, $val);
    }
  }
  if ($self->{usageOnly}) {
    print <<EOP;
String space: $self->{TotalStrings} bytes in $self->{Strings} strings.
EOP
    $self->{CompleteTotal} += $self->{TotalStrings};
    print <<EOP;
Grand total = $self->{CompleteTotal} bytes (1 level deep) + overhead.
EOP
  }
}

sub scalarUsage {
  my $self = shift;
  my $size;
  if (UNIVERSAL::isa($_[0], 'ARRAY')) {
	$size = $self->arrayUsage($_[0]);
  } elsif (UNIVERSAL::isa($_[0], 'HASH')) {
	$size = $self->hashUsage($_[0]);
  } elsif (!ref($_[0])) {
	$size = length($_[0]);
  }
  $self->{TotalStrings} += $size;
  $self->{Strings}++;
  $size;
}

sub arrayUsage {		# array ref, name
  my $self = shift;
  my $size = 0;
  map {$size += $self->scalarUsage($_)} @{$_[0]};
  my $len = @{$_[0]};
  print "\@$_[1] = $len item", ($len > 1 ? "s" : ""), " (data: $size bytes)\n"
      if defined $_[1];
  $self->{CompleteTotal} +=  $size;
  $size;
}

sub hashUsage {			# hash ref, name
  my $self = shift;
  my @keys = keys %{$_[0]};
  my @values = values %{$_[0]};
  my $keys = $self->arrayUsage(\@keys);
  my $values = $self->arrayUsage(\@values);
  my $len = @keys;
  my $total = $keys + $values;
  print "\%$_[1] = $len item", ($len > 1 ? "s" : ""),
    " (keys: $keys; values: $values; total: $total bytes)\n"
      if defined $_[1];
  $total;
}

sub globUsage {			# glob ref, name
  my $self = shift;
  local *stab = *{$_[0]};
  my $total = 0;
  $total += $self->scalarUsage($stab) if defined $stab;
  $total += $self->arrayUsage(\@stab, $_[1]) if @stab;
  $total += $self->hashUsage(\%stab, $_[1]) 
    if %stab and $_[1] ne "main::" and $_[1] ne "DB::";	
  #and !($package eq "Dumpvalue" and $key eq "stab"));
  $total;
}

1;


