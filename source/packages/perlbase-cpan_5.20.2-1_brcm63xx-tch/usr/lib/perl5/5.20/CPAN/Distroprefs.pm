
use 5.006;
use strict;
package CPAN::Distroprefs;

use vars qw($VERSION);
$VERSION = '6.0001';

package CPAN::Distroprefs::Result;

use File::Spec;

sub new { bless $_[1] || {} => $_[0] }

sub abs { File::Spec->catfile($_[0]->dir, $_[0]->file) }

sub __cloner {
    my ($class, $name, $newclass) = @_;
    $newclass = 'CPAN::Distroprefs::Result::' . $newclass;
    no strict 'refs';
    *{$class . '::' . $name} = sub {
        $newclass->new({
            %{ $_[0] },
            %{ $_[1] },
        });
    };
}
BEGIN { __PACKAGE__->__cloner(as_warning => 'Warning') }
BEGIN { __PACKAGE__->__cloner(as_fatal   => 'Fatal') }
BEGIN { __PACKAGE__->__cloner(as_success => 'Success') }

sub __accessor {
    my ($class, $key) = @_;
    no strict 'refs';
    *{$class . '::' . $key} = sub { $_[0]->{$key} };
}
BEGIN { __PACKAGE__->__accessor($_) for qw(type file ext dir) }

sub is_warning { 0 }
sub is_fatal   { 0 }
sub is_success { 0 }

package CPAN::Distroprefs::Result::Error;
use vars qw(@ISA);
BEGIN { @ISA = 'CPAN::Distroprefs::Result' } ## no critic
BEGIN { __PACKAGE__->__accessor($_) for qw(msg) }

sub as_string {
    my ($self) = @_;
    if ($self->msg) {
        return sprintf $self->fmt_reason, $self->file, $self->msg;
    } else {
        return sprintf $self->fmt_unknown, $self->file;
    }
}

package CPAN::Distroprefs::Result::Warning;
use vars qw(@ISA);
BEGIN { @ISA = 'CPAN::Distroprefs::Result::Error' } ## no critic
sub is_warning { 1 }
sub fmt_reason  { "Error reading distroprefs file %s, skipping: %s" }
sub fmt_unknown { "Unknown error reading distroprefs file %s, skipping." }

package CPAN::Distroprefs::Result::Fatal;
use vars qw(@ISA);
BEGIN { @ISA = 'CPAN::Distroprefs::Result::Error' } ## no critic
sub is_fatal { 1 }
sub fmt_reason  { "Error reading distroprefs file %s: %s" }
sub fmt_unknown { "Unknown error reading distroprefs file %s." }

package CPAN::Distroprefs::Result::Success;
use vars qw(@ISA);
BEGIN { @ISA = 'CPAN::Distroprefs::Result' } ## no critic
BEGIN { __PACKAGE__->__accessor($_) for qw(prefs extension) }
sub is_success { 1 }

package CPAN::Distroprefs::Iterator;

sub new { bless $_[1] => $_[0] }

sub next { $_[0]->() }

package CPAN::Distroprefs;

use Carp ();
use DirHandle;

sub _load_method {
    my ($self, $loader, $result) = @_;
    return '_load_yaml' if $loader eq 'CPAN' or $loader =~ /^YAML(::|$)/;
    return '_load_' . $result->ext;
}

sub _load_yaml {
    my ($self, $loader, $result) = @_;
    my $data = eval {
        $loader eq 'CPAN'
        ? $loader->_yaml_loadfile($result->abs)
        : [ $loader->can('LoadFile')->($result->abs) ]
    };
    if (my $err = $@) {
        die $result->as_warning({
            msg  => $err,
        });
    } elsif (!$data) {
        die $result->as_warning;
    } else {
        return @$data;
    }
}

sub _load_dd {
    my ($self, $loader, $result) = @_;
    my @data;
    {
        package CPAN::Eval;
        # this caused a die in CPAN.pm, and I am leaving it 'fatal', though I'm
        # not sure why we wouldn't just skip the file as we do for all other
        # errors. -- hdp
        my $abs = $result->abs;
        open FH, "<$abs" or die $result->as_fatal(msg => "$!");
        local $/;
        my $eval = <FH>;
        close FH;
        no strict;
        eval $eval;
        if (my $err = $@) {
            die $result->as_warning({ msg => $err });
        }
        my $i = 1;
        while (${"VAR$i"}) {
            push @data, ${"VAR$i"};
            $i++;
        }
    }
    return @data;
}

sub _load_st {
    my ($self, $loader, $result) = @_;
    # eval because Storable is never forward compatible
    my @data = eval { @{scalar $loader->can('retrieve')->($result->abs) } };
    if (my $err = $@) {
        die $result->as_warning({ msg => $err });
    }
    return @data;
}

sub _build_file_list {
    if (@_ > 3) {
        die "_build_file_list should be called with 3 arguments, was called with more. First argument is '$_[0]'.";
    }
    my ($dir, $dir1, $ext_re) = @_;
    my @list;
    my $dh;
    unless (opendir($dh, $dir)) {
        $CPAN::Frontend->mywarn("ignoring prefs directory '$dir': $!");
        return @list;
    }
    while (my $fn = readdir $dh) {
        next if $fn eq '.' || $fn eq '..';
        if (-d "$dir/$fn") {
            next if $fn =~ /^[._]/; # prune .svn, .git, .hg, _darcs and what the user wants to hide
            push @list, _build_file_list("$dir/$fn", "$dir1$fn/", $ext_re);
        } else {
            if ($fn =~ $ext_re) {
                push @list, "$dir1$fn";
            }
        }
    }
    return @list;
}

sub find {
    my ($self, $dir, $ext_map) = @_;

    return CPAN::Distroprefs::Iterator->new(sub { return }) unless %$ext_map;

    my $possible_ext = join "|", map { quotemeta } keys %$ext_map;
    my $ext_re = qr/\.($possible_ext)$/;

    my @files = _build_file_list($dir, '', $ext_re);
    @files = sort @files if @files;

    # label the block so that we can use redo in the middle
    return CPAN::Distroprefs::Iterator->new(sub { LOOP: {

        my $fn = shift @files;
        return unless defined $fn;
        my ($ext) = $fn =~ $ext_re;

        my $loader = $ext_map->{$ext};

        my $result = CPAN::Distroprefs::Result->new({
            file => $fn, ext => $ext, dir => $dir
        });
        # copied from CPAN.pm; is this ever actually possible?
        redo unless -f $result->abs;

        my $load_method = $self->_load_method($loader, $result);
        my @prefs = eval { $self->$load_method($loader, $result) };
        if (my $err = $@) {
            if (ref($err) && eval { $err->isa('CPAN::Distroprefs::Result') }) {
                return $err;
            }
            # rethrow any exceptions that we did not generate
            die $err;
        } elsif (!@prefs) {
            # the loader should have handled this, but just in case:
            return $result->as_warning;
        }
        return $result->as_success({
            prefs => [
                map { CPAN::Distroprefs::Pref->new({ data => $_ }) } @prefs
            ],
        });
    } });
}

package CPAN::Distroprefs::Pref;

use Carp ();

sub new { bless $_[1] => $_[0] }

sub data { shift->{data} }

sub has_any_match { $_[0]->data->{match} ? 1 : 0 }

sub has_match {
    my $match = $_[0]->data->{match} || return 0;
    exists $match->{$_[1]} || exists $match->{"not_$_[1]"}
}

sub has_valid_subkeys {
    grep { exists $_[0]->data->{match}{$_} }
        map { $_, "not_$_" }
        $_[0]->match_attributes
}

sub _pattern {
    my $re = shift;
    my $p = eval sprintf 'qr{%s}', $re;
    if ($@) {
        $@ =~ s/\n$//;
        die "Error in Distroprefs pattern qr{$re}\n$@";
    }
    return $p;
}

sub _match_scalar {
    my ($match, $data) = @_;
    my $qr = _pattern($match);
    return $data =~ /$qr/;
}

sub _match_hash {
    my ($match, $data) = @_;
    for my $mkey (keys %$match) {
	(my $dkey = $mkey) =~ s/^not_//;
        my $val = defined $data->{$dkey} ? $data->{$dkey} : '';
	if (_match_scalar($match->{$mkey}, $val)) {
	    return 0 if $mkey =~ /^not_/;
	}
	else {
	    return 0 if $mkey !~ /^not_/;
	}
    }
    return 1;
}

sub _match {
    my ($self, $key, $data, $matcher) = @_;
    my $m = $self->data->{match};
    if (exists $m->{$key}) {
	return 0 unless $matcher->($m->{$key}, $data);
    }
    if (exists $m->{"not_$key"}) {
	return 0 if $matcher->($m->{"not_$key"}, $data);
    }
    return 1;
}

sub _scalar_match {
    my ($self, $key, $data) = @_;
    return $self->_match($key, $data, \&_match_scalar);
}

sub _hash_match {
    my ($self, $key, $data) = @_;
    return $self->_match($key, $data, \&_match_hash);
}

sub match_attributes { qw(env distribution perl perlconfig module) }

sub match_module {
    my ($self, $modules) = @_;
    return $self->_match("module", $modules, sub {
	my($match, $data) = @_;
	my $qr = _pattern($match);
	for my $module (@$data) {
	    return 1 if $module =~ /$qr/;
	}
	return 0;
    });
}

sub match_distribution { shift->_scalar_match(distribution => @_) }
sub match_perl         { shift->_scalar_match(perl         => @_) }

sub match_perlconfig   { shift->_hash_match(perlconfig => @_) }
sub match_env          { shift->_hash_match(env        => @_) }

sub matches {
    my ($self, $arg) = @_;

    my $default_match = 0;
    for my $key (grep { $self->has_match($_) } $self->match_attributes) {
        unless (exists $arg->{$key}) {
            Carp::croak "Can't match pref: missing argument key $key";
        }
        $default_match = 1;
        my $val = $arg->{$key};
        # make it possible to avoid computing things until we have to
        if (ref($val) eq 'CODE') { $val = $val->() }
        my $meth = "match_$key";
        return 0 unless $self->$meth($val);
    }

    return $default_match;
}

1;

__END__

