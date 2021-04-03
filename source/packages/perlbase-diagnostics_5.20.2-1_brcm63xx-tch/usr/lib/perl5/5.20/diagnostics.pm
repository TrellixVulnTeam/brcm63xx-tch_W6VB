package diagnostics;


use strict;
use 5.009001;
use Carp;
$Carp::Internal{__PACKAGE__.""}++;

our $VERSION = '1.34';
our $DEBUG;
our $VERBOSE;
our $PRETTY;
our $TRACEONLY = 0;
our $WARNTRACE = 0;

use Config;
use Text::Tabs 'expand';
my $privlib = $Config{privlibexp};
if ($^O eq 'VMS') {
    require VMS::Filespec;
    $privlib = VMS::Filespec::unixify($privlib);
}
my @trypod = (
	   "$privlib/pod/perldiag.pod",
	   "$privlib/pods/perldiag.pod",
	  );
unshift @trypod, "./pod/perldiag.pod" if -e "pod/perldiag.pod";
(my $PODFILE) = ((grep { -e } @trypod), $trypod[$#trypod])[0];

$DEBUG ||= 0;

local $| = 1;
local $_;
local $.;

my $standalone;
my(%HTML_2_Troff, %HTML_2_Latin_1, %HTML_2_ASCII_7);

CONFIG: {
    our $opt_p = our $opt_d = our $opt_v = our $opt_f = '';

    unless (caller) {
	$standalone++;
	require Getopt::Std;
	Getopt::Std::getopts('pdvf:')
	    or die "Usage: $0 [-v] [-p] [-f splainpod]";
	$PODFILE = $opt_f if $opt_f;
	$DEBUG = 2 if $opt_d;
	$VERBOSE = $opt_v;
	$PRETTY = $opt_p;
    }

    if (open(POD_DIAG, $PODFILE)) {
	warn "Happy happy podfile from real $PODFILE\n" if $DEBUG;
	last CONFIG;
    } 

    if (caller) {
	INCPATH: {
	    for my $file ( (map { "$_/".__PACKAGE__.".pm" } @INC), $0) {
		warn "Checking $file\n" if $DEBUG;
		if (open(POD_DIAG, $file)) {
		    while (<POD_DIAG>) {
			next unless
			    /^__END__\s*# wish diag dbase were more accessible/;
			print STDERR "podfile is $file\n" if $DEBUG;
			last INCPATH;
		    }
		}
	    } 
	}
    } else { 
	print STDERR "podfile is <DATA>\n" if $DEBUG;
	*POD_DIAG = *main::DATA;
    }
}
if (eof(POD_DIAG)) { 
    die "couldn't find diagnostic data in $PODFILE @INC $0";
}


%HTML_2_Troff = (
    'amp'	=>	'&',	#   ampersand
    'lt'	=>	'<',	#   left chevron, less-than
    'gt'	=>	'>',	#   right chevron, greater-than
    'quot'	=>	'"',	#   double quote

    "Aacute"	=>	"A\\*'",	#   capital A, acute accent
    # etc

);

%HTML_2_Latin_1 = (
    'amp'	=>	'&',	#   ampersand
    'lt'	=>	'<',	#   left chevron, less-than
    'gt'	=>	'>',	#   right chevron, greater-than
    'quot'	=>	'"',	#   double quote

    "Aacute"	=>	"\xC1"	#   capital A, acute accent

    # etc
);

%HTML_2_ASCII_7 = (
    'amp'	=>	'&',	#   ampersand
    'lt'	=>	'<',	#   left chevron, less-than
    'gt'	=>	'>',	#   right chevron, greater-than
    'quot'	=>	'"',	#   double quote

    "Aacute"	=>	"A"	#   capital A, acute accent
    # etc
);

our %HTML_Escapes;
*HTML_Escapes = do {
    if ($standalone) {
	$PRETTY ? \%HTML_2_Latin_1 : \%HTML_2_ASCII_7; 
    } else {
	\%HTML_2_Latin_1; 
    }
}; 

*THITHER = $standalone ? *STDOUT : *STDERR;

my %transfmt = (); 
my $transmo = <<EOFUNC;
sub transmo {
    #local \$^W = 0;  # recursive warnings we do NOT need!
EOFUNC

my %msg;
{
    print STDERR "FINISHING COMPILATION for $_\n" if $DEBUG;
    local $/ = '';
    local $_;
    my $header;
    my @headers;
    my $for_item;
    my $seen_body;
    while (<POD_DIAG>) {

	sub _split_pod_link {
	    $_[0] =~ m'(?:([^|]*)\|)?([^/]*)(?:/("?)(.*)\3)?'s;
	    ($1,$2,$4);
	}

	unescape();
	if ($PRETTY) {
	    sub noop   { return $_[0] }  # spensive for a noop
	    sub bold   { my $str =$_[0];  $str =~ s/(.)/$1\b$1/g; return $str; } 
	    sub italic { my $str = $_[0]; $str =~ s/(.)/_\b$1/g;  return $str; } 
	    s/C<<< (.*?) >>>|C<< (.*?) >>|[BC]<(.*?)>/bold($+)/ges;
	    s/[IF]<(.*?)>/italic($1)/ges;
	    s/L<(.*?)>/
	       my($text,$page,$sect) = _split_pod_link($1);
	       defined $text
	        ? $text
	        : defined $sect
	           ? italic($sect) . ' in ' . italic($page)
	           : italic($page)
	     /ges;
	     s/S<(.*?)>/
               $1
             /ges;
	} else {
	    s/C<<< (.*?) >>>|C<< (.*?) >>|[BC]<(.*?)>/$+/gs;
	    s/[IF]<(.*?)>/$1/gs;
	    s/L<(.*?)>/
	       my($text,$page,$sect) = _split_pod_link($1);
	       defined $text
	        ? $text
	        : defined $sect
	           ? qq '"$sect" in $page'
	           : $page
	     /ges;
	    s/S<(.*?)>/
               $1
             /ges;
	} 
	unless (/^=/) {
	    if (defined $header) { 
		if ( $header eq 'DESCRIPTION' && 
		    (   /Optional warnings are enabled/ 
		     || /Some of these messages are generic./
		    ) )
		{
		    next;
		}
		$_ = expand $_;
		s/^/    /gm;
		$msg{$header} .= $_;
		for my $h(@headers) { $msg{$h} .= $_ }
		++$seen_body;
	 	undef $for_item;	
	    }
	    next;
	} 

	# If we have not come across the body of the description yet, then
	# the previous header needs to share the same description.
	if ($seen_body) {
	    @headers = ();
	}
	else {
	    push @headers, $header if defined $header;
	}

	unless ( s/=item (.*?)\s*\z//s) {

	    if ( s/=head1\sDESCRIPTION//) {
		$msg{$header = 'DESCRIPTION'} = '';
		undef $for_item;
	    }
	    elsif( s/^=for\s+diagnostics\s*\n(.*?)\s*\z// ) {
		$for_item = $1;
	    }
	    elsif( /^=back/ ) { # Stop processing body here
		undef $header;
		undef $for_item;
		$seen_body = 0;
		next;
	    }
	    next;
	}

	if( $for_item ) { $header = $for_item; undef $for_item } 
	else {
	    $header = $1;

	    $header =~ s/\n/ /gs; # Allow multi-line headers
	}

	# strip formatting directives from =item line
	$header =~ s/[A-Z]<(.*?)>/$1/g;

	# Since we strip "(\.\s*)\n" when we search a warning, strip it here as well
	$header =~ s/(\.\s*)?$//;

        my @toks = split( /(%l?[dxX]|%[ucp]|%(?:\.\d+)?[fs])/, $header );
	if (@toks > 1) {
            my $conlen = 0;
            for my $i (0..$#toks){
                if( $i % 2 ){
                    if(      $toks[$i] eq '%c' ){
                        $toks[$i] = '.';
                    } elsif( $toks[$i] =~ /^%(?:d|u)$/ ){
                        $toks[$i] = '\d+';
                    } elsif( $toks[$i] =~ '^%(?:s|.*f)$' ){
                        $toks[$i] = $i == $#toks ? '.*' : '.*?';
                    } elsif( $toks[$i] =~ '%.(\d+)s' ){
                        $toks[$i] = ".{$1}";
                    } elsif( $toks[$i] =~ '^%l*([pxX])$' ){
                        $toks[$i] = $1 eq 'X' ? '[\dA-F]+' : '[\da-f]+';
                    }
                } elsif( length( $toks[$i] ) ){
                    $toks[$i] = quotemeta $toks[$i];
                    $conlen += length( $toks[$i] );
                }
            }  
            my $lhs = join( '', @toks );
            $lhs =~ s/(\\\s)+/\\s+/g; # Replace lit space with multi-space match
	    $transfmt{$header}{pat} =
              "    s^\\s*$lhs\\s*\Q$header\Es\n\t&& return 1;\n";
            $transfmt{$header}{len} = $conlen;
	} else {
            my $lhs = "\Q$header\E";
            $lhs =~ s/(\\\s)+/\\s+/g; # Replace lit space with multi-space match
            $transfmt{$header}{pat} =
	      "    s^\\s*$lhs\\s*\Q$header\E\n\t && return 1;\n";
            $transfmt{$header}{len} = length( $header );
	} 

	print STDERR __PACKAGE__.": Duplicate entry: \"$header\"\n"
	    if $msg{$header};

	$msg{$header} = '';
	$seen_body = 0;
    } 


    close POD_DIAG unless *main::DATA eq *POD_DIAG;

    die "No diagnostics?" unless %msg;

    # Apply patterns in order of decreasing sum of lengths of fixed parts
    # Seems the best way of hitting the right one.
    for my $hdr ( sort { $transfmt{$b}{len} <=> $transfmt{$a}{len} }
                  keys %transfmt ){
        $transmo .= $transfmt{$hdr}{pat};
    }
    $transmo .= "    return 0;\n}\n";
    print STDERR $transmo if $DEBUG;
    eval $transmo;
    die $@ if $@;
}

if ($standalone) {
    if (!@ARGV and -t STDIN) { print STDERR "$0: Reading from STDIN\n" } 
    while (defined (my $error = <>)) {
	splainthis($error) || print THITHER $error;
    } 
    exit;
} 

my $olddie;
my $oldwarn;

sub import {
    shift;
    $^W = 1; # yup, clobbered the global variable; 
	     # tough, if you want diags, you want diags.
    return if defined $SIG{__WARN__} && ($SIG{__WARN__} eq \&warn_trap);

    for (@_) {

	/^-d(ebug)?$/ 	   	&& do {
				    $DEBUG++;
				    next;
				   };

	/^-v(erbose)?$/ 	&& do {
				    $VERBOSE++;
				    next;
				   };

	/^-p(retty)?$/ 		&& do {
				    print STDERR "$0: I'm afraid it's too late for prettiness.\n";
				    $PRETTY++;
				    next;
			       };
	# matches trace and traceonly for legacy doc mixup reasons
	/^-t(race(only)?)?$/	&& do {
				    $TRACEONLY++;
				    next;
			       };
	/^-w(arntrace)?$/ 	&& do {
				    $WARNTRACE++;
				    next;
			       };

	warn "Unknown flag: $_";
    } 

    $oldwarn = $SIG{__WARN__};
    $olddie = $SIG{__DIE__};
    $SIG{__WARN__} = \&warn_trap;
    $SIG{__DIE__} = \&death_trap;
} 

sub enable { &import }

sub disable {
    shift;
    return unless $SIG{__WARN__} eq \&warn_trap;
    $SIG{__WARN__} = $oldwarn || '';
    $SIG{__DIE__} = $olddie || '';
} 

sub warn_trap {
    my $warning = $_[0];
    if (caller eq __PACKAGE__ or !splainthis($warning)) {
	if ($WARNTRACE) {
	    print STDERR Carp::longmess($warning);
	} else {
	    print STDERR $warning;
	}
    } 
    goto &$oldwarn if defined $oldwarn and $oldwarn and $oldwarn ne \&warn_trap;
};

sub death_trap {
    my $exception = $_[0];

    # See if we are coming from anywhere within an eval. If so we don't
    # want to explain the exception because it's going to get caught.
    my $in_eval = 0;
    my $i = 0;
    while (my $caller = (caller($i++))[3]) {
      if ($caller eq '(eval)') {
	$in_eval = 1;
	last;
      }
    }

    splainthis($exception) unless $in_eval;
    if (caller eq __PACKAGE__) {
	print STDERR "INTERNAL EXCEPTION: $exception";
    } 
    &$olddie if defined $olddie and $olddie and $olddie ne \&death_trap;

    return if $in_eval;

    # We don't want to unset these if we're coming from an eval because
    # then we've turned off diagnostics.

    # Switch off our die/warn handlers so we don't wind up in our own
    # traps.
    $SIG{__DIE__} = $SIG{__WARN__} = '';

    $exception =~ s/\n(?=.)/\n\t/gas;

    die Carp::longmess("__diagnostics__")
	  =~ s/^__diagnostics__.*?line \d+\.?\n/
		  "Uncaught exception from user code:\n\t$exception"
	      /re;
	# up we go; where we stop, nobody knows, but i think we die now
	# but i'm deeply afraid of the &$olddie guy reraising and us getting
	# into an indirect recursion loop
};

my %exact_duplicate;
my %old_diag;
my $count;
my $wantspace;
sub splainthis {
  return 0 if $TRACEONLY;
  for (my $tmp = shift) {
    local $\;
    local $!;
    ### &finish_compilation unless %msg;
    s/(\.\s*)?\n+$//;
    my $orig = $_;
    # return unless defined;

    # get rid of the where-are-we-in-input part
    s/, <.*?> (?:line|chunk).*$//;

    # Discard 1st " at <file> line <no>" and all text beyond
    # but be aware of messages containing " at this-or-that"
    my $real = 0;
    my @secs = split( / at / );
    return unless @secs;
    $_ = $secs[0];
    for my $i ( 1..$#secs ){
        if( $secs[$i] =~ /.+? (?:line|chunk) \d+/ ){
            $real = 1;
            last;
        } else {
            $_ .= ' at ' . $secs[$i];
	}
    }

    # remove parenthesis occurring at the end of some messages 
    s/^\((.*)\)$/$1/;

    if ($exact_duplicate{$orig}++) {
	return &transmo;
    } else {
	return 0 unless &transmo;
    }

    my $short = shorten($orig);
    if ($old_diag{$_}) {
	autodescribe();
	print THITHER "$short (#$old_diag{$_})\n";
	$wantspace = 1;
    } elsif (!$msg{$_} && $orig =~ /\n./s) {
	# A multiline message, like "Attempt to reload /
	# Compilation failed"
	my $found;
	for (split /^/, $orig) {
	    splainthis($_) and $found = 1;
	}
	return $found;
    } else {
	autodescribe();
	$old_diag{$_} = ++$count;
	print THITHER "\n" if $wantspace;
	$wantspace = 0;
	print THITHER "$short (#$old_diag{$_})\n";
	if ($msg{$_}) {
	    print THITHER $msg{$_};
	} else {
	    if (0 and $standalone) { 
		print THITHER "    **** Error #$old_diag{$_} ",
			($real ? "is" : "appears to be"),
			" an unknown diagnostic message.\n\n";
	    }
	    return 0;
	} 
    }
    return 1;
  }
} 

sub autodescribe {
    if ($VERBOSE and not $count) {
	print THITHER &{$PRETTY ? \&bold : \&noop}("DESCRIPTION OF DIAGNOSTICS"),
		"\n$msg{DESCRIPTION}\n";
    } 
} 

sub unescape { 
    s {
            E<  
            ( [A-Za-z]+ )       
            >   
    } { 
         do {   
             exists $HTML_Escapes{$1}
                ? do { $HTML_Escapes{$1} }
                : do {
                    warn "Unknown escape: E<$1> in $_";
                    "E<$1>";
                } 
         } 
    }egx;
}

sub shorten {
    my $line = $_[0];
    if (length($line) > 79 and index($line, "\n") == -1) {
	my $space_place = rindex($line, ' ', 79);
	if ($space_place != -1) {
	    substr($line, $space_place, 1) = "\n\t";
	} 
    } 
    return $line;
} 


1 unless $standalone;  # or it'll complain about itself
__END__ # wish diag dbase were more accessible
