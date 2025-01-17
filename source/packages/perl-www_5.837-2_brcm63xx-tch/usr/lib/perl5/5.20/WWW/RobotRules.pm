package WWW::RobotRules;

$VERSION = "5.832";
sub Version { $VERSION; }

use strict;
use URI ();



sub new {
    my($class, $ua) = @_;

    # This ugly hack is needed to ensure backwards compatibility.
    # The "WWW::RobotRules" class is now really abstract.
    $class = "WWW::RobotRules::InCore" if $class eq "WWW::RobotRules";

    my $self = bless { }, $class;
    $self->agent($ua);
    $self;
}


sub parse {
    my($self, $robot_txt_uri, $txt, $fresh_until) = @_;
    $robot_txt_uri = URI->new("$robot_txt_uri");
    my $netloc = $robot_txt_uri->host . ":" . $robot_txt_uri->port;

    $self->clear_rules($netloc);
    $self->fresh_until($netloc, $fresh_until || (time + 365*24*3600));

    my $ua;
    my $is_me = 0;		# 1 iff this record is for me
    my $is_anon = 0;		# 1 iff this record is for *
    my $seen_disallow = 0;      # watch for missing record separators
    my @me_disallowed = ();	# rules disallowed for me
    my @anon_disallowed = ();	# rules disallowed for *

    # blank lines are significant, so turn CRLF into LF to avoid generating
    # false ones
    $txt =~ s/\015\012/\012/g;

    # split at \012 (LF) or \015 (CR) (Mac text files have just CR for EOL)
    for(split(/[\012\015]/, $txt)) {

	# Lines containing only a comment are discarded completely, and
        # therefore do not indicate a record boundary.
	next if /^\s*\#/;

	s/\s*\#.*//;        # remove comments at end-of-line

	if (/^\s*$/) {	    # blank line
	    last if $is_me; # That was our record. No need to read the rest.
	    $is_anon = 0;
	    $seen_disallow = 0;
	}
        elsif (/^\s*User-Agent\s*:\s*(.*)/i) {
	    $ua = $1;
	    $ua =~ s/\s+$//;

	    if ($seen_disallow) {
		# treat as start of a new record
		$seen_disallow = 0;
		last if $is_me; # That was our record. No need to read the rest.
		$is_anon = 0;
	    }

	    if ($is_me) {
		# This record already had a User-agent that
		# we matched, so just continue.
	    }
	    elsif ($ua eq '*') {
		$is_anon = 1;
	    }
	    elsif($self->is_me($ua)) {
		$is_me = 1;
	    }
	}
	elsif (/^\s*Disallow\s*:\s*(.*)/i) {
	    unless (defined $ua) {
		warn "RobotRules <$robot_txt_uri>: Disallow without preceding User-agent\n" if $^W;
		$is_anon = 1;  # assume that User-agent: * was intended
	    }
	    my $disallow = $1;
	    $disallow =~ s/\s+$//;
	    $seen_disallow = 1;
	    if (length $disallow) {
		my $ignore;
		eval {
		    my $u = URI->new_abs($disallow, $robot_txt_uri);
		    $ignore++ if $u->scheme ne $robot_txt_uri->scheme;
		    $ignore++ if lc($u->host) ne lc($robot_txt_uri->host);
		    $ignore++ if $u->port ne $robot_txt_uri->port;
		    $disallow = $u->path_query;
		    $disallow = "/" unless length $disallow;
		};
		next if $@;
		next if $ignore;
	    }

	    if ($is_me) {
		push(@me_disallowed, $disallow);
	    }
	    elsif ($is_anon) {
		push(@anon_disallowed, $disallow);
	    }
	}
        elsif (/\S\s*:/) {
             # ignore
        }
	else {
	    warn "RobotRules <$robot_txt_uri>: Malformed record: <$_>\n" if $^W;
	}
    }

    if ($is_me) {
	$self->push_rules($netloc, @me_disallowed);
    }
    else {
	$self->push_rules($netloc, @anon_disallowed);
    }
}


sub is_me {
    my($self, $ua_line) = @_;
    my $me = $self->agent;

    # See whether my short-name is a substring of the
    #  "User-Agent: ..." line that we were passed:

    if(index(lc($me), lc($ua_line)) >= 0) {
      return 1;
    }
    else {
      return '';
    }
}


sub allowed {
    my($self, $uri) = @_;
    $uri = URI->new("$uri");

    return 1 unless $uri->scheme eq 'http' or $uri->scheme eq 'https';
     # Robots.txt applies to only those schemes.

    my $netloc = $uri->host . ":" . $uri->port;

    my $fresh_until = $self->fresh_until($netloc);
    return -1 if !defined($fresh_until) || $fresh_until < time;

    my $str = $uri->path_query;
    my $rule;
    for $rule ($self->rules($netloc)) {
	return 1 unless length $rule;
	return 0 if index($str, $rule) == 0;
    }
    return 1;
}


sub agent;
sub visit;
sub no_visits;
sub last_visits;
sub fresh_until;
sub push_rules;
sub clear_rules;
sub rules;
sub dump;



package WWW::RobotRules::InCore;

use vars qw(@ISA);
@ISA = qw(WWW::RobotRules);



sub agent {
    my ($self, $name) = @_;
    my $old = $self->{'ua'};
    if ($name) {
        # Strip it so that it's just the short name.
        # I.e., "FooBot"                                      => "FooBot"
        #       "FooBot/1.2"                                  => "FooBot"
        #       "FooBot/1.2 [http://foobot.int; foo@bot.int]" => "FooBot"

	$name = $1 if $name =~ m/(\S+)/; # get first word
	$name =~ s!/.*!!;  # get rid of version
	unless ($old && $old eq $name) {
	    delete $self->{'loc'}; # all old info is now stale
	    $self->{'ua'} = $name;
	}
    }
    $old;
}


sub visit {
    my($self, $netloc, $time) = @_;
    return unless $netloc;
    $time ||= time;
    $self->{'loc'}{$netloc}{'last'} = $time;
    my $count = \$self->{'loc'}{$netloc}{'count'};
    if (!defined $$count) {
	$$count = 1;
    }
    else {
	$$count++;
    }
}


sub no_visits {
    my ($self, $netloc) = @_;
    $self->{'loc'}{$netloc}{'count'};
}


sub last_visit {
    my ($self, $netloc) = @_;
    $self->{'loc'}{$netloc}{'last'};
}


sub fresh_until {
    my ($self, $netloc, $fresh_until) = @_;
    my $old = $self->{'loc'}{$netloc}{'fresh'};
    if (defined $fresh_until) {
	$self->{'loc'}{$netloc}{'fresh'} = $fresh_until;
    }
    $old;
}


sub push_rules {
    my($self, $netloc, @rules) = @_;
    push (@{$self->{'loc'}{$netloc}{'rules'}}, @rules);
}


sub clear_rules {
    my($self, $netloc) = @_;
    delete $self->{'loc'}{$netloc}{'rules'};
}


sub rules {
    my($self, $netloc) = @_;
    if (defined $self->{'loc'}{$netloc}{'rules'}) {
	return @{$self->{'loc'}{$netloc}{'rules'}};
    }
    else {
	return ();
    }
}


sub dump
{
    my $self = shift;
    for (keys %$self) {
	next if $_ eq 'loc';
	print "$_ = $self->{$_}\n";
    }
    for (keys %{$self->{'loc'}}) {
	my @rules = $self->rules($_);
	print "$_: ", join("; ", @rules), "\n";
    }
}


1;

__END__



