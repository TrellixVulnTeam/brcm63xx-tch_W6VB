package TAP::Formatter::Session;

use strict;
use warnings;

use base 'TAP::Base';

my @ACCESSOR;

BEGIN {

    @ACCESSOR = qw( name formatter parser show_count );

    for my $method (@ACCESSOR) {
        no strict 'refs';
        *$method = sub { shift->{$method} };
    }
}


our $VERSION = '3.30';


sub _initialize {
    my ( $self, $arg_for ) = @_;
    $arg_for ||= {};

    $self->SUPER::_initialize($arg_for);
    my %arg_for = %$arg_for;    # force a shallow copy

    for my $name (@ACCESSOR) {
        $self->{$name} = delete $arg_for{$name};
    }

    if ( !defined $self->show_count ) {
        $self->{show_count} = 1;    # defaults to true
    }
    if ( $self->show_count ) {      # but may be a damned lie!
        $self->{show_count} = $self->_should_show_count;
    }

    if ( my @props = sort keys %arg_for ) {
        $self->_croak(
            "Unknown arguments to " . __PACKAGE__ . "::new (@props)" );
    }

    return $self;
}


sub header { }

sub result { }

sub close_test { }

sub clear_for_close { }

sub _should_show_count {
    my $self = shift;
    return
         !$self->formatter->verbose
      && -t $self->formatter->stdout
      && !$ENV{HARNESS_NOTTY};
}

sub _format_for_output {
    my ( $self, $result ) = @_;
    return $self->formatter->normalize ? $result->as_string : $result->raw;
}

sub _output_test_failure {
    my ( $self, $parser ) = @_;
    my $formatter = $self->formatter;
    return if $formatter->really_quiet;

    my $tests_run     = $parser->tests_run;
    my $tests_planned = $parser->tests_planned;

    my $total
      = defined $tests_planned
      ? $tests_planned
      : $tests_run;

    my $passed = $parser->passed;

    # The total number of fails includes any tests that were planned but
    # didn't run
    my $failed = $parser->failed + $total - $tests_run;
    my $exit   = $parser->exit;

    if ( my $exit = $parser->exit ) {
        my $wstat = $parser->wait;
        my $status = sprintf( "%d (wstat %d, 0x%x)", $exit, $wstat, $wstat );
        $formatter->_failure_output("Dubious, test returned $status\n");
    }

    if ( $failed == 0 ) {
        $formatter->_failure_output(
            $total
            ? "All $total subtests passed "
            : 'No subtests run '
        );
    }
    else {
        $formatter->_failure_output("Failed $failed/$total subtests ");
        if ( !$total ) {
            $formatter->_failure_output("\nNo tests run!");
        }
    }

    if ( my $skipped = $parser->skipped ) {
        $passed -= $skipped;
        my $test = 'subtest' . ( $skipped != 1 ? 's' : '' );
        $formatter->_output(
            "\n\t(less $skipped skipped $test: $passed okay)");
    }

    if ( my $failed = $parser->todo_passed ) {
        my $test = $failed > 1 ? 'tests' : 'test';
        $formatter->_output(
            "\n\t($failed TODO $test unexpectedly succeeded)");
    }

    $formatter->_output("\n");
}

sub _make_ok_line {
    my ( $self, $suffix ) = @_;
    return "ok$suffix\n";
}

1;
