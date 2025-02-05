package TAP::Parser::YAMLish::Reader;

use strict;
use warnings;

use base 'TAP::Object';

our $VERSION = '3.30';


my %UNESCAPES = (
    z => "\x00", a => "\x07", t    => "\x09",
    n => "\x0a", v => "\x0b", f    => "\x0c",
    r => "\x0d", e => "\x1b", '\\' => '\\',
);

my $QQ_STRING    = qr{ " (?:\\. | [^"])* " }x;
my $HASH_LINE    = qr{ ^ ($QQ_STRING|\S+) \s* : \s* (?: (.+?) \s* )? $ }x;
my $IS_HASH_KEY  = qr{ ^ [\w\'\"] }x;
my $IS_END_YAML  = qr{ ^ \.\.\. \s* $ }x;
my $IS_QQ_STRING = qr{ ^ $QQ_STRING $ }x;


sub read {
    my $self = shift;
    my $obj  = shift;

    die "Must have a code reference to read input from"
      unless ref $obj eq 'CODE';

    $self->{reader}  = $obj;
    $self->{capture} = [];

    # Prime the reader
    $self->_next;
    return unless $self->{next};

    my $doc = $self->_read;

    # The terminator is mandatory otherwise we'd consume a line from the
    # iterator that doesn't belong to us. If we want to remove this
    # restriction we'll have to implement look-ahead in the iterators.
    # Which might not be a bad idea.
    my $dots = $self->_peek;
    die "Missing '...' at end of YAMLish"
      unless defined $dots
          and $dots =~ $IS_END_YAML;

    delete $self->{reader};
    delete $self->{next};

    return $doc;
}

sub get_raw { join( "\n", grep defined, @{ shift->{capture} || [] } ) . "\n" }

sub _peek {
    my $self = shift;
    return $self->{next} unless wantarray;
    my $line = $self->{next};
    $line =~ /^ (\s*) (.*) $ /x;
    return ( $2, length $1 );
}

sub _next {
    my $self = shift;
    die "_next called with no reader"
      unless $self->{reader};
    my $line = $self->{reader}->();
    $self->{next} = $line;
    push @{ $self->{capture} }, $line;
}

sub _read {
    my $self = shift;

    my $line = $self->_peek;

    # Do we have a document header?
    if ( $line =~ /^ --- (?: \s* (.+?) \s* )? $/x ) {
        $self->_next;

        return $self->_read_scalar($1) if defined $1;    # Inline?

        my ( $next, $indent ) = $self->_peek;

        if ( $next =~ /^ - /x ) {
            return $self->_read_array($indent);
        }
        elsif ( $next =~ $IS_HASH_KEY ) {
            return $self->_read_hash( $next, $indent );
        }
        elsif ( $next =~ $IS_END_YAML ) {
            die "Premature end of YAMLish";
        }
        else {
            die "Unsupported YAMLish syntax: '$next'";
        }
    }
    else {
        die "YAMLish document header not found";
    }
}

sub _read_qq {
    my $self = shift;
    my $str  = shift;

    unless ( $str =~ s/^ " (.*?) " $/$1/x ) {
        die "Internal: not a quoted string";
    }

    $str =~ s/\\"/"/gx;
    $str =~ s/ \\ ( [tartan\\favez] | x([0-9a-fA-F]{2}) ) 
                 / (length($1) > 1) ? pack("H2", $2) : $UNESCAPES{$1} /gex;
    return $str;
}

sub _read_scalar {
    my $self   = shift;
    my $string = shift;

    return undef if $string eq '~';
    return {} if $string eq '{}';
    return [] if $string eq '[]';

    if ( $string eq '>' || $string eq '|' ) {

        my ( $line, $indent ) = $self->_peek;
        die "Multi-line scalar content missing" unless defined $line;

        my @multiline = ($line);

        while (1) {
            $self->_next;
            my ( $next, $ind ) = $self->_peek;
            last if $ind < $indent;

            my $pad = $string eq '|' ? ( ' ' x ( $ind - $indent ) ) : '';
            push @multiline, $pad . $next;
        }

        return join( ( $string eq '>' ? ' ' : "\n" ), @multiline ) . "\n";
    }

    if ( $string =~ /^ ' (.*) ' $/x ) {
        ( my $rv = $1 ) =~ s/''/'/g;
        return $rv;
    }

    if ( $string =~ $IS_QQ_STRING ) {
        return $self->_read_qq($string);
    }

    if ( $string =~ /^['"]/ ) {

        # A quote with folding... we don't support that
        die __PACKAGE__ . " does not support multi-line quoted scalars";
    }

    # Regular unquoted string
    return $string;
}

sub _read_nested {
    my $self = shift;

    my ( $line, $indent ) = $self->_peek;

    if ( $line =~ /^ -/x ) {
        return $self->_read_array($indent);
    }
    elsif ( $line =~ $IS_HASH_KEY ) {
        return $self->_read_hash( $line, $indent );
    }
    else {
        die "Unsupported YAMLish syntax: '$line'";
    }
}

sub _read_array {
    my ( $self, $limit ) = @_;

    my $ar = [];

    while (1) {
        my ( $line, $indent ) = $self->_peek;
        last
          if $indent < $limit
              || !defined $line
              || $line =~ $IS_END_YAML;

        if ( $indent > $limit ) {
            die "Array line over-indented";
        }

        if ( $line =~ /^ (- \s+) \S+ \s* : (?: \s+ | $ ) /x ) {
            $indent += length $1;
            $line =~ s/-\s+//;
            push @$ar, $self->_read_hash( $line, $indent );
        }
        elsif ( $line =~ /^ - \s* (.+?) \s* $/x ) {
            die "Unexpected start of YAMLish" if $line =~ /^---/;
            $self->_next;
            push @$ar, $self->_read_scalar($1);
        }
        elsif ( $line =~ /^ - \s* $/x ) {
            $self->_next;
            push @$ar, $self->_read_nested;
        }
        elsif ( $line =~ $IS_HASH_KEY ) {
            $self->_next;
            push @$ar, $self->_read_hash( $line, $indent, );
        }
        else {
            die "Unsupported YAMLish syntax: '$line'";
        }
    }

    return $ar;
}

sub _read_hash {
    my ( $self, $line, $limit ) = @_;

    my $indent;
    my $hash = {};

    while (1) {
        die "Badly formed hash line: '$line'"
          unless $line =~ $HASH_LINE;

        my ( $key, $value ) = ( $self->_read_scalar($1), $2 );
        $self->_next;

        if ( defined $value ) {
            $hash->{$key} = $self->_read_scalar($value);
        }
        else {
            $hash->{$key} = $self->_read_nested;
        }

        ( $line, $indent ) = $self->_peek;
        last
          if $indent < $limit
              || !defined $line
              || $line =~ $IS_END_YAML;
    }

    return $hash;
}

1;

__END__


