package LWP::Simple;

use strict;
use vars qw($ua %loop_check $FULL_LWP @EXPORT @EXPORT_OK $VERSION);

require Exporter;

@EXPORT = qw(get head getprint getstore mirror);
@EXPORT_OK = qw($ua);

use HTTP::Status;
push(@EXPORT, @HTTP::Status::EXPORT);

$VERSION = "5.835";

sub import
{
    my $pkg = shift;
    my $callpkg = caller;
    Exporter::export($pkg, $callpkg, @_);
}

use LWP::UserAgent ();
use HTTP::Status ();
use HTTP::Date ();
$ua = LWP::UserAgent->new;  # we create a global UserAgent object
$ua->agent("LWP::Simple/$VERSION ");
$ua->env_proxy;


sub get ($)
{
    my $response = $ua->get(shift);
    return $response->decoded_content if $response->is_success;
    return undef;
}


sub head ($)
{
    my($url) = @_;
    my $request = HTTP::Request->new(HEAD => $url);
    my $response = $ua->request($request);

    if ($response->is_success) {
	return $response unless wantarray;
	return (scalar $response->header('Content-Type'),
		scalar $response->header('Content-Length'),
		HTTP::Date::str2time($response->header('Last-Modified')),
		HTTP::Date::str2time($response->header('Expires')),
		scalar $response->header('Server'),
	       );
    }
    return;
}


sub getprint ($)
{
    my($url) = @_;
    my $request = HTTP::Request->new(GET => $url);
    local($\) = ""; # ensure standard $OUTPUT_RECORD_SEPARATOR
    my $callback = sub { print $_[0] };
    if ($^O eq "MacOS") {
	$callback = sub { $_[0] =~ s/\015?\012/\n/g; print $_[0] }
    }
    my $response = $ua->request($request, $callback);
    unless ($response->is_success) {
	print STDERR $response->status_line, " <URL:$url>\n";
    }
    $response->code;
}


sub getstore ($$)
{
    my($url, $file) = @_;
    my $request = HTTP::Request->new(GET => $url);
    my $response = $ua->request($request, $file);

    $response->code;
}


sub mirror ($$)
{
    my($url, $file) = @_;
    my $response = $ua->mirror($url, $file);
    $response->code;
}


1;

__END__

