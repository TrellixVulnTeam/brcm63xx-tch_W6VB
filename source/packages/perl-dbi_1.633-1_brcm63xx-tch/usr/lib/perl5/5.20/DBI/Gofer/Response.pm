package DBI::Gofer::Response;


use strict;

use Carp;
use DBI qw(neat neat_list);

use base qw(DBI::Util::_accessor Exporter);

our $VERSION = "0.011566";

use constant GOf_RESPONSE_EXECUTED => 0x0001;

our @EXPORT = qw(GOf_RESPONSE_EXECUTED);


__PACKAGE__->mk_accessors(qw(
    version
    rv
    err
    errstr
    state
    flags
    last_insert_id
    dbh_attributes
    sth_resultsets
    warnings
));
__PACKAGE__->mk_accessors_using(make_accessor_autoviv_hashref => qw(
    meta
));


sub new {
    my ($self, $args) = @_;
    $args->{version} ||= $VERSION;
    chomp $args->{errstr} if $args->{errstr};
    return $self->SUPER::new($args);
}


sub err_errstr_state {
    my $self = shift;
    return @{$self}{qw(err errstr state)};
}

sub executed_flag_set {
    my $flags = shift->flags
        or return 0;
    return $flags & GOf_RESPONSE_EXECUTED;
}


sub add_err {
    my ($self, $err, $errstr, $state, $trace) = @_;

    # acts like the DBI's set_err method.
    # this code copied from DBI::PurePerl's set_err method.

    chomp $errstr if $errstr;
    $state ||= '';
    carp ref($self)."->add_err($err, $errstr, $state)"
        if $trace and defined($err) || $errstr;

    my ($r_err, $r_errstr, $r_state) = ($self->{err}, $self->{errstr}, $self->{state});

    if ($r_errstr) {
        $r_errstr .= sprintf " [err was %s now %s]", $r_err, $err
                if $r_err && $err && $r_err ne $err;
        $r_errstr .= sprintf " [state was %s now %s]", $r_state, $state
                if $r_state and $r_state ne "S1000" && $state && $r_state ne $state;
        $r_errstr .= "\n$errstr" if $r_errstr ne $errstr;
    }
    else {
        $r_errstr = $errstr;
    }

    # assign if higher priority: err > "0" > "" > undef
    my $err_changed;
    if ($err                 # new error: so assign
        or !defined $r_err   # no existing warn/info: so assign
           # new warn ("0" len 1) > info ("" len 0): so assign
        or defined $err && length($err) > length($r_err)
    ) {
        $r_err = $err;
        ++$err_changed;
    }

    $r_state = ($state eq "00000") ? "" : $state
        if $state && $err_changed;

    ($self->{err}, $self->{errstr}, $self->{state}) = ($r_err, $r_errstr, $r_state);

    return undef;
}


sub summary_as_text {
    my $self = shift;
    my ($context) = @_;

    my ($rv, $err, $errstr, $state) = ($self->{rv}, $self->{err}, $self->{errstr}, $self->{state});

    my @s = sprintf("\trv=%s", (ref $rv) ? "[".neat_list($rv)."]" : neat($rv));
    $s[-1] .= sprintf(", err=%s, errstr=%s", $err, neat($errstr))
        if defined $err;
    $s[-1] .= sprintf(",  flags=0x%x", $self->{flags})
        if defined $self->{flags};

    push @s, "last_insert_id=%s", $self->last_insert_id
        if defined $self->last_insert_id;

    if (my $dbh_attr = $self->dbh_attributes) {
        my @keys = sort keys %$dbh_attr;
        push @s, sprintf "dbh= { %s }", join(", ", map { "$_=>".neat($dbh_attr->{$_},100) } @keys)
            if @keys;
    }

    for my $rs (@{$self->sth_resultsets || []}) {
        my ($rowset, $err, $errstr, $state)
            = @{$rs}{qw(rowset err errstr state)};
        my $summary = "rowset: ";
        my $NUM_OF_FIELDS = $rs->{NUM_OF_FIELDS} || 0;
        my $rows = $rowset ? @$rowset : 0;
        if ($rowset || $NUM_OF_FIELDS > 0) {
            $summary .= sprintf "%d rows, %d columns", $rows, $NUM_OF_FIELDS;
        }
        $summary .= sprintf ", err=%s, errstr=%s", $err, neat($errstr) if defined $err;
        if ($rows) {
            my $NAME = $rs->{NAME};
            # generate
            my @colinfo = map { "$NAME->[$_]=".neat($rowset->[0][$_], 30) } 0..@{$NAME}-1;
            $summary .= sprintf " [%s]", join ", ", @colinfo;
            $summary .= ",..." if $rows > 1;
            # we can be a little more helpful for Sybase/MSSQL user
            $summary .= " syb_result_type=$rs->{syb_result_type}"
                if $rs->{syb_result_type} and $rs->{syb_result_type} != 4040;
        }
        push @s, $summary;
    }
    for my $w (@{$self->warnings || []}) {
        chomp $w;
        push @s, "warning: $w";
    }
    if ($context && %$context) {
        my @keys = sort keys %$context;
        push @s, join(", ", map { "$_=>".$context->{$_} } @keys);
    }
    return join("\n\t", @s). "\n";
}


sub outline_as_text { # one-line version of summary_as_text
    my $self = shift;
    my ($context) = @_;

    my ($rv, $err, $errstr, $state) = ($self->{rv}, $self->{err}, $self->{errstr}, $self->{state});

    my $s = sprintf("rv=%s", (ref $rv) ? "[".neat_list($rv)."]" : neat($rv));
    $s .= sprintf(", err=%s %s", $err, neat($errstr))
        if defined $err;
    $s .= sprintf(", flags=0x%x", $self->{flags})
        if $self->{flags};

    if (my $sth_resultsets = $self->sth_resultsets) {
        $s .= sprintf(", %d resultsets ", scalar @$sth_resultsets);

        my @rs;
        for my $rs (@{$self->sth_resultsets || []}) {
            my $summary = "";
            my ($rowset, $err, $errstr)
                = @{$rs}{qw(rowset err errstr)};
            my $NUM_OF_FIELDS = $rs->{NUM_OF_FIELDS} || 0;
            my $rows = $rowset ? @$rowset : 0;
            if ($rowset || $NUM_OF_FIELDS > 0) {
                $summary .= sprintf "%dr x %dc", $rows, $NUM_OF_FIELDS;
            }
            $summary .= sprintf "%serr %s %s", ($summary?", ":""), $err, neat($errstr)
                if defined $err;
            push @rs, $summary;
        }
        $s .= join "; ", map { "[$_]" } @rs;
    }

    return $s;
}


1;


