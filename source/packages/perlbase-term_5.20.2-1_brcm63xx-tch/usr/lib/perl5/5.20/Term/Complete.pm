package Term::Complete;
require 5.000;
require Exporter;

use strict;
our @ISA = qw(Exporter);
our @EXPORT = qw(Complete);
our $VERSION = '1.402';



our($complete, $kill, $erase1, $erase2, $tty_raw_noecho, $tty_restore, $stty, $tty_safe_restore);
our($tty_saved_state) = '';
CONFIG: {
    $complete = "\004";
    $kill     = "\025";
    $erase1 =   "\177";
    $erase2 =   "\010";
    foreach my $s (qw(/bin/stty /usr/bin/stty)) {
	if (-x $s) {
	    $tty_raw_noecho = "$s raw -echo";
	    $tty_restore    = "$s -raw echo";
	    $tty_safe_restore = $tty_restore;
	    $stty = $s;
	    last;
	}
    }
}

sub Complete {
    my($prompt, @cmp_lst, $cmp, $test, $l, @match);
    my ($return, $r) = ("", 0);

    $return = "";
    $r      = 0;

    $prompt = shift;
    if (ref $_[0] || $_[0] =~ /^\*/) {
	@cmp_lst = sort @{$_[0]};
    }
    else {
	@cmp_lst = sort(@_);
    }

    # Attempt to save the current stty state, to be restored later
    if (defined $stty && defined $tty_saved_state && $tty_saved_state eq '') {
	$tty_saved_state = qx($stty -g 2>/dev/null);
	if ($?) {
	    # stty -g not supported
	    $tty_saved_state = undef;
	}
	else {
	    $tty_saved_state =~ s/\s+$//g;
	    $tty_restore = qq($stty "$tty_saved_state" 2>/dev/null);
	}
    }
    system $tty_raw_noecho if defined $tty_raw_noecho;
    LOOP: {
        local $_;
        print($prompt, $return);
        while (($_ = getc(STDIN)) ne "\r") {
            CASE: {
                # (TAB) attempt completion
                $_ eq "\t" && do {
                    @match = grep(/^\Q$return/, @cmp_lst);
                    unless ($#match < 0) {
                        $l = length($test = shift(@match));
                        foreach $cmp (@match) {
                            until (substr($cmp, 0, $l) eq substr($test, 0, $l)) {
                                $l--;
                            }
                        }
                        print("\a");
                        print($test = substr($test, $r, $l - $r));
                        $r = length($return .= $test);
                    }
                    last CASE;
                };

                # (^D) completion list
                $_ eq $complete && do {
                    print(join("\r\n", '', grep(/^\Q$return/, @cmp_lst)), "\r\n");
                    redo LOOP;
                };

                # (^U) kill
                $_ eq $kill && do {
                    if ($r) {
                        $r	= 0;
			$return	= "";
                        print("\r\n");
                        redo LOOP;
                    }
                    last CASE;
                };

                # (DEL) || (BS) erase
                ($_ eq $erase1 || $_ eq $erase2) && do {
                    if($r) {
                        print("\b \b");
                        chop($return);
                        $r--;
                    }
                    last CASE;
                };

                # printable char
                ord >= 32 && do {
                    $return .= $_;
                    $r++;
                    print;
                    last CASE;
                };
            }
        }
    }

    # system $tty_restore if defined $tty_restore;
    if (defined $tty_saved_state && defined $tty_restore && defined $tty_safe_restore)
    {
	system $tty_restore;
	if ($?) {
	    # tty_restore caused error
	    system $tty_safe_restore;
	}
    }
    print("\n");
    $return;
}

1;
