package TAP::Formatter::Base;

use strict;
use warnings;
use base 'TAP::Base';
use POSIX qw(strftime);

my $MAX_ERRORS = 5;
my %VALIDATION_FOR;

BEGIN {
    %VALIDATION_FOR = (
        directives => sub { shift; shift },
        verbosity  => sub { shift; shift },
        normalize  => sub { shift; shift },
        timer      => sub { shift; shift },
        failures   => sub { shift; shift },
        comments   => sub { shift; shift },
        errors     => sub { shift; shift },
        color      => sub { shift; shift },
        jobs       => sub { shift; shift },
        show_count => sub { shift; shift },
        stdout     => sub {
            my ( $self, $ref ) = @_;

            $self->_croak("option 'stdout' needs a filehandle")
              unless $self->_is_filehandle($ref);

            return $ref;
        },
    );

    sub _is_filehandle {
        my ( $self, $ref ) = @_;

        return 0 if !defined $ref;

        return 1 if ref $ref eq 'GLOB';    # lexical filehandle
        return 1 if !ref $ref && ref \$ref eq 'GLOB'; # bare glob like *STDOUT

        return 1 if eval { $ref->can('print') };

        return 0;
    }

    my @getter_setters = qw(
      _longest
      _printed_summary_header
      _colorizer
    );

    __PACKAGE__->mk_methods( @getter_setters, keys %VALIDATION_FOR );
}


our $VERSION = '3.30';


sub _initialize {
    my ( $self, $arg_for ) = @_;
    $arg_for ||= {};

    $self->SUPER::_initialize($arg_for);
    my %arg_for = %$arg_for;    # force a shallow copy

    $self->verbosity(0);

    for my $name ( keys %VALIDATION_FOR ) {
        my $property = delete $arg_for{$name};
        if ( defined $property ) {
            my $validate = $VALIDATION_FOR{$name};
            $self->$name( $self->$validate($property) );
        }
    }

    if ( my @props = keys %arg_for ) {
        $self->_croak(
            "Unknown arguments to " . __PACKAGE__ . "::new (@props)" );
    }

    $self->stdout( \*STDOUT ) unless $self->stdout;

    if ( $self->color ) {
        require TAP::Formatter::Color;
        $self->_colorizer( TAP::Formatter::Color->new );
    }

    return $self;
}

sub verbose      { shift->verbosity >= 1 }
sub quiet        { shift->verbosity <= -1 }
sub really_quiet { shift->verbosity <= -2 }
sub silent       { shift->verbosity <= -3 }




sub prepare {
    my ( $self, @tests ) = @_;

    my $longest = 0;

    for my $test (@tests) {
        $longest = length $test if length $test > $longest;
    }

    $self->_longest($longest);
}

sub _format_now { strftime "[%H:%M:%S]", localtime }

sub _format_name {
    my ( $self, $test ) = @_;
    my $name = $test;
    my $periods = '.' x ( $self->_longest + 2 - length $test );
    $periods = " $periods ";

    if ( $self->timer ) {
        my $stamp = $self->_format_now();
        return "$stamp $name$periods";
    }
    else {
        return "$name$periods";
    }

}


sub open_test {
    die "Unimplemented.";
}

sub _output_success {
    my ( $self, $msg ) = @_;
    $self->_output($msg);
}


sub summary {
    my ( $self, $aggregate, $interrupted ) = @_;

    return if $self->silent;

    my @t     = $aggregate->descriptions;
    my $tests = \@t;

    my $runtime = $aggregate->elapsed_timestr;

    my $total  = $aggregate->total;
    my $passed = $aggregate->passed;

    if ( $self->timer ) {
        $self->_output( $self->_format_now(), "\n" );
    }

    $self->_failure_output("Test run interrupted!\n")
      if $interrupted;

    # TODO: Check this condition still works when all subtests pass but
    # the exit status is nonzero

    if ( $aggregate->all_passed ) {
        $self->_output_success("All tests successful.\n");
    }

    # ~TODO option where $aggregate->skipped generates reports
    if ( $total != $passed or $aggregate->has_problems ) {
        $self->_output("\nTest Summary Report");
        $self->_output("\n-------------------\n");
        for my $test (@$tests) {
            $self->_printed_summary_header(0);
            my ($parser) = $aggregate->parsers($test);
            $self->_output_summary_failure(
                'failed',
                [ '  Failed test:  ', '  Failed tests:  ' ],
                $test, $parser
            );
            $self->_output_summary_failure(
                'todo_passed',
                "  TODO passed:   ", $test, $parser
            );

            # ~TODO this cannot be the default
            #$self->_output_summary_failure( 'skipped', "  Tests skipped: " );

            if ( my $exit = $parser->exit ) {
                $self->_summary_test_header( $test, $parser );
                $self->_failure_output("  Non-zero exit status: $exit\n");
            }
            elsif ( my $wait = $parser->wait ) {
                $self->_summary_test_header( $test, $parser );
                $self->_failure_output("  Non-zero wait status: $wait\n");
            }

            if ( my @errors = $parser->parse_errors ) {
                my $explain;
                if ( @errors > $MAX_ERRORS && !$self->errors ) {
                    $explain
                      = "Displayed the first $MAX_ERRORS of "
                      . scalar(@errors)
                      . " TAP syntax errors.\n"
                      . "Re-run prove with the -p option to see them all.\n";
                    splice @errors, $MAX_ERRORS;
                }
                $self->_summary_test_header( $test, $parser );
                $self->_failure_output(
                    sprintf "  Parse errors: %s\n",
                    shift @errors
                );
                for my $error (@errors) {
                    my $spaces = ' ' x 16;
                    $self->_failure_output("$spaces$error\n");
                }
                $self->_failure_output($explain) if $explain;
            }
        }
    }
    my $files = @$tests;
    $self->_output("Files=$files, Tests=$total, $runtime\n");
    my $status = $aggregate->get_status;
    $self->_output("Result: $status\n");
}

sub _output_summary_failure {
    my ( $self, $method, $name, $test, $parser ) = @_;

    # ugly hack.  Must rethink this :(
    my $output = $method eq 'failed' ? '_failure_output' : '_output';

    if ( my @r = $parser->$method() ) {
        $self->_summary_test_header( $test, $parser );
        my ( $singular, $plural )
          = 'ARRAY' eq ref $name ? @$name : ( $name, $name );
        $self->$output( @r == 1 ? $singular : $plural );
        my @results = $self->_balanced_range( 40, @r );
        $self->$output( sprintf "%s\n" => shift @results );
        my $spaces = ' ' x 16;
        while (@results) {
            $self->$output( sprintf "$spaces%s\n" => shift @results );
        }
    }
}

sub _summary_test_header {
    my ( $self, $test, $parser ) = @_;
    return if $self->_printed_summary_header;
    my $spaces = ' ' x ( $self->_longest - length $test );
    $spaces = ' ' unless $spaces;
    my $output = $self->_get_output_method($parser);
    my $wait   = $parser->wait;
    defined $wait or $wait = '(none)';
    $self->$output(
        sprintf "$test$spaces(Wstat: %s Tests: %d Failed: %d)\n",
        $wait, $parser->tests_run, scalar $parser->failed
    );
    $self->_printed_summary_header(1);
}

sub _output {
    my $self = shift;

    print { $self->stdout } @_;
}

sub _failure_output {
    my $self = shift;

    $self->_output(@_);
}

sub _balanced_range {
    my ( $self, $limit, @range ) = @_;
    @range = $self->_range(@range);
    my $line = "";
    my @lines;
    my $curr = 0;
    while (@range) {
        if ( $curr < $limit ) {
            my $range = ( shift @range ) . ", ";
            $line .= $range;
            $curr += length $range;
        }
        elsif (@range) {
            $line =~ s/, $//;
            push @lines => $line;
            $line = '';
            $curr = 0;
        }
    }
    if ($line) {
        $line =~ s/, $//;
        push @lines => $line;
    }
    return @lines;
}

sub _range {
    my ( $self, @numbers ) = @_;

    # shouldn't be needed, but subclasses might call this
    @numbers = sort { $a <=> $b } @numbers;
    my ( $min, @range );

    for my $i ( 0 .. $#numbers ) {
        my $num  = $numbers[$i];
        my $next = $numbers[ $i + 1 ];
        if ( defined $next && $next == $num + 1 ) {
            if ( !defined $min ) {
                $min = $num;
            }
        }
        elsif ( defined $min ) {
            push @range => "$min-$num";
            undef $min;
        }
        else {
            push @range => $num;
        }
    }
    return @range;
}

sub _get_output_method {
    my ( $self, $parser ) = @_;
    return $parser->has_problems ? '_failure_output' : '_output';
}

1;
