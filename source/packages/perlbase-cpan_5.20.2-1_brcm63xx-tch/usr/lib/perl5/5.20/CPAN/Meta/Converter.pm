use 5.006;
use strict;
use warnings;
package CPAN::Meta::Converter;
our $VERSION = '2.140640'; # VERSION


use CPAN::Meta::Validator;
use CPAN::Meta::Requirements;
use version 0.88 ();
use Parse::CPAN::Meta 1.4400 ();
use List::Util 1.33 qw/all/;

sub _dclone {
  my $ref = shift;

  # if an object is in the data structure and doesn't specify how to
  # turn itself into JSON, we just stringify the object.  That does the
  # right thing for typical things that might be there, like version objects,
  # Path::Class objects, etc.
  no warnings 'once';
  local *UNIVERSAL::TO_JSON = sub { return "$_[0]" };

  my $backend = Parse::CPAN::Meta->json_backend();
  return $backend->new->utf8->decode(
    $backend->new->utf8->allow_blessed->convert_blessed->encode($ref)
  );
}

my %known_specs = (
    '2'   => 'http://search.cpan.org/perldoc?CPAN::Meta::Spec',
    '1.4' => 'http://module-build.sourceforge.net/META-spec-v1.4.html',
    '1.3' => 'http://module-build.sourceforge.net/META-spec-v1.3.html',
    '1.2' => 'http://module-build.sourceforge.net/META-spec-v1.2.html',
    '1.1' => 'http://module-build.sourceforge.net/META-spec-v1.1.html',
    '1.0' => 'http://module-build.sourceforge.net/META-spec-v1.0.html'
);

my @spec_list = sort { $a <=> $b } keys %known_specs;
my ($LOWEST, $HIGHEST) = @spec_list[0,-1];


sub _keep { $_[0] }

sub _keep_or_one { defined($_[0]) ? $_[0] : 1 }

sub _keep_or_zero { defined($_[0]) ? $_[0] : 0 }

sub _keep_or_unknown { defined($_[0]) && length($_[0]) ? $_[0] : "unknown" }

sub _generated_by {
  my $gen = shift;
  my $sig = __PACKAGE__ . " version " . (__PACKAGE__->VERSION || "<dev>");

  return $sig unless defined $gen and length $gen;
  return $gen if $gen =~ /\Q$sig/;
  return "$gen, $sig";
}

sub _listify { ! defined $_[0] ? undef : ref $_[0] eq 'ARRAY' ? $_[0] : [$_[0]] }

sub _prefix_custom {
  my $key = shift;
  $key =~ s/^(?!x_)   # Unless it already starts with x_
             (?:x-?)? # Remove leading x- or x (if present)
           /x_/ix;    # and prepend x_
  return $key;
}

sub _ucfirst_custom {
  my $key = shift;
  $key = ucfirst $key unless $key =~ /[A-Z]/;
  return $key;
}

sub _no_prefix_ucfirst_custom {
  my $key = shift;
  $key =~ s/^x_//;
  return _ucfirst_custom($key);
}

sub _change_meta_spec {
  my ($element, undef, undef, $version) = @_;
  return {
    version => $version,
    url => $known_specs{$version},
  };
}

my @open_source = (
  'perl',
  'gpl',
  'apache',
  'artistic',
  'artistic_2',
  'lgpl',
  'bsd',
  'gpl',
  'mit',
  'mozilla',
  'open_source',
);

my %is_open_source = map {; $_ => 1 } @open_source;

my @valid_licenses_1 = (
  @open_source,
  'unrestricted',
  'restrictive',
  'unknown',
);

my %license_map_1 = (
  ( map { $_ => $_ } @valid_licenses_1 ),
  artistic2 => 'artistic_2',
);

sub _license_1 {
  my ($element) = @_;
  return 'unknown' unless defined $element;
  if ( $license_map_1{lc $element} ) {
    return $license_map_1{lc $element};
  }
  else {
    return 'unknown';
  }
}

my @valid_licenses_2 = qw(
  agpl_3
  apache_1_1
  apache_2_0
  artistic_1
  artistic_2
  bsd
  freebsd
  gfdl_1_2
  gfdl_1_3
  gpl_1
  gpl_2
  gpl_3
  lgpl_2_1
  lgpl_3_0
  mit
  mozilla_1_0
  mozilla_1_1
  openssl
  perl_5
  qpl_1_0
  ssleay
  sun
  zlib
  open_source
  restricted
  unrestricted
  unknown
);

my %license_map_2 = (
  (map { $_ => $_ } @valid_licenses_2),
  apache      => 'apache_2_0',  # clearly stated as 2.0
  artistic    => 'artistic_1',  # clearly stated as 1
  artistic2   => 'artistic_2',  # clearly stated as 2
  gpl         => 'open_source', # we don't know which GPL; punt
  lgpl        => 'open_source', # we don't know which LGPL; punt
  mozilla     => 'open_source', # we don't know which MPL; punt
  perl        => 'perl_5',      # clearly Perl 5
  restrictive => 'restricted',
);

sub _license_2 {
  my ($element) = @_;
  return [ 'unknown' ] unless defined $element;
  $element = [ $element ] unless ref $element eq 'ARRAY';
  my @new_list;
  for my $lic ( @$element ) {
    next unless defined $lic;
    if ( my $new = $license_map_2{lc $lic} ) {
      push @new_list, $new;
    }
  }
  return @new_list ? \@new_list : [ 'unknown' ];
}

my %license_downgrade_map = qw(
  agpl_3            open_source
  apache_1_1        apache
  apache_2_0        apache
  artistic_1        artistic
  artistic_2        artistic_2
  bsd               bsd
  freebsd           open_source
  gfdl_1_2          open_source
  gfdl_1_3          open_source
  gpl_1             gpl
  gpl_2             gpl
  gpl_3             gpl
  lgpl_2_1          lgpl
  lgpl_3_0          lgpl
  mit               mit
  mozilla_1_0       mozilla
  mozilla_1_1       mozilla
  openssl           open_source
  perl_5            perl
  qpl_1_0           open_source
  ssleay            open_source
  sun               open_source
  zlib              open_source
  open_source       open_source
  restricted        restrictive
  unrestricted      unrestricted
  unknown           unknown
);

sub _downgrade_license {
  my ($element) = @_;
  if ( ! defined $element ) {
    return "unknown";
  }
  elsif( ref $element eq 'ARRAY' ) {
    if ( @$element > 1) {
      if ( all { $is_open_source{ $license_downgrade_map{lc $_} || 'unknown' } } @$element ) {
        return 'open_source';
      }
      else {
        return 'unknown';
      }
    }
    elsif ( @$element == 1 ) {
      return $license_downgrade_map{lc $element->[0]} || "unknown";
    }
  }
  elsif ( ! ref $element ) {
    return $license_downgrade_map{lc $element} || "unknown";
  }
  return "unknown";
}

my $no_index_spec_1_2 = {
  'file' => \&_listify,
  'dir' => \&_listify,
  'package' => \&_listify,
  'namespace' => \&_listify,
};

my $no_index_spec_1_3 = {
  'file' => \&_listify,
  'directory' => \&_listify,
  'package' => \&_listify,
  'namespace' => \&_listify,
};

my $no_index_spec_2 = {
  'file' => \&_listify,
  'directory' => \&_listify,
  'package' => \&_listify,
  'namespace' => \&_listify,
  ':custom'  => \&_prefix_custom,
};

sub _no_index_1_2 {
  my (undef, undef, $meta) = @_;
  my $no_index = $meta->{no_index} || $meta->{private};
  return unless $no_index;

  # cleanup wrong format
  if ( ! ref $no_index ) {
    my $item = $no_index;
    $no_index = { dir => [ $item ], file => [ $item ] };
  }
  elsif ( ref $no_index eq 'ARRAY' ) {
    my $list = $no_index;
    $no_index = { dir => [ @$list ], file => [ @$list ] };
  }

  # common mistake: files -> file
  if ( exists $no_index->{files} ) {
    $no_index->{file} = delete $no_index->{file};
  }
  # common mistake: modules -> module
  if ( exists $no_index->{modules} ) {
    $no_index->{module} = delete $no_index->{module};
  }
  return _convert($no_index, $no_index_spec_1_2);
}

sub _no_index_directory {
  my ($element, $key, $meta, $version) = @_;
  return unless $element;

  # cleanup wrong format
  if ( ! ref $element ) {
    my $item = $element;
    $element = { directory => [ $item ], file => [ $item ] };
  }
  elsif ( ref $element eq 'ARRAY' ) {
    my $list = $element;
    $element = { directory => [ @$list ], file => [ @$list ] };
  }

  if ( exists $element->{dir} ) {
    $element->{directory} = delete $element->{dir};
  }
  # common mistake: files -> file
  if ( exists $element->{files} ) {
    $element->{file} = delete $element->{file};
  }
  # common mistake: modules -> module
  if ( exists $element->{modules} ) {
    $element->{module} = delete $element->{module};
  }
  my $spec = $version == 2 ? $no_index_spec_2 : $no_index_spec_1_3;
  return _convert($element, $spec);
}

sub _is_module_name {
  my $mod = shift;
  return unless defined $mod && length $mod;
  return $mod =~ m{^[A-Za-z][A-Za-z0-9_]*(?:::[A-Za-z0-9_]+)*$};
}

sub _clean_version {
  my ($element) = @_;
  return 0 if ! defined $element;

  $element =~ s{^\s*}{};
  $element =~ s{\s*$}{};
  $element =~ s{^\.}{0.};

  return 0 if ! length $element;
  return 0 if ( $element eq 'undef' || $element eq '<undef>' );

  my $v = eval { version->new($element) };
  # XXX check defined $v and not just $v because version objects leak memory
  # in boolean context -- dagolden, 2012-02-03
  if ( defined $v ) {
    return $v->is_qv ? $v->normal : $element;
  }
  else {
    return 0;
  }
}

sub _bad_version_hook {
  my ($v) = @_;
  $v =~ s{[a-z]+$}{}; # strip trailing alphabetics
  my $vobj = eval { version->parse($v) };
  return defined($vobj) ? $vobj : version->parse(0); # or give up
}

sub _version_map {
  my ($element) = @_;
  return unless defined $element;
  if ( ref $element eq 'HASH' ) {
    # XXX turn this into CPAN::Meta::Requirements with bad version hook
    # and then turn it back into a hash
    my $new_map = CPAN::Meta::Requirements->new(
      { bad_version_hook => \&_bad_version_hook } # punt
    );
    while ( my ($k,$v) = each %$element ) {
      next unless _is_module_name($k);
      if ( !defined($v) || !length($v) || $v eq 'undef' || $v eq '<undef>'  ) {
        $v = 0;
      }
      # some weird, old META have bad yml with module => module
      # so check if value is like a module name and not like a version
      if ( _is_module_name($v) && ! version::is_lax($v) ) {
        $new_map->add_minimum($k => 0);
        $new_map->add_minimum($v => 0);
      }
      $new_map->add_string_requirement($k => $v);
    }
    return $new_map->as_string_hash;
  }
  elsif ( ref $element eq 'ARRAY' ) {
    my $hashref = { map { $_ => 0 } @$element };
    return _version_map($hashref); # cleanup any weird stuff
  }
  elsif ( ref $element eq '' && length $element ) {
    return { $element => 0 }
  }
  return;
}

sub _prereqs_from_1 {
  my (undef, undef, $meta) = @_;
  my $prereqs = {};
  for my $phase ( qw/build configure/ ) {
    my $key = "${phase}_requires";
    $prereqs->{$phase}{requires} = _version_map($meta->{$key})
      if $meta->{$key};
  }
  for my $rel ( qw/requires recommends conflicts/ ) {
    $prereqs->{runtime}{$rel} = _version_map($meta->{$rel})
      if $meta->{$rel};
  }
  return $prereqs;
}

my $prereqs_spec = {
  configure => \&_prereqs_rel,
  build     => \&_prereqs_rel,
  test      => \&_prereqs_rel,
  runtime   => \&_prereqs_rel,
  develop   => \&_prereqs_rel,
  ':custom'  => \&_prefix_custom,
};

my $relation_spec = {
  requires   => \&_version_map,
  recommends => \&_version_map,
  suggests   => \&_version_map,
  conflicts  => \&_version_map,
  ':custom'  => \&_prefix_custom,
};

sub _cleanup_prereqs {
  my ($prereqs, $key, $meta, $to_version) = @_;
  return unless $prereqs && ref $prereqs eq 'HASH';
  return _convert( $prereqs, $prereqs_spec, $to_version );
}

sub _prereqs_rel {
  my ($relation, $key, $meta, $to_version) = @_;
  return unless $relation && ref $relation eq 'HASH';
  return _convert( $relation, $relation_spec, $to_version );
}


BEGIN {
  my @old_prereqs = qw(
    requires
    configure_requires
    recommends
    conflicts
  );

  for ( @old_prereqs ) {
    my $sub = "_get_$_";
    my ($phase,$type) = split qr/_/, $_;
    if ( ! defined $type ) {
      $type = $phase;
      $phase = 'runtime';
    }
    no strict 'refs';
    *{$sub} = sub { _extract_prereqs($_[2]->{prereqs},$phase,$type) };
  }
}

sub _get_build_requires {
  my ($data, $key, $meta) = @_;

  my $test_h  = _extract_prereqs($_[2]->{prereqs}, qw(test  requires)) || {};
  my $build_h = _extract_prereqs($_[2]->{prereqs}, qw(build requires)) || {};

  my $test_req  = CPAN::Meta::Requirements->from_string_hash($test_h);
  my $build_req = CPAN::Meta::Requirements->from_string_hash($build_h);

  $test_req->add_requirements($build_req)->as_string_hash;
}

sub _extract_prereqs {
  my ($prereqs, $phase, $type) = @_;
  return unless ref $prereqs eq 'HASH';
  return scalar _version_map($prereqs->{$phase}{$type});
}

sub _downgrade_optional_features {
  my (undef, undef, $meta) = @_;
  return unless exists $meta->{optional_features};
  my $origin = $meta->{optional_features};
  my $features = {};
  for my $name ( keys %$origin ) {
    $features->{$name} = {
      description => $origin->{$name}{description},
      requires => _extract_prereqs($origin->{$name}{prereqs},'runtime','requires'),
      configure_requires => _extract_prereqs($origin->{$name}{prereqs},'runtime','configure_requires'),
      build_requires => _extract_prereqs($origin->{$name}{prereqs},'runtime','build_requires'),
      recommends => _extract_prereqs($origin->{$name}{prereqs},'runtime','recommends'),
      conflicts => _extract_prereqs($origin->{$name}{prereqs},'runtime','conflicts'),
    };
    for my $k (keys %{$features->{$name}} ) {
      delete $features->{$name}{$k} unless defined $features->{$name}{$k};
    }
  }
  return $features;
}

sub _upgrade_optional_features {
  my (undef, undef, $meta) = @_;
  return unless exists $meta->{optional_features};
  my $origin = $meta->{optional_features};
  my $features = {};
  for my $name ( keys %$origin ) {
    $features->{$name} = {
      description => $origin->{$name}{description},
      prereqs => _prereqs_from_1(undef, undef, $origin->{$name}),
    };
    delete $features->{$name}{prereqs}{configure};
  }
  return $features;
}

my $optional_features_2_spec = {
  description => \&_keep,
  prereqs => \&_cleanup_prereqs,
  ':custom'  => \&_prefix_custom,
};

sub _feature_2 {
  my ($element, $key, $meta, $to_version) = @_;
  return unless $element && ref $element eq 'HASH';
  _convert( $element, $optional_features_2_spec, $to_version );
}

sub _cleanup_optional_features_2 {
  my ($element, $key, $meta, $to_version) = @_;
  return unless $element && ref $element eq 'HASH';
  my $new_data = {};
  for my $k ( keys %$element ) {
    $new_data->{$k} = _feature_2( $element->{$k}, $k, $meta, $to_version );
  }
  return unless keys %$new_data;
  return $new_data;
}

sub _optional_features_1_4 {
  my ($element) = @_;
  return unless $element;
  $element = _optional_features_as_map($element);
  for my $name ( keys %$element ) {
    for my $drop ( qw/requires_packages requires_os excluded_os/ ) {
      delete $element->{$name}{$drop};
    }
  }
  return $element;
}

sub _optional_features_as_map {
  my ($element) = @_;
  return unless $element;
  if ( ref $element eq 'ARRAY' ) {
    my %map;
    for my $feature ( @$element ) {
      my (@parts) = %$feature;
      $map{$parts[0]} = $parts[1];
    }
    $element = \%map;
  }
  return $element;
}

sub _is_urlish { defined $_[0] && $_[0] =~ m{\A[-+.a-z0-9]+:.+}i }

sub _url_or_drop {
  my ($element) = @_;
  return $element if _is_urlish($element);
  return;
}

sub _url_list {
  my ($element) = @_;
  return unless $element;
  $element = _listify( $element );
  $element = [ grep { _is_urlish($_) } @$element ];
  return unless @$element;
  return $element;
}

sub _author_list {
  my ($element) = @_;
  return [ 'unknown' ] unless $element;
  $element = _listify( $element );
  $element = [ map { defined $_ && length $_ ? $_ : 'unknown' } @$element ];
  return [ 'unknown' ] unless @$element;
  return $element;
}

my $resource2_upgrade = {
  license    => sub { return _is_urlish($_[0]) ? _listify( $_[0] ) : undef },
  homepage   => \&_url_or_drop,
  bugtracker => sub {
    my ($item) = @_;
    return unless $item;
    if ( $item =~ m{^mailto:(.*)$} ) { return { mailto => $1 } }
    elsif( _is_urlish($item) ) { return { web => $item } }
    else { return }
  },
  repository => sub { return _is_urlish($_[0]) ? { url => $_[0] } : undef },
  ':custom'  => \&_prefix_custom,
};

sub _upgrade_resources_2 {
  my (undef, undef, $meta, $version) = @_;
  return unless exists $meta->{resources};
  return _convert($meta->{resources}, $resource2_upgrade);
}

my $bugtracker2_spec = {
  web => \&_url_or_drop,
  mailto => \&_keep,
  ':custom'  => \&_prefix_custom,
};

sub _repo_type {
  my ($element, $key, $meta, $to_version) = @_;
  return $element if defined $element;
  return unless exists $meta->{url};
  my $repo_url = $meta->{url};
  for my $type ( qw/git svn/ ) {
    return $type if $repo_url =~ m{\A$type};
  }
  return;
}

my $repository2_spec = {
  web => \&_url_or_drop,
  url => \&_url_or_drop,
  type => \&_repo_type,
  ':custom'  => \&_prefix_custom,
};

my $resources2_cleanup = {
  license    => \&_url_list,
  homepage   => \&_url_or_drop,
  bugtracker => sub { ref $_[0] ? _convert( $_[0], $bugtracker2_spec ) : undef },
  repository => sub { my $data = shift; ref $data ? _convert( $data, $repository2_spec ) : undef },
  ':custom'  => \&_prefix_custom,
};

sub _cleanup_resources_2 {
  my ($resources, $key, $meta, $to_version) = @_;
  return unless $resources && ref $resources eq 'HASH';
  return _convert($resources, $resources2_cleanup, $to_version);
}

my $resource1_spec = {
  license    => \&_url_or_drop,
  homepage   => \&_url_or_drop,
  bugtracker => \&_url_or_drop,
  repository => \&_url_or_drop,
  ':custom'  => \&_keep,
};

sub _resources_1_3 {
  my (undef, undef, $meta, $version) = @_;
  return unless exists $meta->{resources};
  return _convert($meta->{resources}, $resource1_spec);
}

*_resources_1_4 = *_resources_1_3;

sub _resources_1_2 {
  my (undef, undef, $meta) = @_;
  my $resources = $meta->{resources} || {};
  if ( $meta->{license_url} && ! $resources->{license} ) {
    $resources->{license} = $meta->license_url
      if _is_urlish($meta->{license_url});
  }
  return unless keys %$resources;
  return _convert($resources, $resource1_spec);
}

my $resource_downgrade_spec = {
  license    => sub { return ref $_[0] ? $_[0]->[0] : $_[0] },
  homepage   => \&_url_or_drop,
  bugtracker => sub { return $_[0]->{web} },
  repository => sub { return $_[0]->{url} || $_[0]->{web} },
  ':custom'  => \&_no_prefix_ucfirst_custom,
};

sub _downgrade_resources {
  my (undef, undef, $meta, $version) = @_;
  return unless exists $meta->{resources};
  return _convert($meta->{resources}, $resource_downgrade_spec);
}

sub _release_status {
  my ($element, undef, $meta) = @_;
  return $element if $element && $element =~ m{\A(?:stable|testing|unstable)\z};
  return _release_status_from_version(undef, undef, $meta);
}

sub _release_status_from_version {
  my (undef, undef, $meta) = @_;
  my $version = $meta->{version} || '';
  return ( $version =~ /_/ ) ? 'testing' : 'stable';
}

my $provides_spec = {
  file => \&_keep,
  version => \&_keep,
};

my $provides_spec_2 = {
  file => \&_keep,
  version => \&_keep,
  ':custom'  => \&_prefix_custom,
};

sub _provides {
  my ($element, $key, $meta, $to_version) = @_;
  return unless defined $element && ref $element eq 'HASH';
  my $spec = $to_version == 2 ? $provides_spec_2 : $provides_spec;
  my $new_data = {};
  for my $k ( keys %$element ) {
    $new_data->{$k} = _convert($element->{$k}, $spec, $to_version);
    $new_data->{$k}{version} = _clean_version($element->{$k}{version})
      if exists $element->{$k}{version};
  }
  return $new_data;
}

sub _convert {
  my ($data, $spec, $to_version) = @_;

  my $new_data = {};
  for my $key ( keys %$spec ) {
    next if $key eq ':custom' || $key eq ':drop';
    next unless my $fcn = $spec->{$key};
    die "spec for '$key' is not a coderef"
      unless ref $fcn && ref $fcn eq 'CODE';
    my $new_value = $fcn->($data->{$key}, $key, $data, $to_version);
    $new_data->{$key} = $new_value if defined $new_value;
  }

  my $drop_list   = $spec->{':drop'};
  my $customizer  = $spec->{':custom'} || \&_keep;

  for my $key ( keys %$data ) {
    next if $drop_list && grep { $key eq $_ } @$drop_list;
    next if exists $spec->{$key}; # we handled it
    $new_data->{ $customizer->($key) } = $data->{$key};
  }

  return $new_data;
}


my %up_convert = (
  '2-from-1.4' => {
    # PRIOR MANDATORY
    'abstract'            => \&_keep_or_unknown,
    'author'              => \&_author_list,
    'generated_by'        => \&_generated_by,
    'license'             => \&_license_2,
    'meta-spec'           => \&_change_meta_spec,
    'name'                => \&_keep,
    'version'             => \&_keep,
    # CHANGED TO MANDATORY
    'dynamic_config'      => \&_keep_or_one,
    # ADDED MANDATORY
    'release_status'      => \&_release_status_from_version,
    # PRIOR OPTIONAL
    'keywords'            => \&_keep,
    'no_index'            => \&_no_index_directory,
    'optional_features'   => \&_upgrade_optional_features,
    'provides'            => \&_provides,
    'resources'           => \&_upgrade_resources_2,
    # ADDED OPTIONAL
    'description'         => \&_keep,
    'prereqs'             => \&_prereqs_from_1,

    # drop these deprecated fields, but only after we convert
    ':drop' => [ qw(
        build_requires
        configure_requires
        conflicts
        distribution_type
        license_url
        private
        recommends
        requires
    ) ],

    # other random keys need x_ prefixing
    ':custom'              => \&_prefix_custom,
  },
  '1.4-from-1.3' => {
    # PRIOR MANDATORY
    'abstract'            => \&_keep_or_unknown,
    'author'              => \&_author_list,
    'generated_by'        => \&_generated_by,
    'license'             => \&_license_1,
    'meta-spec'           => \&_change_meta_spec,
    'name'                => \&_keep,
    'version'             => \&_keep,
    # PRIOR OPTIONAL
    'build_requires'      => \&_version_map,
    'conflicts'           => \&_version_map,
    'distribution_type'   => \&_keep,
    'dynamic_config'      => \&_keep_or_one,
    'keywords'            => \&_keep,
    'no_index'            => \&_no_index_directory,
    'optional_features'   => \&_optional_features_1_4,
    'provides'            => \&_provides,
    'recommends'          => \&_version_map,
    'requires'            => \&_version_map,
    'resources'           => \&_resources_1_4,
    # ADDED OPTIONAL
    'configure_requires'  => \&_keep,

    # drop these deprecated fields, but only after we convert
    ':drop' => [ qw(
      license_url
      private
    )],

    # other random keys are OK if already valid
    ':custom'              => \&_keep
  },
  '1.3-from-1.2' => {
    # PRIOR MANDATORY
    'abstract'            => \&_keep_or_unknown,
    'author'              => \&_author_list,
    'generated_by'        => \&_generated_by,
    'license'             => \&_license_1,
    'meta-spec'           => \&_change_meta_spec,
    'name'                => \&_keep,
    'version'             => \&_keep,
    # PRIOR OPTIONAL
    'build_requires'      => \&_version_map,
    'conflicts'           => \&_version_map,
    'distribution_type'   => \&_keep,
    'dynamic_config'      => \&_keep_or_one,
    'keywords'            => \&_keep,
    'no_index'            => \&_no_index_directory,
    'optional_features'   => \&_optional_features_as_map,
    'provides'            => \&_provides,
    'recommends'          => \&_version_map,
    'requires'            => \&_version_map,
    'resources'           => \&_resources_1_3,

    # drop these deprecated fields, but only after we convert
    ':drop' => [ qw(
      license_url
      private
    )],

    # other random keys are OK if already valid
    ':custom'              => \&_keep
  },
  '1.2-from-1.1' => {
    # PRIOR MANDATORY
    'version'             => \&_keep,
    # CHANGED TO MANDATORY
    'license'             => \&_license_1,
    'name'                => \&_keep,
    'generated_by'        => \&_generated_by,
    # ADDED MANDATORY
    'abstract'            => \&_keep_or_unknown,
    'author'              => \&_author_list,
    'meta-spec'           => \&_change_meta_spec,
    # PRIOR OPTIONAL
    'build_requires'      => \&_version_map,
    'conflicts'           => \&_version_map,
    'distribution_type'   => \&_keep,
    'dynamic_config'      => \&_keep_or_one,
    'recommends'          => \&_version_map,
    'requires'            => \&_version_map,
    # ADDED OPTIONAL
    'keywords'            => \&_keep,
    'no_index'            => \&_no_index_1_2,
    'optional_features'   => \&_optional_features_as_map,
    'provides'            => \&_provides,
    'resources'           => \&_resources_1_2,

    # drop these deprecated fields, but only after we convert
    ':drop' => [ qw(
      license_url
      private
    )],

    # other random keys are OK if already valid
    ':custom'              => \&_keep
  },
  '1.1-from-1.0' => {
    # CHANGED TO MANDATORY
    'version'             => \&_keep,
    # IMPLIED MANDATORY
    'name'                => \&_keep,
    # PRIOR OPTIONAL
    'build_requires'      => \&_version_map,
    'conflicts'           => \&_version_map,
    'distribution_type'   => \&_keep,
    'dynamic_config'      => \&_keep_or_one,
    'generated_by'        => \&_generated_by,
    'license'             => \&_license_1,
    'recommends'          => \&_version_map,
    'requires'            => \&_version_map,
    # ADDED OPTIONAL
    'license_url'         => \&_url_or_drop,
    'private'             => \&_keep,

    # other random keys are OK if already valid
    ':custom'              => \&_keep
  },
);

my %down_convert = (
  '1.4-from-2' => {
    # MANDATORY
    'abstract'            => \&_keep_or_unknown,
    'author'              => \&_author_list,
    'generated_by'        => \&_generated_by,
    'license'             => \&_downgrade_license,
    'meta-spec'           => \&_change_meta_spec,
    'name'                => \&_keep,
    'version'             => \&_keep,
    # OPTIONAL
    'build_requires'      => \&_get_build_requires,
    'configure_requires'  => \&_get_configure_requires,
    'conflicts'           => \&_get_conflicts,
    'distribution_type'   => \&_keep,
    'dynamic_config'      => \&_keep_or_one,
    'keywords'            => \&_keep,
    'no_index'            => \&_no_index_directory,
    'optional_features'   => \&_downgrade_optional_features,
    'provides'            => \&_provides,
    'recommends'          => \&_get_recommends,
    'requires'            => \&_get_requires,
    'resources'           => \&_downgrade_resources,

    # drop these unsupported fields (after conversion)
    ':drop' => [ qw(
      description
      prereqs
      release_status
    )],

    # custom keys will be left unchanged
    ':custom'              => \&_keep
  },
  '1.3-from-1.4' => {
    # MANDATORY
    'abstract'            => \&_keep_or_unknown,
    'author'              => \&_author_list,
    'generated_by'        => \&_generated_by,
    'license'             => \&_license_1,
    'meta-spec'           => \&_change_meta_spec,
    'name'                => \&_keep,
    'version'             => \&_keep,
    # OPTIONAL
    'build_requires'      => \&_version_map,
    'conflicts'           => \&_version_map,
    'distribution_type'   => \&_keep,
    'dynamic_config'      => \&_keep_or_one,
    'keywords'            => \&_keep,
    'no_index'            => \&_no_index_directory,
    'optional_features'   => \&_optional_features_as_map,
    'provides'            => \&_provides,
    'recommends'          => \&_version_map,
    'requires'            => \&_version_map,
    'resources'           => \&_resources_1_3,

    # drop these unsupported fields, but only after we convert
    ':drop' => [ qw(
      configure_requires
    )],

    # other random keys are OK if already valid
    ':custom'              => \&_keep,
  },
  '1.2-from-1.3' => {
    # MANDATORY
    'abstract'            => \&_keep_or_unknown,
    'author'              => \&_author_list,
    'generated_by'        => \&_generated_by,
    'license'             => \&_license_1,
    'meta-spec'           => \&_change_meta_spec,
    'name'                => \&_keep,
    'version'             => \&_keep,
    # OPTIONAL
    'build_requires'      => \&_version_map,
    'conflicts'           => \&_version_map,
    'distribution_type'   => \&_keep,
    'dynamic_config'      => \&_keep_or_one,
    'keywords'            => \&_keep,
    'no_index'            => \&_no_index_1_2,
    'optional_features'   => \&_optional_features_as_map,
    'provides'            => \&_provides,
    'recommends'          => \&_version_map,
    'requires'            => \&_version_map,
    'resources'           => \&_resources_1_3,

    # other random keys are OK if already valid
    ':custom'              => \&_keep,
  },
  '1.1-from-1.2' => {
    # MANDATORY
    'version'             => \&_keep,
    # IMPLIED MANDATORY
    'name'                => \&_keep,
    'meta-spec'           => \&_change_meta_spec,
    # OPTIONAL
    'build_requires'      => \&_version_map,
    'conflicts'           => \&_version_map,
    'distribution_type'   => \&_keep,
    'dynamic_config'      => \&_keep_or_one,
    'generated_by'        => \&_generated_by,
    'license'             => \&_license_1,
    'private'             => \&_keep,
    'recommends'          => \&_version_map,
    'requires'            => \&_version_map,

    # drop unsupported fields
    ':drop' => [ qw(
      abstract
      author
      provides
      no_index
      keywords
      resources
    )],

    # other random keys are OK if already valid
    ':custom'              => \&_keep,
  },
  '1.0-from-1.1' => {
    # IMPLIED MANDATORY
    'name'                => \&_keep,
    'meta-spec'           => \&_change_meta_spec,
    'version'             => \&_keep,
    # PRIOR OPTIONAL
    'build_requires'      => \&_version_map,
    'conflicts'           => \&_version_map,
    'distribution_type'   => \&_keep,
    'dynamic_config'      => \&_keep_or_one,
    'generated_by'        => \&_generated_by,
    'license'             => \&_license_1,
    'recommends'          => \&_version_map,
    'requires'            => \&_version_map,

    # other random keys are OK if already valid
    ':custom'              => \&_keep,
  },
);

my %cleanup = (
  '2' => {
    # PRIOR MANDATORY
    'abstract'            => \&_keep_or_unknown,
    'author'              => \&_author_list,
    'generated_by'        => \&_generated_by,
    'license'             => \&_license_2,
    'meta-spec'           => \&_change_meta_spec,
    'name'                => \&_keep,
    'version'             => \&_keep,
    # CHANGED TO MANDATORY
    'dynamic_config'      => \&_keep_or_one,
    # ADDED MANDATORY
    'release_status'      => \&_release_status,
    # PRIOR OPTIONAL
    'keywords'            => \&_keep,
    'no_index'            => \&_no_index_directory,
    'optional_features'   => \&_cleanup_optional_features_2,
    'provides'            => \&_provides,
    'resources'           => \&_cleanup_resources_2,
    # ADDED OPTIONAL
    'description'         => \&_keep,
    'prereqs'             => \&_cleanup_prereqs,

    # drop these deprecated fields, but only after we convert
    ':drop' => [ qw(
        build_requires
        configure_requires
        conflicts
        distribution_type
        license_url
        private
        recommends
        requires
    ) ],

    # other random keys need x_ prefixing
    ':custom'              => \&_prefix_custom,
  },
  '1.4' => {
    # PRIOR MANDATORY
    'abstract'            => \&_keep_or_unknown,
    'author'              => \&_author_list,
    'generated_by'        => \&_generated_by,
    'license'             => \&_license_1,
    'meta-spec'           => \&_change_meta_spec,
    'name'                => \&_keep,
    'version'             => \&_keep,
    # PRIOR OPTIONAL
    'build_requires'      => \&_version_map,
    'conflicts'           => \&_version_map,
    'distribution_type'   => \&_keep,
    'dynamic_config'      => \&_keep_or_one,
    'keywords'            => \&_keep,
    'no_index'            => \&_no_index_directory,
    'optional_features'   => \&_optional_features_1_4,
    'provides'            => \&_provides,
    'recommends'          => \&_version_map,
    'requires'            => \&_version_map,
    'resources'           => \&_resources_1_4,
    # ADDED OPTIONAL
    'configure_requires'  => \&_keep,

    # other random keys are OK if already valid
    ':custom'             => \&_keep
  },
  '1.3' => {
    # PRIOR MANDATORY
    'abstract'            => \&_keep_or_unknown,
    'author'              => \&_author_list,
    'generated_by'        => \&_generated_by,
    'license'             => \&_license_1,
    'meta-spec'           => \&_change_meta_spec,
    'name'                => \&_keep,
    'version'             => \&_keep,
    # PRIOR OPTIONAL
    'build_requires'      => \&_version_map,
    'conflicts'           => \&_version_map,
    'distribution_type'   => \&_keep,
    'dynamic_config'      => \&_keep_or_one,
    'keywords'            => \&_keep,
    'no_index'            => \&_no_index_directory,
    'optional_features'   => \&_optional_features_as_map,
    'provides'            => \&_provides,
    'recommends'          => \&_version_map,
    'requires'            => \&_version_map,
    'resources'           => \&_resources_1_3,

    # other random keys are OK if already valid
    ':custom'             => \&_keep
  },
  '1.2' => {
    # PRIOR MANDATORY
    'version'             => \&_keep,
    # CHANGED TO MANDATORY
    'license'             => \&_license_1,
    'name'                => \&_keep,
    'generated_by'        => \&_generated_by,
    # ADDED MANDATORY
    'abstract'            => \&_keep_or_unknown,
    'author'              => \&_author_list,
    'meta-spec'           => \&_change_meta_spec,
    # PRIOR OPTIONAL
    'build_requires'      => \&_version_map,
    'conflicts'           => \&_version_map,
    'distribution_type'   => \&_keep,
    'dynamic_config'      => \&_keep_or_one,
    'recommends'          => \&_version_map,
    'requires'            => \&_version_map,
    # ADDED OPTIONAL
    'keywords'            => \&_keep,
    'no_index'            => \&_no_index_1_2,
    'optional_features'   => \&_optional_features_as_map,
    'provides'            => \&_provides,
    'resources'           => \&_resources_1_2,

    # other random keys are OK if already valid
    ':custom'             => \&_keep
  },
  '1.1' => {
    # CHANGED TO MANDATORY
    'version'             => \&_keep,
    # IMPLIED MANDATORY
    'name'                => \&_keep,
    'meta-spec'           => \&_change_meta_spec,
    # PRIOR OPTIONAL
    'build_requires'      => \&_version_map,
    'conflicts'           => \&_version_map,
    'distribution_type'   => \&_keep,
    'dynamic_config'      => \&_keep_or_one,
    'generated_by'        => \&_generated_by,
    'license'             => \&_license_1,
    'recommends'          => \&_version_map,
    'requires'            => \&_version_map,
    # ADDED OPTIONAL
    'license_url'         => \&_url_or_drop,
    'private'             => \&_keep,

    # other random keys are OK if already valid
    ':custom'             => \&_keep
  },
  '1.0' => {
    # IMPLIED MANDATORY
    'name'                => \&_keep,
    'meta-spec'           => \&_change_meta_spec,
    'version'             => \&_keep,
    # IMPLIED OPTIONAL
    'build_requires'      => \&_version_map,
    'conflicts'           => \&_version_map,
    'distribution_type'   => \&_keep,
    'dynamic_config'      => \&_keep_or_one,
    'generated_by'        => \&_generated_by,
    'license'             => \&_license_1,
    'recommends'          => \&_version_map,
    'requires'            => \&_version_map,

    # other random keys are OK if already valid
    ':custom'             => \&_keep,
  },
);



sub new {
  my ($class,$data) = @_;

  # create an attributes hash
  my $self = {
    'data'    => $data,
    'spec'    => _extract_spec_version($data),
  };

  # create the object
  return bless $self, $class;
}

sub _extract_spec_version {
    my ($data) = @_;
    my $spec = $data->{'meta-spec'};

    # is meta-spec there and valid?
    return "1.0" unless defined $spec && ref $spec eq 'HASH'; # before meta-spec?

    # does the version key look like a valid version?
    my $v = $spec->{version};
    if ( defined $v && $v =~ /^\d+(?:\.\d+)?$/ ) {
        return $v if defined $v && grep { $v eq $_ } keys %known_specs; # known spec
        return $v+0 if defined $v && grep { $v == $_ } keys %known_specs; # 2.0 => 2
    }

    # otherwise, use heuristics: look for 1.x vs 2.0 fields
    return "2" if exists $data->{prereqs};
    return "1.4" if exists $data->{configure_requires};
    return "1.2"; # when meta-spec was first defined
}


sub convert {
  my ($self, %args) = @_;
  my $args = { %args };

  my $new_version = $args->{version} || $HIGHEST;

  my ($old_version) = $self->{spec};
  my $converted = _dclone($self->{data});

  if ( $old_version == $new_version ) {
    $converted = _convert( $converted, $cleanup{$old_version}, $old_version );
    my $cmv = CPAN::Meta::Validator->new( $converted );
    unless ( $cmv->is_valid ) {
      my $errs = join("\n", $cmv->errors);
      die "Failed to clean-up $old_version metadata. Errors:\n$errs\n";
    }
    return $converted;
  }
  elsif ( $old_version > $new_version )  {
    my @vers = sort { $b <=> $a } keys %known_specs;
    for my $i ( 0 .. $#vers-1 ) {
      next if $vers[$i] > $old_version;
      last if $vers[$i+1] < $new_version;
      my $spec_string = "$vers[$i+1]-from-$vers[$i]";
      $converted = _convert( $converted, $down_convert{$spec_string}, $vers[$i+1] );
      my $cmv = CPAN::Meta::Validator->new( $converted );
      unless ( $cmv->is_valid ) {
        my $errs = join("\n", $cmv->errors);
        die "Failed to downconvert metadata to $vers[$i+1]. Errors:\n$errs\n";
      }
    }
    return $converted;
  }
  else {
    my @vers = sort { $a <=> $b } keys %known_specs;
    for my $i ( 0 .. $#vers-1 ) {
      next if $vers[$i] < $old_version;
      last if $vers[$i+1] > $new_version;
      my $spec_string = "$vers[$i+1]-from-$vers[$i]";
      $converted = _convert( $converted, $up_convert{$spec_string}, $vers[$i+1] );
      my $cmv = CPAN::Meta::Validator->new( $converted );
      unless ( $cmv->is_valid ) {
        my $errs = join("\n", $cmv->errors);
        die "Failed to upconvert metadata to $vers[$i+1]. Errors:\n$errs\n";
      }
    }
    return $converted;
  }
}

1;


__END__

