package DBI::ProfileData;
use strict;


our $VERSION = "2.010008";

use Carp qw(croak);
use Symbol;
use Fcntl qw(:flock);

use DBI::Profile qw(dbi_profile_merge);

sub COUNT     () { 0 };
sub TOTAL     () { 1 };
sub FIRST     () { 2 };
sub SHORTEST  () { 3 };
sub LONGEST   () { 4 };
sub FIRST_AT  () { 5 };
sub LAST_AT   () { 6 };
sub PATH      () { 7 };


my $HAS_FLOCK = (defined $ENV{DBI_PROFILE_FLOCK})
    ? $ENV{DBI_PROFILE_FLOCK}
    : do { local $@; eval { flock STDOUT, 0; 1 } };



sub new {
    my $pkg = shift;
    my $self = {
                Files        => [ "dbi.prof" ],
		Filter       => undef,
                DeleteFiles  => 0,
                LockFile     => $HAS_FLOCK,
                _header      => {},
                _nodes       => [],
                _node_lookup => {},
                _sort        => 'none',
                @_
               };
    bless $self, $pkg;

    # File (singular) overrides Files (plural)
    $self->{Files} = [ $self->{File} ] if exists $self->{File};

    $self->_read_files();
    return $self;
}

sub _read_files {
    my $self = shift;
    my $files  = $self->{Files};
    my $read_header = 0;
    my @files_to_delete;

    my $fh = gensym;
    foreach (@$files) {
        my $filename = $_;

        if ($self->{DeleteFiles}) {
            my $newfilename = $filename . ".deleteme";
	    if ($^O eq 'VMS') {
		# VMS default filesystem can only have one period
		$newfilename = $filename . 'deleteme';
	    }
            # will clobber an existing $newfilename
            rename($filename, $newfilename)
                or croak "Can't rename($filename, $newfilename): $!";
	    # On a versioned filesystem we want old versions to be removed
	    1 while (unlink $filename);
            $filename = $newfilename;
        }

        open($fh, "<", $filename)
          or croak("Unable to read profile file '$filename': $!");

        # lock the file in case it's still being written to
        # (we'll be forced to wait till the write is complete)
        flock($fh, LOCK_SH) if $self->{LockFile};

        if (-s $fh) {   # not empty
            $self->_read_header($fh, $filename, $read_header ? 0 : 1);
            $read_header = 1;
            $self->_read_body($fh, $filename);
        }
        close($fh); # and release lock

        push @files_to_delete, $filename
            if $self->{DeleteFiles};
    }
    for (@files_to_delete){
	# for versioned file systems
	1 while (unlink $_);
	if(-e $_){
	    warn "Can't delete '$_': $!";
	}
    }

    # discard node_lookup now that all files are read
    delete $self->{_node_lookup};
}

sub _read_header {
    my ($self, $fh, $filename, $keep) = @_;

    # get profiler module id
    my $first = <$fh>;
    chomp $first;
    $self->{_profiler} = $first if $keep;

    # collect variables from the header
    local $_;
    while (<$fh>) {
        chomp;
        last unless length $_;
        /^(\S+)\s*=\s*(.*)/
          or croak("Syntax error in header in $filename line $.: $_");
        # XXX should compare new with existing (from previous file)
        # and warn if they differ (different program or path)
        $self->{_header}{$1} = unescape_key($2) if $keep;
    }
}


sub unescape_key {  # inverse of escape_key() in DBI::ProfileDumper
    local $_ = shift;
    s/(?<!\\)\\n/\n/g; # expand \n, unless it's a \\n
    s/(?<!\\)\\r/\r/g; # expand \r, unless it's a \\r
    s/\\\\/\\/g;       # \\ to \
    return $_;
}


sub _read_body {
    my ($self, $fh, $filename) = @_;
    my $nodes = $self->{_nodes};
    my $lookup = $self->{_node_lookup};
    my $filter = $self->{Filter};

    # build up node array
    my @path = ("");
    my (@data, $path_key);
    local $_;
    while (<$fh>) {
        chomp;
        if (/^\+\s+(\d+)\s?(.*)/) {
            # it's a key
            my ($key, $index) = ($2, $1 - 1);

            $#path = $index;      # truncate path to new length
            $path[$index] = unescape_key($key); # place new key at end

        }
	elsif (s/^=\s+//) {
            # it's data - file in the node array with the path in index 0
	    # (the optional minus is to make it more robust against systems
	    # with unstable high-res clocks - typically due to poor NTP config
	    # of kernel SMP behaviour, i.e. min time may be -0.000008))

            @data = split / /, $_;

            # corrupt data?
            croak("Invalid number of fields in $filename line $.: $_")
                unless @data == 7;
            croak("Invalid leaf node characters $filename line $.: $_")
                unless m/^[-+ 0-9eE\.]+$/;

	    # hook to enable pre-processing of the data - such as mangling SQL
	    # so that slightly different statements get treated as the same
	    # and so merged in the results
	    $filter->(\@path, \@data) if $filter;

            # elements of @path can't have NULLs in them, so this
            # forms a unique string per @path.  If there's some way I
            # can get this without arbitrarily stripping out a
            # character I'd be happy to hear it!
            $path_key = join("\0",@path);

            # look for previous entry
            if (exists $lookup->{$path_key}) {
                # merge in the new data
		dbi_profile_merge($nodes->[$lookup->{$path_key}], \@data);
            } else {
                # insert a new node - nodes are arrays with data in 0-6
                # and path data after that
                push(@$nodes, [ @data, @path ]);

                # record node in %seen
                $lookup->{$path_key} = $#$nodes;
            }
        }
	else {
            croak("Invalid line type syntax error in $filename line $.: $_");
	}
    }
}




sub clone {
    my $self = shift;

    # start with a simple copy
    my $clone = bless { %$self }, ref($self);

    # deep copy nodes
    $clone->{_nodes}  = [ map { [ @$_ ] } @{$self->{_nodes}} ];

    # deep copy header
    $clone->{_header} = { %{$self->{_header}} };

    return $clone;
}


sub header { shift->{_header} }



sub nodes { shift->{_nodes} }



sub count { scalar @{shift->{_nodes}} }




{
    my %FIELDS = (
                  longest  => LONGEST,
                  total    => TOTAL,
                  count    => COUNT,
                  shortest => SHORTEST,
                  key1     => PATH+0,
                  key2     => PATH+1,
                  key3     => PATH+2,
                 );
    sub sort {
        my $self = shift;
        my $nodes = $self->{_nodes};
        my %opt = @_;

        croak("Missing required field option.") unless $opt{field};

        my $index = $FIELDS{$opt{field}};

        croak("Unrecognized sort field '$opt{field}'.")
          unless defined $index;

        # sort over index
        if ($opt{reverse}) {
            @$nodes = sort {
                $a->[$index] <=> $b->[$index]
            } @$nodes;
        } else {
            @$nodes = sort {
                $b->[$index] <=> $a->[$index]
            } @$nodes;
        }

        # remember how we're sorted
        $self->{_sort} = $opt{field};

        return $self;
    }
}



sub exclude {
    my $self = shift;
    my $nodes = $self->{_nodes};
    my %opt = @_;

    # find key index number
    my ($index, $val);
    foreach (keys %opt) {
        if (/^key(\d+)$/) {
            $index   = PATH + $1 - 1;
            $val     = $opt{$_};
            last;
        }
    }
    croak("Missing required keyN option.") unless $index;

    if (UNIVERSAL::isa($val,"Regexp")) {
        # regex match
        @$nodes = grep {
            $#$_ < $index or $_->[$index] !~ /$val/
        } @$nodes;
    } else {
        if ($opt{case_sensitive}) {
            @$nodes = grep {
                $#$_ < $index or $_->[$index] ne $val;
            } @$nodes;
        } else {
            $val = lc $val;
            @$nodes = grep {
                $#$_ < $index or lc($_->[$index]) ne $val;
            } @$nodes;
        }
    }

    return scalar @$nodes;
}



sub match {
    my $self = shift;
    my $nodes = $self->{_nodes};
    my %opt = @_;

    # find key index number
    my ($index, $val);
    foreach (keys %opt) {
        if (/^key(\d+)$/) {
            $index   = PATH + $1 - 1;
            $val     = $opt{$_};
            last;
        }
    }
    croak("Missing required keyN option.") unless $index;

    if (UNIVERSAL::isa($val,"Regexp")) {
        # regex match
        @$nodes = grep {
            $#$_ >= $index and $_->[$index] =~ /$val/
        } @$nodes;
    } else {
        if ($opt{case_sensitive}) {
            @$nodes = grep {
                $#$_ >= $index and $_->[$index] eq $val;
            } @$nodes;
        } else {
            $val = lc $val;
            @$nodes = grep {
                $#$_ >= $index and lc($_->[$index]) eq $val;
            } @$nodes;
        }
    }

    return scalar @$nodes;
}



sub Data {
    my $self = shift;
    my (%Data, @data, $ptr);

    foreach my $node (@{$self->{_nodes}}) {
        # traverse to key location
        $ptr = \%Data;
        foreach my $key (@{$node}[PATH .. $#$node - 1]) {
            $ptr->{$key} = {} unless exists $ptr->{$key};
            $ptr = $ptr->{$key};
        }

        # slice out node data
        $ptr->{$node->[-1]} = [ @{$node}[0 .. 6] ];
    }

    return \%Data;
}



sub format {
    my ($self, $node) = @_;
    my $format;

    # setup keys
    my $keys = "";
    for (my $i = PATH; $i <= $#$node; $i++) {
        my $key = $node->[$i];

        # remove leading and trailing space
        $key =~ s/^\s+//;
        $key =~ s/\s+$//;

        # if key has newlines or is long take special precautions
        if (length($key) > 72 or $key =~ /\n/) {
            $keys .= "  Key " . ($i - PATH + 1) . "         :\n\n$key\n\n";
        } else {
            $keys .= "  Key " . ($i - PATH + 1) . "         : $key\n";
        }
    }

    # nodes with multiple runs get the long entry format, nodes with
    # just one run get a single count.
    if ($node->[COUNT] > 1) {
        $format = <<END;
  Count         : %d
  Total Time    : %3.6f seconds
  Longest Time  : %3.6f seconds
  Shortest Time : %3.6f seconds
  Average Time  : %3.6f seconds
END
        return sprintf($format, @{$node}[COUNT,TOTAL,LONGEST,SHORTEST],
                       $node->[TOTAL] / $node->[COUNT]) . $keys;
    } else {
        $format = <<END;
  Count         : %d
  Time          : %3.6f seconds
END

        return sprintf($format, @{$node}[COUNT,TOTAL]) . $keys;

    }
}



sub report {
    my $self  = shift;
    my $nodes = $self->{_nodes};
    my %opt   = @_;

    croak("Missing required number option") unless exists $opt{number};

    $opt{number} = @$nodes if @$nodes < $opt{number};

    my $report = $self->_report_header($opt{number});
    for (0 .. $opt{number} - 1) {
        $report .= sprintf("#" x 5  . "[ %d ]". "#" x 59 . "\n",
                           $_ + 1);
        $report .= $self->format($nodes->[$_]);
        $report .= "\n";
    }
    return $report;
}

sub _report_header {
    my ($self, $number) = @_;
    my $nodes = $self->{_nodes};
    my $node_count = @$nodes;

    # find total runtime and method count
    my ($time, $count) = (0,0);
    foreach my $node (@$nodes) {
        $time  += $node->[TOTAL];
        $count += $node->[COUNT];
    }

    my $header = <<END;

DBI Profile Data ($self->{_profiler})

END

    # output header fields
    while (my ($key, $value) = each %{$self->{_header}}) {
        $header .= sprintf("  %-13s : %s\n", $key, $value);
    }

    # output summary data fields
    $header .= sprintf(<<END, $node_count, $number, $self->{_sort}, $count, $time);
  Total Records : %d (showing %d, sorted by %s)
  Total Count   : %d
  Total Runtime : %3.6f seconds

END

    return $header;
}


1;

__END__

