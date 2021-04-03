package Unicode::Collate::Locale;

use strict;
use Carp;
use base qw(Unicode::Collate);

our $VERSION = '1.02';

my $PL_EXT  = '.pl';

my %LocaleFile = map { ($_, $_) } qw(
   af ar as az be bg bn ca cs cy da ee eo es et fa fi fil fo fr
   gu ha haw hi hr hu hy ig is ja kk kl kn ko kok ln lt lv
   mk ml mr mt nb nn nso om or pa pl ro ru sa se si sk sl sq
   sr sv ta te th tn to tr uk ur vi wae wo yo zh
);
   $LocaleFile{'default'} = '';
   $LocaleFile{'bs'}      = 'hr';
   $LocaleFile{'bs_Cyrl'} = 'sr';
   $LocaleFile{'sr_Latn'} = 'hr';
   $LocaleFile{'de__phonebook'}   = 'de_phone';
   $LocaleFile{'es__traditional'} = 'es_trad';
   $LocaleFile{'fi__phonebook'}   = 'fi_phone';
   $LocaleFile{'si__dictionary'}  = 'si_dict';
   $LocaleFile{'sv__reformed'}    = 'sv_refo';
   $LocaleFile{'zh__big5han'}     = 'zh_big5';
   $LocaleFile{'zh__gb2312han'}   = 'zh_gb';
   $LocaleFile{'zh__pinyin'}      = 'zh_pin';
   $LocaleFile{'zh__stroke'}      = 'zh_strk';
   $LocaleFile{'zh__zhuyin'}      = 'zh_zhu';

my %TypeAlias = qw(
    phone     phonebook
    phonebk   phonebook
    dict      dictionary
    reform    reformed
    trad      traditional
    big5      big5han
    gb2312    gb2312han
);

sub _locale {
    my $locale = shift;
    if ($locale) {
	$locale = lc $locale;
	$locale =~ tr/\-\ \./_/;
	$locale =~ s/_([0-9a-z]+)\z/$TypeAlias{$1} ?
				  "_$TypeAlias{$1}" : "_$1"/e;
	$LocaleFile{$locale} and return $locale;

	my @code = split /_/, $locale;
	my $lan = shift @code;
	my $scr = @code && length $code[0] == 4 ? ucfirst shift @code : '';
	my $reg = @code && length $code[0] <  4 ? uc      shift @code : '';
	my $var = @code                         ?         shift @code : '';

	my @list;
	push @list, (
	    "${lan}_${scr}_${reg}_$var",
	    "${lan}_${scr}__$var", # empty $scr should not be ${lan}__$var.
	    "${lan}_${reg}_$var",  # empty $reg may be ${lan}__$var.
	    "${lan}__$var",
	) if $var ne '';
	push @list, (
	    "${lan}_${scr}_${reg}",
	    "${lan}_${scr}",
	    "${lan}_${reg}",
	     ${lan},
	);
	for my $loc (@list) {
	    $LocaleFile{$loc} and return $loc;
	}
    }
    return 'default';
}

sub getlocale {
    return shift->{accepted_locale};
}

sub locale_version {
    return shift->{locale_version};
}

sub _fetchpl {
    my $accepted = shift;
    my $f = $LocaleFile{$accepted};
    return if !$f;
    $f .= $PL_EXT;

    # allow to search @INC
    my $path = "Unicode/Collate/Locale/$f";
    my $h = do $path;
    croak "Unicode/Collate/Locale/$f can't be found" if !$h;
    return $h;
}

sub new {
    my $class = shift;
    my %hash = @_;
    $hash{accepted_locale} = _locale($hash{locale});

    if (exists $hash{table}) {
	croak "your table can't be used with Unicode::Collate::Locale";
    }

    my $href = _fetchpl($hash{accepted_locale});
    while (my($k,$v) = each %$href) {
	if (!exists $hash{$k}) {
	    $hash{$k} = $v;
	} elsif ($k eq 'entry') {
	    $hash{$k} = $v.$hash{$k};
	} else {
	    croak "$k is reserved by $hash{locale}, can't be overwritten";
	}
    }
    return $class->SUPER::new(%hash);
}

1;
__END__

MEMORANDA for developing

locale            based CLDR
----------------------------------------------------------------------------
af                22.1 = 1.8.1
ar                22.1 = 1.9.0
as                22.1 = 1.8.1
az                22.1 = 1.8.1 (type="standard")
be                22.1 = 1.9.0
bg                22.1 = 1.9.0
bn                22.1 = 2.0.1 (type="standard")
bs                22.1 = 1.9.0 (alias source="hr")
bs_Cyrl           22.1 = 22    (alias source="sr")
ca                22.1 = 1.8.1 (alt="proposed" type="standard")
cs                22.1 = 1.8.1 (type="standard")
cy                22.1 = 1.8.1
da                22.1 = 1.8.1 (type="standard") [mod aA to pass CLDR test]
de__phonebook     22.1 = 2.0   (type="phonebook")
ee                22.1 = 22
eo                22.1 = 1.8.1
es                22.1 = 1.9.0 (type="standard")
es__traditional   22.1 = 1.8.1 (type="traditional")
et                22.1 = 1.8.1
fa                22.1 = 1.8.1
fi                22.1 = 1.8.1 (type="standard" alt="proposed")
fi__phonebook     22.1 = 1.8.1 (type="phonebook")
fil               22.1 = 1.9.0 (type="standard") = 1.8.1
fo                22.1 = 1.8.1 (alt="proposed" type="standard")
fr                22.1 = 1.9.0 (fr_CA, backwards="on")
gu                22.1 = 1.9.0 (type="standard")
ha                22.1 = 1.9.0
haw               22.1 = 1.8.1
hi                22.1 = 1.9.0 (type="standard")
hr                22.1 = 1.9.0 (type="standard")
hu                22.1 = 1.8.1 (alt="proposed" type="standard")
hy                22.1 = 1.8.1
ig                22.1 = 1.8.1
is                22.1 = 1.8.1 (type="standard")
ja                22.1 = 1.8.1 (type="standard")
kk                22.1 = 1.9.0
kl                22.1 = 1.8.1 (type="standard")
kn                22.1 = 1.9.0 (type="standard")
ko                22.1 = 1.8.1 (type="standard")
kok               22.1 = 1.8.1
ln                22.1 = 2.0   (type="standard") = 1.8.1
lt                22.1 = 1.9.0
lv                22.1 = 1.9.0 (type="standard") = 1.8.1
mk                22.1 = 1.9.0
ml                22.1 = 1.9.0
mr                22.1 = 1.8.1
mt                22.1 = 1.9.0
nb                22.1 = 2.0   (type="standard")
nn                22.1 = 2.0   (type="standard")
nso               22.1 = 1.8.1
om                22.1 = 1.8.1
or                22.1 = 1.9.0
pa                22.1 = 1.8.1
pl                22.1 = 1.8.1
ro                22.1 = 1.9.0 (type="standard")
ru                22.1 = 1.9.0
sa                1.9.1 = 1.8.1 (type="standard" alt="proposed") [now /seed]
se                22.1 = 1.8.1 (type="standard")
si                22.1 = 1.9.0 (type="standard")
si__dictionary    22.1 = 1.9.0 (type="dictionary")
sk                22.1 = 1.9.0 (type="standard")
sl                22.1 = 1.8.1 (type="standard" alt="proposed")
sq                22.1 = 1.8.1 (alt="proposed" type="standard")
sr                22.1 = 1.9.0 (type="standard")
sr_Latn           22.1 = 1.8.1 (alias source="hr")
sv                22.1 = 1.9.0 (type="standard")
sv__reformed      22.1 = 1.8.1 (type="reformed")
ta                22.1 = 1.9.0
te                22.1 = 1.9.0
th                22.1 = 22
tn                22.1 = 1.8.1
to                22.1 = 22
tr                22.1 = 1.8.1 (type="standard")
uk                22.1 = 21
ur                22.1 = 1.9.0
vi                22.1 = 1.8.1
wae               22.1 = 2.0
wo                1.9.1 = 1.8.1 [now /seed]
yo                22.1 = 1.8.1
zh                22.1 = 1.8.1 (type="standard")
zh__big5han       22.1 = 1.8.1 (type="big5han")
zh__gb2312han     22.1 = 1.8.1 (type="gb2312han")
zh__pinyin        22.1 = 2.0   (type='pinyin' alt='short')
zh__stroke        22.1 = 1.9.1 (type='stroke' alt='short')
zh__zhuyin        22.1 = 22    (type='zhuyin' alt='short')
----------------------------------------------------------------------------

