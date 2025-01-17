
require 5.008;

use strict;

use DBI ();
require DBI::SQL::Nano;

package DBI::DBD::SqlEngine;

use strict;

use Carp;
use vars qw( @ISA $VERSION $drh %methods_installed);

$VERSION = "0.06";

$drh = undef;    # holds driver handle(s) once initialized

DBI->setup_driver("DBI::DBD::SqlEngine");    # only needed once but harmless to repeat

my %accessors = (
                  versions   => "get_driver_versions",
                  get_meta   => "get_sql_engine_meta",
                  set_meta   => "set_sql_engine_meta",
                  clear_meta => "clear_sql_engine_meta",
                );

sub driver ($;$)
{
    my ( $class, $attr ) = @_;

    # Drivers typically use a singleton object for the $drh
    # We use a hash here to have one singleton per subclass.
    # (Otherwise DBD::CSV and DBD::DBM, for example, would
    # share the same driver object which would cause problems.)
    # An alternative would be to not cache the $drh here at all
    # and require that subclasses do that. Subclasses should do
    # their own caching, so caching here just provides extra safety.
    $drh->{$class} and return $drh->{$class};

    $attr ||= {};
    {
        no strict "refs";
        unless ( $attr->{Attribution} )
        {
            $class eq "DBI::DBD::SqlEngine"
              and $attr->{Attribution} = "$class by Jens Rehsack";
            $attr->{Attribution} ||= ${ $class . "::ATTRIBUTION" }
              || "oops the author of $class forgot to define this";
        }
        $attr->{Version} ||= ${ $class . "::VERSION" };
        $attr->{Name} or ( $attr->{Name} = $class ) =~ s/^DBD\:\://;
    }

    $drh->{$class} = DBI::_new_drh( $class . "::dr", $attr );
    $drh->{$class}->STORE( ShowErrorStatement => 1 );

    my $prefix = DBI->driver_prefix($class);
    if ($prefix)
    {
        my $dbclass = $class . "::db";
        while ( my ( $accessor, $funcname ) = each %accessors )
        {
            my $method = $prefix . $accessor;
            $dbclass->can($method) and next;
            my $inject = sprintf <<'EOI', $dbclass, $method, $dbclass, $funcname;
sub %s::%s
{
    my $func = %s->can (q{%s});
    goto &$func;
    }
EOI
            eval $inject;
            $dbclass->install_method($method);
        }
    }
    else
    {
        warn "Using DBI::DBD::SqlEngine with unregistered driver $class.\n"
          . "Reading documentation how to prevent is strongly recommended.\n";

    }

    # XXX inject DBD::XXX::Statement unless exists

    my $stclass = $class . "::st";
    $stclass->install_method("sql_get_colnames") unless ( $methods_installed{__PACKAGE__}++ );

    return $drh->{$class};
}    # driver

sub CLONE
{
    undef $drh;
}    # CLONE


package DBI::DBD::SqlEngine::dr;

use strict;
use warnings;

use vars qw(@ISA $imp_data_size);

use Carp qw/carp/;

$imp_data_size = 0;

sub connect ($$;$$$)
{
    my ( $drh, $dbname, $user, $auth, $attr ) = @_;

    # create a 'blank' dbh
    my $dbh = DBI::_new_dbh(
                             $drh,
                             {
                                Name         => $dbname,
                                USER         => $user,
                                CURRENT_USER => $user,
                             }
                           );

    if ($dbh)
    {
        # must be done first, because setting flags implicitly calls $dbdname::db->STORE
        $dbh->func( 0, "init_default_attributes" );
        my $two_phased_init;
        defined $dbh->{sql_init_phase} and $two_phased_init = ++$dbh->{sql_init_phase};
        my %second_phase_attrs;
        my @func_inits;

        # this must be done to allow DBI.pm reblessing got handle after successful connecting
        exists $attr->{RootClass} and $second_phase_attrs{RootClass} = delete $attr->{RootClass};

        my ( $var, $val );
        while ( length $dbname )
        {
            if ( $dbname =~ s/^((?:[^\\;]|\\.)*?);//s )
            {
                $var = $1;
            }
            else
            {
                $var    = $dbname;
                $dbname = "";
            }

            if ( $var =~ m/^(.+?)=(.*)/s )
            {
                $var = $1;
                ( $val = $2 ) =~ s/\\(.)/$1/g;
                exists $attr->{$var}
                  and carp("$var is given in DSN *and* \$attr during DBI->connect()")
                  if ($^W);
                exists $attr->{$var} or $attr->{$var} = $val;
            }
            elsif ( $var =~ m/^(.+?)=>(.*)/s )
            {
                $var = $1;
                ( $val = $2 ) =~ s/\\(.)/$1/g;
                my $ref = eval $val;
                # $dbh->$var($ref);
                push( @func_inits, $var, $ref );
            }
        }

        # The attributes need to be sorted in a specific way as the
        # assignment is through tied hashes and calls STORE on each
        # attribute.  Some attributes require to be called prior to
        # others
        # e.g. f_dir *must* be done before xx_tables in DBD::File
        # The dbh attribute sql_init_order is a hash with the order
        # as key (low is first, 0 .. 100) and the attributes that
        # are set to that oreder as anon-list as value:
        # {  0 => [qw( AutoCommit PrintError RaiseError Profile ... )],
        #   10 => [ list of attr to be dealt with immediately after first ],
        #   50 => [ all fields that are unspecified or default sort order ],
        #   90 => [ all fields that are needed after other initialisation ],
        #   }

        my %order = map {
            my $order = $_;
            map { ( $_ => $order ) } @{ $dbh->{sql_init_order}{$order} };
        } sort { $a <=> $b } keys %{ $dbh->{sql_init_order} || {} };
        my @ordered_attr =
          map  { $_->[0] }
          sort { $a->[1] <=> $b->[1] }
          map  { [ $_, defined $order{$_} ? $order{$_} : 50 ] }
          keys %$attr;

        # initialize given attributes ... lower weighted before higher weighted
        foreach my $a (@ordered_attr)
        {
            exists $attr->{$a} or next;
            $two_phased_init and eval {
                $dbh->{$a} = $attr->{$a};
                delete $attr->{$a};
            };
            $@ and $second_phase_attrs{$a} = delete $attr->{$a};
            $two_phased_init or $dbh->STORE( $a, delete $attr->{$a} );
        }

        $two_phased_init and $dbh->func( 1, "init_default_attributes" );
        %$attr = %second_phase_attrs;

        for ( my $i = 0; $i < scalar(@func_inits); $i += 2 )
        {
            my $func = $func_inits[$i];
            my $arg  = $func_inits[ $i + 1 ];
            $dbh->$func($arg);
        }

        $dbh->func("init_done");

        $dbh->STORE( Active => 1 );
    }

    return $dbh;
}    # connect

sub data_sources ($;$)
{
    my ( $drh, $attr ) = @_;

    my $tbl_src;
    $attr
      and defined $attr->{sql_table_source}
      and $attr->{sql_table_source}->isa('DBI::DBD::SqlEngine::TableSource')
      and $tbl_src = $attr->{sql_table_source};

    !defined($tbl_src)
      and $drh->{ImplementorClass}->can('default_table_source')
      and $tbl_src = $drh->{ImplementorClass}->default_table_source();
    defined($tbl_src) or return;

    $tbl_src->data_sources( $drh, $attr );
}    # data_sources

sub disconnect_all
{
}    # disconnect_all

sub DESTROY
{
    undef;
}    # DESTROY


package DBI::DBD::SqlEngine::db;

use strict;
use warnings;

use vars qw(@ISA $imp_data_size);

use Carp;

if ( eval { require Clone; } )
{
    Clone->import("clone");
}
else
{
    require Storable;    # in CORE since 5.7.3
    *clone = \&Storable::dclone;
}

$imp_data_size = 0;

sub ping
{
    ( $_[0]->FETCH("Active") ) ? 1 : 0;
}    # ping

sub data_sources
{
    my ( $dbh, $attr, @other ) = @_;
    my $drh = $dbh->{Driver};    # XXX proxy issues?
    ref($attr) eq 'HASH' or $attr = {};
    defined( $attr->{sql_table_source} ) or $attr->{sql_table_source} = $dbh->{sql_table_source};
    return $drh->data_sources( $attr, @other );
}

sub prepare ($$;@)
{
    my ( $dbh, $statement, @attribs ) = @_;

    # create a 'blank' sth
    my $sth = DBI::_new_sth( $dbh, { Statement => $statement } );

    if ($sth)
    {
        my $class = $sth->FETCH("ImplementorClass");
        $class =~ s/::st$/::Statement/;
        my $stmt;

        # if using SQL::Statement version > 1
        # cache the parser object if the DBD supports parser caching
        # SQL::Nano and older SQL::Statements don't support this

        if ( $class->isa("SQL::Statement") )
        {
            my $parser = $dbh->{sql_parser_object};
            $parser ||= eval { $dbh->func("sql_parser_object") };
            if ($@)
            {
                $stmt = eval { $class->new($statement) };
            }
            else
            {
                $stmt = eval { $class->new( $statement, $parser ) };
            }
        }
        else
        {
            $stmt = eval { $class->new($statement) };
        }
        if ( $@ || $stmt->{errstr} )
        {
            $dbh->set_err( $DBI::stderr, $@ || $stmt->{errstr} );
            undef $sth;
        }
        else
        {
            $sth->STORE( "sql_stmt", $stmt );
            $sth->STORE( "sql_params", [] );
            $sth->STORE( "NUM_OF_PARAMS", scalar( $stmt->params() ) );
            my @colnames = $sth->sql_get_colnames();
            $sth->STORE( "NUM_OF_FIELDS", scalar @colnames );
        }
    }
    return $sth;
}    # prepare

sub set_versions
{
    my $dbh = $_[0];
    $dbh->{sql_engine_version} = $DBI::DBD::SqlEngine::VERSION;
    for (qw( nano_version statement_version ))
    {
        defined $DBI::SQL::Nano::versions->{$_} or next;
        $dbh->{"sql_$_"} = $DBI::SQL::Nano::versions->{$_};
    }
    $dbh->{sql_handler} =
      $dbh->{sql_statement_version}
      ? "SQL::Statement"
      : "DBI::SQL::Nano";

    return $dbh;
}    # set_versions

sub init_valid_attributes
{
    my $dbh = $_[0];

    $dbh->{sql_valid_attrs} = {
                             sql_engine_version         => 1,    # DBI::DBD::SqlEngine version
                             sql_handler                => 1,    # Nano or S:S
                             sql_nano_version           => 1,    # Nano version
                             sql_statement_version      => 1,    # S:S version
                             sql_flags                  => 1,    # flags for SQL::Parser
                             sql_dialect                => 1,    # dialect for SQL::Parser
                             sql_quoted_identifier_case => 1,    # case for quoted identifiers
                             sql_identifier_case        => 1,    # case for non-quoted identifiers
                             sql_parser_object          => 1,    # SQL::Parser instance
                             sql_sponge_driver          => 1,    # Sponge driver for table_info ()
                             sql_valid_attrs            => 1,    # SQL valid attributes
                             sql_readonly_attrs         => 1,    # SQL readonly attributes
                             sql_init_phase             => 1,    # Only during initialization
                             sql_meta                   => 1,    # meta data for tables
                             sql_meta_map               => 1,    # mapping table for identifier case
                              };
    $dbh->{sql_readonly_attrs} = {
                               sql_engine_version         => 1,    # DBI::DBD::SqlEngine version
                               sql_handler                => 1,    # Nano or S:S
                               sql_nano_version           => 1,    # Nano version
                               sql_statement_version      => 1,    # S:S version
                               sql_quoted_identifier_case => 1,    # case for quoted identifiers
                               sql_parser_object          => 1,    # SQL::Parser instance
                               sql_sponge_driver          => 1,    # Sponge driver for table_info ()
                               sql_valid_attrs            => 1,    # SQL valid attributes
                               sql_readonly_attrs         => 1,    # SQL readonly attributes
                                 };

    return $dbh;
}    # init_valid_attributes

sub init_default_attributes
{
    my ( $dbh, $phase ) = @_;
    my $given_phase = $phase;

    unless ( defined($phase) )
    {
        # we have an "old" driver here
        $phase = defined $dbh->{sql_init_phase};
        $phase and $phase = $dbh->{sql_init_phase};
    }

    if ( 0 == $phase )
    {
        # must be done first, because setting flags implicitly calls $dbdname::db->STORE
        $dbh->func("init_valid_attributes");

        $dbh->func("set_versions");

        $dbh->{sql_identifier_case}        = 2;    # SQL_IC_LOWER
        $dbh->{sql_quoted_identifier_case} = 3;    # SQL_IC_SENSITIVE

        $dbh->{sql_dialect} = "CSV";

        $dbh->{sql_init_phase} = $given_phase;

        # complete derived attributes, if required
        ( my $drv_class = $dbh->{ImplementorClass} ) =~ s/::db$//;
        my $drv_prefix  = DBI->driver_prefix($drv_class);
        my $valid_attrs = $drv_prefix . "valid_attrs";
        my $ro_attrs    = $drv_prefix . "readonly_attrs";

        # check whether we're running in a Gofer server or not (see
        # validate_FETCH_attr for details)
        $dbh->{sql_engine_in_gofer} =
          ( defined $INC{"DBD/Gofer.pm"} && ( caller(5) )[0] eq "DBI::Gofer::Execute" );
        $dbh->{sql_meta}     = {};
        $dbh->{sql_meta_map} = {};    # choose new name because it contains other keys

        # init_default_attributes calls inherited routine before derived DBD's
        # init their default attributes, so we don't override something here
        #
        # defining an order of attribute initialization from connect time
        # specified ones with a magic baarier (see next statement)
        my $drv_pfx_meta = $drv_prefix . "meta";
        $dbh->{sql_init_order} = {
                           0  => [qw( Profile RaiseError PrintError AutoCommit )],
                           90 => [ "sql_meta", $dbh->{$drv_pfx_meta} ? $dbh->{$drv_pfx_meta} : () ],
        };
        # ensuring Profile, RaiseError, PrintError, AutoCommit are initialized
        # first when initializing attributes from connect time specified
        # attributes
        # further, initializations to predefined tables are happens after any
        # unspecified attribute initialization (that default to order 50)

        my @comp_attrs = qw(valid_attrs version readonly_attrs);

        if ( exists $dbh->{$drv_pfx_meta} and !$dbh->{sql_engine_in_gofer} )
        {
            my $attr = $dbh->{$drv_pfx_meta};
                  defined $attr
              and defined $dbh->{$valid_attrs}
              and !defined $dbh->{$valid_attrs}{$attr}
              and $dbh->{$valid_attrs}{$attr} = 1;

            my %h;
            tie %h, "DBI::DBD::SqlEngine::TieTables", $dbh;
            $dbh->{$attr} = \%h;

            push @comp_attrs, "meta";
        }

        foreach my $comp_attr (@comp_attrs)
        {
            my $attr = $drv_prefix . $comp_attr;
            defined $dbh->{$valid_attrs}
              and !defined $dbh->{$valid_attrs}{$attr}
              and $dbh->{$valid_attrs}{$attr} = 1;
            defined $dbh->{$ro_attrs}
              and !defined $dbh->{$ro_attrs}{$attr}
              and $dbh->{$ro_attrs}{$attr} = 1;
        }
    }

    return $dbh;
}    # init_default_attributes

sub init_done
{
    defined $_[0]->{sql_init_phase} and delete $_[0]->{sql_init_phase};
    delete $_[0]->{sql_valid_attrs}->{sql_init_phase};
    return;
}

sub sql_parser_object
{
    my $dbh = $_[0];
    my $dialect = $dbh->{sql_dialect} || "CSV";
    my $parser = {
                   RaiseError => $dbh->FETCH("RaiseError"),
                   PrintError => $dbh->FETCH("PrintError"),
                 };
    my $sql_flags = $dbh->FETCH("sql_flags") || {};
    %$parser = ( %$parser, %$sql_flags );
    $parser = SQL::Parser->new( $dialect, $parser );
    $dbh->{sql_parser_object} = $parser;
    return $parser;
}    # sql_parser_object

sub sql_sponge_driver
{
    my $dbh  = $_[0];
    my $dbh2 = $dbh->{sql_sponge_driver};
    unless ($dbh2)
    {
        $dbh2 = $dbh->{sql_sponge_driver} = DBI->connect("DBI:Sponge:");
        unless ($dbh2)
        {
            $dbh->set_err( $DBI::stderr, $DBI::errstr );
            return;
        }
    }
}

sub disconnect ($)
{
    %{ $_[0]->{sql_meta} }     = ();
    %{ $_[0]->{sql_meta_map} } = ();
    $_[0]->STORE( Active => 0 );
    return 1;
}    # disconnect

sub validate_FETCH_attr
{
    my ( $dbh, $attrib ) = @_;

    # If running in a Gofer server, access to our tied compatibility hash
    # would force Gofer to serialize the tieing object including it's
    # private $dbh reference used to do the driver function calls.
    # This will result in nasty exceptions. So return a copy of the
    # sql_meta structure instead, which is the source of for the compatibility
    # tie-hash. It's not as good as liked, but the best we can do in this
    # situation.
    if ( $dbh->{sql_engine_in_gofer} )
    {
        ( my $drv_class = $dbh->{ImplementorClass} ) =~ s/::db$//;
        my $drv_prefix = DBI->driver_prefix($drv_class);
        exists $dbh->{ $drv_prefix . "meta" } && $attrib eq $dbh->{ $drv_prefix . "meta" }
          and $attrib = "sql_meta";
    }

    return $attrib;
}

sub FETCH ($$)
{
    my ( $dbh, $attrib ) = @_;
    $attrib eq "AutoCommit"
      and return 1;

    # Driver private attributes are lower cased
    if ( $attrib eq ( lc $attrib ) )
    {
        # first let the implementation deliver an alias for the attribute to fetch
        # after it validates the legitimation of the fetch request
        $attrib = $dbh->func( $attrib, "validate_FETCH_attr" ) or return;

        my $attr_prefix;
        $attrib =~ m/^([a-z]+_)/ and $attr_prefix = $1;
        unless ($attr_prefix)
        {
            ( my $drv_class = $dbh->{ImplementorClass} ) =~ s/::db$//;
            $attr_prefix = DBI->driver_prefix($drv_class);
            $attrib      = $attr_prefix . $attrib;
        }
        my $valid_attrs = $attr_prefix . "valid_attrs";
        my $ro_attrs    = $attr_prefix . "readonly_attrs";

        exists $dbh->{$valid_attrs}
          and ( $dbh->{$valid_attrs}{$attrib}
                or return $dbh->set_err( $DBI::stderr, "Invalid attribute '$attrib'" ) );
        exists $dbh->{$ro_attrs}
          and $dbh->{$ro_attrs}{$attrib}
          and defined $dbh->{$attrib}
          and refaddr( $dbh->{$attrib} )
          and return clone( $dbh->{$attrib} );

        return $dbh->{$attrib};
    }
    # else pass up to DBI to handle
    return $dbh->SUPER::FETCH($attrib);
}    # FETCH

sub validate_STORE_attr
{
    my ( $dbh, $attrib, $value ) = @_;

    if (     $attrib eq "sql_identifier_case" || $attrib eq "sql_quoted_identifier_case"
         and $value < 1 || $value > 4 )
    {
        croak "attribute '$attrib' must have a value from 1 .. 4 (SQL_IC_UPPER .. SQL_IC_MIXED)";
        # XXX correctly a remap of all entries in sql_meta/sql_meta_map is required here
    }

    ( my $drv_class = $dbh->{ImplementorClass} ) =~ s/::db$//;
    my $drv_prefix = DBI->driver_prefix($drv_class);

    exists $dbh->{ $drv_prefix . "meta" }
      and $attrib eq $dbh->{ $drv_prefix . "meta" }
      and $attrib = "sql_meta";

    return ( $attrib, $value );
}

sub STORE ($$$)
{
    my ( $dbh, $attrib, $value ) = @_;

    if ( $attrib eq "AutoCommit" )
    {
        $value and return 1;    # is already set
        croak "Can't disable AutoCommit";
    }

    if ( $attrib eq lc $attrib )
    {
        # Driver private attributes are lower cased

        ( $attrib, $value ) = $dbh->func( $attrib, $value, "validate_STORE_attr" );
        $attrib or return;

        my $attr_prefix;
        $attrib =~ m/^([a-z]+_)/ and $attr_prefix = $1;
        unless ($attr_prefix)
        {
            ( my $drv_class = $dbh->{ImplementorClass} ) =~ s/::db$//;
            $attr_prefix = DBI->driver_prefix($drv_class);
            $attrib      = $attr_prefix . $attrib;
        }
        my $valid_attrs = $attr_prefix . "valid_attrs";
        my $ro_attrs    = $attr_prefix . "readonly_attrs";

        exists $dbh->{$valid_attrs}
          and ( $dbh->{$valid_attrs}{$attrib}
                or return $dbh->set_err( $DBI::stderr, "Invalid attribute '$attrib'" ) );
        exists $dbh->{$ro_attrs}
          and $dbh->{$ro_attrs}{$attrib}
          and defined $dbh->{$attrib}
          and return $dbh->set_err( $DBI::stderr,
                                    "attribute '$attrib' is readonly and must not be modified" );

        if ( $attrib eq "sql_meta" )
        {
            while ( my ( $k, $v ) = each %$value )
            {
                $dbh->{$attrib}{$k} = $v;
            }
        }
        else
        {
            $dbh->{$attrib} = $value;
        }

        return 1;
    }

    return $dbh->SUPER::STORE( $attrib, $value );
}    # STORE

sub get_driver_versions
{
    my ( $dbh, $table ) = @_;
    my %vsn = (
                OS   => "$^O ($Config::Config{osvers})",
                Perl => "$] ($Config::Config{archname})",
                DBI  => $DBI::VERSION,
              );
    my %vmp;

    my $sql_engine_verinfo =
      join " ",
      $dbh->{sql_engine_version}, "using", $dbh->{sql_handler},
      $dbh->{sql_handler} eq "SQL::Statement"
      ? $dbh->{sql_statement_version}
      : $dbh->{sql_nano_version};

    my $indent   = 0;
    my @deriveds = ( $dbh->{ImplementorClass} );
    while (@deriveds)
    {
        my $derived = shift @deriveds;
        $derived eq "DBI::DBD::SqlEngine::db" and last;
        $derived->isa("DBI::DBD::SqlEngine::db") or next;
        #no strict 'refs';
        eval "push \@deriveds, \@${derived}::ISA";
        #use strict;
        ( my $drv_class = $derived ) =~ s/::db$//;
        my $drv_prefix  = DBI->driver_prefix($drv_class);
        my $ddgv        = $dbh->{ImplementorClass}->can("get_${drv_prefix}versions");
        my $drv_version = $ddgv ? &$ddgv( $dbh, $table ) : $dbh->{ $drv_prefix . "version" };
        $drv_version ||=
          eval { $derived->VERSION() };    # XXX access $drv_class::VERSION via symbol table
        $vsn{$drv_class} = $drv_version;
        $indent and $vmp{$drv_class} = " " x $indent . $drv_class;
        $indent += 2;
    }

    $vsn{"DBI::DBD::SqlEngine"} = $sql_engine_verinfo;
    $indent and $vmp{"DBI::DBD::SqlEngine"} = " " x $indent . "DBI::DBD::SqlEngine";

    $DBI::PurePerl and $vsn{"DBI::PurePerl"} = $DBI::PurePerl::VERSION;

    $indent += 20;
    my @versions = map { sprintf "%-${indent}s %s", $vmp{$_} || $_, $vsn{$_} }
      sort {
        $a->isa($b)                    and return -1;
        $b->isa($a)                    and return 1;
        $a->isa("DBI::DBD::SqlEngine") and return -1;
        $b->isa("DBI::DBD::SqlEngine") and return 1;
        return $a cmp $b;
      } keys %vsn;

    return wantarray ? @versions : join "\n", @versions;
}    # get_versions

sub get_single_table_meta
{
    my ( $dbh, $table, $attr ) = @_;
    my $meta;

    $table eq "."
      and return $dbh->FETCH($attr);

    ( my $class = $dbh->{ImplementorClass} ) =~ s/::db$/::Table/;
    ( undef, $meta ) = $class->get_table_meta( $dbh, $table, 1 );
    $meta or croak "No such table '$table'";

    # prevent creation of undef attributes
    return $class->get_table_meta_attr( $meta, $attr );
}    # get_single_table_meta

sub get_sql_engine_meta
{
    my ( $dbh, $table, $attr ) = @_;

    my $gstm = $dbh->{ImplementorClass}->can("get_single_table_meta");

    $table eq "*"
      and $table = [ ".", keys %{ $dbh->{sql_meta} } ];
    $table eq "+"
      and $table = [ grep { m/^[_A-Za-z0-9]+$/ } keys %{ $dbh->{sql_meta} } ];
    ref $table eq "Regexp"
      and $table = [ grep { $_ =~ $table } keys %{ $dbh->{sql_meta} } ];

    ref $table || ref $attr
      or return &$gstm( $dbh, $table, $attr );

    ref $table or $table = [$table];
    ref $attr  or $attr  = [$attr];
    "ARRAY" eq ref $table
      or return
      $dbh->set_err( $DBI::stderr,
          "Invalid argument for \$table - SCALAR, Regexp or ARRAY expected but got " . ref $table );
    "ARRAY" eq ref $attr
      or return $dbh->set_err(
                    "Invalid argument for \$attr - SCALAR or ARRAY expected but got " . ref $attr );

    my %results;
    foreach my $tname ( @{$table} )
    {
        my %tattrs;
        foreach my $aname ( @{$attr} )
        {
            $tattrs{$aname} = &$gstm( $dbh, $tname, $aname );
        }
        $results{$tname} = \%tattrs;
    }

    return \%results;
}    # get_sql_engine_meta

sub set_single_table_meta
{
    my ( $dbh, $table, $attr, $value ) = @_;
    my $meta;

    $table eq "."
      and return $dbh->STORE( $attr, $value );

    ( my $class = $dbh->{ImplementorClass} ) =~ s/::db$/::Table/;
    ( undef, $meta ) = $class->get_table_meta( $dbh, $table, 1 );
    $meta or croak "No such table '$table'";
    $class->set_table_meta_attr( $meta, $attr, $value );

    return $dbh;
}    # set_single_table_meta

sub set_sql_engine_meta
{
    my ( $dbh, $table, $attr, $value ) = @_;

    my $sstm = $dbh->{ImplementorClass}->can("set_single_table_meta");

    $table eq "*"
      and $table = [ ".", keys %{ $dbh->{sql_meta} } ];
    $table eq "+"
      and $table = [ grep { m/^[_A-Za-z0-9]+$/ } keys %{ $dbh->{sql_meta} } ];
    ref($table) eq "Regexp"
      and $table = [ grep { $_ =~ $table } keys %{ $dbh->{sql_meta} } ];

    ref $table || ref $attr
      or return &$sstm( $dbh, $table, $attr, $value );

    ref $table or $table = [$table];
    ref $attr or $attr = { $attr => $value };
    "ARRAY" eq ref $table
      or croak "Invalid argument for \$table - SCALAR, Regexp or ARRAY expected but got "
      . ref $table;
    "HASH" eq ref $attr
      or croak "Invalid argument for \$attr - SCALAR or HASH expected but got " . ref $attr;

    foreach my $tname ( @{$table} )
    {
        my %tattrs;
        while ( my ( $aname, $aval ) = each %$attr )
        {
            &$sstm( $dbh, $tname, $aname, $aval );
        }
    }

    return $dbh;
}    # set_file_meta

sub clear_sql_engine_meta
{
    my ( $dbh, $table ) = @_;

    ( my $class = $dbh->{ImplementorClass} ) =~ s/::db$/::Table/;
    my ( undef, $meta ) = $class->get_table_meta( $dbh, $table, 1 );
    $meta and %{$meta} = ();

    return;
}    # clear_file_meta

sub DESTROY ($)
{
    my $dbh = shift;
    $dbh->SUPER::FETCH("Active") and $dbh->disconnect;
    undef $dbh->{sql_parser_object};
}    # DESTROY

sub type_info_all ($)
{
    [
       {
          TYPE_NAME          => 0,
          DATA_TYPE          => 1,
          PRECISION          => 2,
          LITERAL_PREFIX     => 3,
          LITERAL_SUFFIX     => 4,
          CREATE_PARAMS      => 5,
          NULLABLE           => 6,
          CASE_SENSITIVE     => 7,
          SEARCHABLE         => 8,
          UNSIGNED_ATTRIBUTE => 9,
          MONEY              => 10,
          AUTO_INCREMENT     => 11,
          LOCAL_TYPE_NAME    => 12,
          MINIMUM_SCALE      => 13,
          MAXIMUM_SCALE      => 14,
       },
       [
          "VARCHAR", DBI::SQL_VARCHAR(), undef, "'", "'", undef, 0, 1, 1, 0, 0, 0, undef, 1, 999999,
       ],
       [ "CHAR", DBI::SQL_CHAR(), undef, "'", "'", undef, 0, 1, 1, 0, 0, 0, undef, 1, 999999, ],
       [ "INTEGER", DBI::SQL_INTEGER(), undef, "", "", undef, 0, 0, 1, 0, 0, 0, undef, 0, 0, ],
       [ "REAL",    DBI::SQL_REAL(),    undef, "", "", undef, 0, 0, 1, 0, 0, 0, undef, 0, 0, ],
       [
          "BLOB", DBI::SQL_LONGVARBINARY(), undef, "'", "'", undef, 0, 1, 1, 0, 0, 0, undef, 1,
          999999,
       ],
       [
          "BLOB", DBI::SQL_LONGVARBINARY(), undef, "'", "'", undef, 0, 1, 1, 0, 0, 0, undef, 1,
          999999,
       ],
       [
          "TEXT", DBI::SQL_LONGVARCHAR(), undef, "'", "'", undef, 0, 1, 1, 0, 0, 0, undef, 1,
          999999,
       ],
    ];
}    # type_info_all

sub get_avail_tables
{
    my $dbh    = $_[0];
    my @tables = ();

    if ( $dbh->{sql_handler} eq "SQL::Statement" and $dbh->{sql_ram_tables} )
    {
        # XXX map +[ undef, undef, $_, "TABLE", "TEMP" ], keys %{...}
        foreach my $table ( keys %{ $dbh->{sql_ram_tables} } )
        {
            push @tables, [ undef, undef, $table, "TABLE", "TEMP" ];
        }
    }

    my $tbl_src;
    defined $dbh->{sql_table_source}
      and $dbh->{sql_table_source}->isa('DBI::DBD::SqlEngine::TableSource')
      and $tbl_src = $dbh->{sql_table_source};

    !defined($tbl_src)
      and $dbh->{Driver}->{ImplementorClass}->can('default_table_source')
      and $tbl_src = $dbh->{Driver}->{ImplementorClass}->default_table_source();
    defined($tbl_src) and push( @tables, $tbl_src->avail_tables($dbh) );

    return @tables;
}    # get_avail_tables

{
    my $names = [qw( TABLE_QUALIFIER TABLE_OWNER TABLE_NAME TABLE_TYPE REMARKS )];

    sub table_info ($)
    {
        my $dbh = shift;

        my @tables = $dbh->func("get_avail_tables");

        # Temporary kludge: DBD::Sponge dies if @tables is empty. :-(
        # this no longer seems to be true @tables or return;

        my $dbh2 = $dbh->func("sql_sponge_driver");
        my $sth = $dbh2->prepare(
                                  "TABLE_INFO",
                                  {
                                     rows => \@tables,
                                     NAME => $names,
                                  }
                                );
        $sth or return $dbh->set_err( $DBI::stderr, $dbh2->errstr );
        $sth->execute or return;
        return $sth;
    }    # table_info
}

sub list_tables ($)
{
    my $dbh = shift;
    my @table_list;

    my @tables = $dbh->func("get_avail_tables") or return;
    foreach my $ref (@tables)
    {
        # rt69260 and rt67223 - the same issue in 2 different queues
        push @table_list, $ref->[2];
    }

    return @table_list;
}    # list_tables

sub quote ($$;$)
{
    my ( $self, $str, $type ) = @_;
    defined $str or return "NULL";
    defined $type && (    $type == DBI::SQL_NUMERIC()
                       || $type == DBI::SQL_DECIMAL()
                       || $type == DBI::SQL_INTEGER()
                       || $type == DBI::SQL_SMALLINT()
                       || $type == DBI::SQL_FLOAT()
                       || $type == DBI::SQL_REAL()
                       || $type == DBI::SQL_DOUBLE()
                       || $type == DBI::SQL_TINYINT() )
      and return $str;

    $str =~ s/\\/\\\\/sg;
    $str =~ s/\0/\\0/sg;
    $str =~ s/\'/\\\'/sg;
    $str =~ s/\n/\\n/sg;
    $str =~ s/\r/\\r/sg;
    return "'$str'";
}    # quote

sub commit ($)
{
    my $dbh = shift;
    $dbh->FETCH("Warn")
      and carp "Commit ineffective while AutoCommit is on", -1;
    return 1;
}    # commit

sub rollback ($)
{
    my $dbh = shift;
    $dbh->FETCH("Warn")
      and carp "Rollback ineffective while AutoCommit is on", -1;
    return 0;
}    # rollback


package DBI::DBD::SqlEngine::TieMeta;

use Carp qw(croak);
require Tie::Hash;
@DBI::DBD::SqlEngine::TieMeta::ISA = qw(Tie::Hash);

sub TIEHASH
{
    my ( $class, $tblClass, $tblMeta ) = @_;

    my $self = bless(
                      {
                         tblClass => $tblClass,
                         tblMeta  => $tblMeta,
                      },
                      $class
                    );
    return $self;
}    # new

sub STORE
{
    my ( $self, $meta_attr, $meta_val ) = @_;

    $self->{tblClass}->set_table_meta_attr( $self->{tblMeta}, $meta_attr, $meta_val );

    return;
}    # STORE

sub FETCH
{
    my ( $self, $meta_attr ) = @_;

    return $self->{tblClass}->get_table_meta_attr( $self->{tblMeta}, $meta_attr );
}    # FETCH

sub FIRSTKEY
{
    my $a = scalar keys %{ $_[0]->{tblMeta} };
    each %{ $_[0]->{tblMeta} };
}    # FIRSTKEY

sub NEXTKEY
{
    each %{ $_[0]->{tblMeta} };
}    # NEXTKEY

sub EXISTS
{
    exists $_[0]->{tblMeta}{ $_[1] };
}    # EXISTS

sub DELETE
{
    croak "Can't delete single attributes from table meta structure";
}    # DELETE

sub CLEAR
{
    %{ $_[0]->{tblMeta} } = ();
}    # CLEAR

sub SCALAR
{
    scalar %{ $_[0]->{tblMeta} };
}    # SCALAR


package DBI::DBD::SqlEngine::TieTables;

use Carp qw(croak);
require Tie::Hash;
@DBI::DBD::SqlEngine::TieTables::ISA = qw(Tie::Hash);

sub TIEHASH
{
    my ( $class, $dbh ) = @_;

    ( my $tbl_class = $dbh->{ImplementorClass} ) =~ s/::db$/::Table/;
    my $self = bless(
                      {
                         dbh      => $dbh,
                         tblClass => $tbl_class,
                      },
                      $class
                    );
    return $self;
}    # new

sub STORE
{
    my ( $self, $table, $tbl_meta ) = @_;

    "HASH" eq ref $tbl_meta
      or croak "Invalid data for storing as table meta data (must be hash)";

    ( undef, my $meta ) = $self->{tblClass}->get_table_meta( $self->{dbh}, $table, 1 );
    $meta or croak "Invalid table name '$table'";

    while ( my ( $meta_attr, $meta_val ) = each %$tbl_meta )
    {
        $self->{tblClass}->set_table_meta_attr( $meta, $meta_attr, $meta_val );
    }

    return;
}    # STORE

sub FETCH
{
    my ( $self, $table ) = @_;

    ( undef, my $meta ) = $self->{tblClass}->get_table_meta( $self->{dbh}, $table, 1 );
    $meta or croak "Invalid table name '$table'";

    my %h;
    tie %h, "DBI::DBD::SqlEngine::TieMeta", $self->{tblClass}, $meta;

    return \%h;
}    # FETCH

sub FIRSTKEY
{
    my $a = scalar keys %{ $_[0]->{dbh}->{sql_meta} };
    each %{ $_[0]->{dbh}->{sql_meta} };
}    # FIRSTKEY

sub NEXTKEY
{
    each %{ $_[0]->{dbh}->{sql_meta} };
}    # NEXTKEY

sub EXISTS
{
    exists $_[0]->{dbh}->{sql_meta}->{ $_[1] }
      or exists $_[0]->{dbh}->{sql_meta_map}->{ $_[1] };
}    # EXISTS

sub DELETE
{
    my ( $self, $table ) = @_;

    ( undef, my $meta ) = $self->{tblClass}->get_table_meta( $self->{dbh}, $table, 1 );
    $meta or croak "Invalid table name '$table'";

    delete $_[0]->{dbh}->{sql_meta}->{ $meta->{table_name} };
}    # DELETE

sub CLEAR
{
    %{ $_[0]->{dbh}->{sql_meta} }     = ();
    %{ $_[0]->{dbh}->{sql_meta_map} } = ();
}    # CLEAR

sub SCALAR
{
    scalar %{ $_[0]->{dbh}->{sql_meta} };
}    # SCALAR


package DBI::DBD::SqlEngine::st;

use strict;
use warnings;

use vars qw(@ISA $imp_data_size);

$imp_data_size = 0;

sub bind_param ($$$;$)
{
    my ( $sth, $pNum, $val, $attr ) = @_;
    if ( $attr && defined $val )
    {
        my $type = ref $attr eq "HASH" ? $attr->{TYPE} : $attr;
        if (    $type == DBI::SQL_BIGINT()
             || $type == DBI::SQL_INTEGER()
             || $type == DBI::SQL_SMALLINT()
             || $type == DBI::SQL_TINYINT() )
        {
            $val += 0;
        }
        elsif (    $type == DBI::SQL_DECIMAL()
                || $type == DBI::SQL_DOUBLE()
                || $type == DBI::SQL_FLOAT()
                || $type == DBI::SQL_NUMERIC()
                || $type == DBI::SQL_REAL() )
        {
            $val += 0.;
        }
        else
        {
            $val = "$val";
        }
    }
    $sth->{sql_params}[ $pNum - 1 ] = $val;
    return 1;
}    # bind_param

sub execute
{
    my $sth = shift;
    my $params = @_ ? ( $sth->{sql_params} = [@_] ) : $sth->{sql_params};

    $sth->finish;
    my $stmt = $sth->{sql_stmt};

    # must not proved when already executed - SQL::Statement modifies
    # received params
    unless ( $sth->{sql_params_checked}++ )
    {
        # SQL::Statement and DBI::SQL::Nano will return the list of required params
        # when called in list context. Do not look into the several items, they're
        # implementation specific and may change without warning
        unless ( ( my $req_prm = $stmt->params() ) == ( my $nparm = @$params ) )
        {
            my $msg = "You passed $nparm parameters where $req_prm required";
            return $sth->set_err( $DBI::stderr, $msg );
        }
    }

    my @err;
    my $result;
    eval {
        local $SIG{__WARN__} = sub { push @err, @_ };
        $result = $stmt->execute( $sth, $params );
    };
    unless ( defined $result )
    {
        $sth->set_err( $DBI::stderr, $@ || $stmt->{errstr} || $err[0] );
        return;
    }

    if ( $stmt->{NUM_OF_FIELDS} )
    {    # is a SELECT statement
        $sth->STORE( Active => 1 );
        $sth->FETCH("NUM_OF_FIELDS")
          or $sth->STORE( "NUM_OF_FIELDS", $stmt->{NUM_OF_FIELDS} );
    }
    return $result;
}    # execute

sub finish
{
    my $sth = $_[0];
    $sth->SUPER::STORE( Active => 0 );
    delete $sth->{sql_stmt}{data};
    return 1;
}    # finish

sub fetch ($)
{
    my $sth  = $_[0];
    my $data = $sth->{sql_stmt}{data};
    if ( !$data || ref $data ne "ARRAY" )
    {
        $sth->set_err(
            $DBI::stderr,
            "Attempt to fetch row without a preceding execute () call or from a non-SELECT statement"
        );
        return;
    }
    my $dav = shift @$data;
    unless ($dav)
    {
        $sth->finish;
        return;
    }
    if ( $sth->FETCH("ChopBlanks") )    # XXX: (TODO) Only chop on CHAR fields,
    {                                   # not on VARCHAR or NUMERIC (see DBI docs)
        $_ && $_ =~ s/ +$// for @$dav;
    }
    return $sth->_set_fbav($dav);
}    # fetch

no warnings 'once';
*fetchrow_arrayref = \&fetch;

use warnings;

sub sql_get_colnames
{
    my $sth = $_[0];
    # Being a bit dirty here, as neither SQL::Statement::Structure nor
    # DBI::SQL::Nano::Statement_ does not offer an interface to the
    # required data
    my @colnames;
    if ( $sth->{sql_stmt}->{NAME} and "ARRAY" eq ref( $sth->{sql_stmt}->{NAME} ) )
    {
        @colnames = @{ $sth->{sql_stmt}->{NAME} };
    }
    elsif ( $sth->{sql_stmt}->isa('SQL::Statement') )
    {
        my $stmt = $sth->{sql_stmt} || {};
        my @coldefs = @{ $stmt->{column_defs} || [] };
        @colnames = map { $_->{name} || $_->{value} } @coldefs;
    }
    @colnames = $sth->{sql_stmt}->column_names() unless (@colnames);

    @colnames = () if ( grep { m/\*/ } @colnames );

    return @colnames;
}

sub FETCH ($$)
{
    my ( $sth, $attrib ) = @_;

    $attrib eq "NAME" and return [ $sth->sql_get_colnames() ];

    $attrib eq "TYPE"      and return [ ( DBI::SQL_VARCHAR() ) x scalar $sth->sql_get_colnames() ];
    $attrib eq "TYPE_NAME" and return [ ("VARCHAR") x scalar $sth->sql_get_colnames() ];
    $attrib eq "PRECISION" and return [ (0) x scalar $sth->sql_get_colnames() ];
    $attrib eq "NULLABLE"  and return [ (1) x scalar $sth->sql_get_colnames() ];

    if ( $attrib eq lc $attrib )
    {
        # Private driver attributes are lower cased
        return $sth->{$attrib};
    }

    # else pass up to DBI to handle
    return $sth->SUPER::FETCH($attrib);
}    # FETCH

sub STORE ($$$)
{
    my ( $sth, $attrib, $value ) = @_;
    if ( $attrib eq lc $attrib )    # Private driver attributes are lower cased
    {
        $sth->{$attrib} = $value;
        return 1;
    }
    return $sth->SUPER::STORE( $attrib, $value );
}    # STORE

sub DESTROY ($)
{
    my $sth = shift;
    $sth->SUPER::FETCH("Active") and $sth->finish;
    undef $sth->{sql_stmt};
    undef $sth->{sql_params};
}    # DESTROY

sub rows ($)
{
    return $_[0]->{sql_stmt}{NUM_OF_ROWS};
}    # rows


package DBI::DBD::SqlEngine::TableSource;

use strict;
use warnings;

use Carp;

sub data_sources ($;$)
{
    my ( $class, $drh, $attrs ) = @_;
    croak( ( ref( $_[0] ) ? ref( $_[0] ) : $_[0] ) . " must implement data_sources" );
}

sub avail_tables
{
    my ( $self, $dbh ) = @_;
    croak( ( ref( $_[0] ) ? ref( $_[0] ) : $_[0] ) . " must implement avail_tables" );
}


package DBI::DBD::SqlEngine::DataSource;

use strict;
use warnings;

use Carp;

sub complete_table_name ($$;$)
{
    my ( $self, $meta, $table, $respect_case ) = @_;
    croak( ( ref( $_[0] ) ? ref( $_[0] ) : $_[0] ) . " must implement complete_table_name" );
}

sub open_data ($)
{
    my ( $self, $meta, $attrs, $flags ) = @_;
    croak( ( ref( $_[0] ) ? ref( $_[0] ) : $_[0] ) . " must implement open_data" );
}


package DBI::DBD::SqlEngine::Statement;

use strict;
use warnings;

use Carp;

@DBI::DBD::SqlEngine::Statement::ISA = qw(DBI::SQL::Nano::Statement);

sub open_table ($$$$$)
{
    my ( $self, $data, $table, $createMode, $lockMode ) = @_;

    my $class = ref $self;
    $class =~ s/::Statement/::Table/;

    my $flags = {
                  createMode => $createMode,
                  lockMode   => $lockMode,
                };
    $self->{command} eq "DROP" and $flags->{dropMode} = 1;

    # because column name mapping is initialized in constructor ...
    # and therefore specific opening operations might be done before
    # reaching DBI::DBD::SqlEngine::Table->new(), we need to intercept
    # ReadOnly here
    my $write_op = $createMode || $lockMode || $flags->{dropMode};
    if ($write_op)
    {
        my ( $tblnm, $table_meta ) = $class->get_table_meta( $data->{Database}, $table, 1 )
          or croak "Cannot find appropriate file for table '$table'";
        $table_meta->{readonly}
          and croak "Table '$table' is marked readonly - "
          . $self->{command}
          . ( $lockMode ? " with locking" : "" )
          . " command forbidden";
    }

    return $class->new( $data, { table => $table }, $flags );
}    # open_table


package DBI::DBD::SqlEngine::Table;

use strict;
use warnings;

use Carp;

@DBI::DBD::SqlEngine::Table::ISA = qw(DBI::SQL::Nano::Table);

sub bootstrap_table_meta
{
    my ( $self, $dbh, $meta, $table ) = @_;

    defined $dbh->{ReadOnly}
      and !defined( $meta->{readonly} )
      and $meta->{readonly} = $dbh->{ReadOnly};
    defined $meta->{sql_identifier_case}
      or $meta->{sql_identifier_case} = $dbh->{sql_identifier_case};

    exists $meta->{sql_data_source} or $meta->{sql_data_source} = $dbh->{sql_data_source};

    $meta;
}

sub init_table_meta
{
    my ( $self, $dbh, $meta, $table ) = @_ if (0);

    return;
}    # init_table_meta

sub get_table_meta ($$$;$)
{
    my ( $self, $dbh, $table, $respect_case, @other ) = @_;
    unless ( defined $respect_case )
    {
        $respect_case = 0;
        $table =~ s/^\"// and $respect_case = 1;    # handle quoted identifiers
        $table =~ s/\"$//;
    }

    unless ($respect_case)
    {
        defined $dbh->{sql_meta_map}{$table} and $table = $dbh->{sql_meta_map}{$table};
    }

    my $meta = {};
    defined $dbh->{sql_meta}{$table} and $meta = $dbh->{sql_meta}{$table};

  do_initialize:
    unless ( $meta->{initialized} )
    {
        $self->bootstrap_table_meta( $dbh, $meta, $table, @other );
        $meta->{sql_data_source}->complete_table_name( $meta, $table, $respect_case, @other )
          or return;

        if ( defined $meta->{table_name} and $table ne $meta->{table_name} )
        {
            $dbh->{sql_meta_map}{$table} = $meta->{table_name};
            $table = $meta->{table_name};
        }

        # now we know a bit more - let's check if user can't use consequent spelling
        # XXX add know issue about reset sql_identifier_case here ...
        if ( defined $dbh->{sql_meta}{$table} )
        {
            $meta = delete $dbh->{sql_meta}{$table};    # avoid endless loop
            $meta->{initialized}
              or goto do_initialize;
            #or $meta->{sql_data_source}->complete_table_name( $meta, $table, $respect_case, @other )
            #or return;
        }

        unless ( $dbh->{sql_meta}{$table}{initialized} )
        {
            $self->init_table_meta( $dbh, $meta, $table );
            $meta->{initialized} = 1;
            $dbh->{sql_meta}{$table} = $meta;
        }
    }

    return ( $table, $meta );
}    # get_table_meta

my %reset_on_modify = ();
my %compat_map      = ();

sub register_reset_on_modify
{
    my ( $proto, $extra_resets ) = @_;
    foreach my $cv ( keys %$extra_resets )
    {
        #%reset_on_modify = ( %reset_on_modify, %$extra_resets );
        push @{ $reset_on_modify{$cv} },
          ref $extra_resets->{$cv} ? @{ $extra_resets->{$cv} } : ( $extra_resets->{$cv} );
    }
    return;
}    # register_reset_on_modify

sub register_compat_map
{
    my ( $proto, $extra_compat_map ) = @_;
    %compat_map = ( %compat_map, %$extra_compat_map );
    return;
}    # register_compat_map

sub get_table_meta_attr
{
    my ( $class, $meta, $attrib ) = @_;
    exists $compat_map{$attrib}
      and $attrib = $compat_map{$attrib};
    exists $meta->{$attrib}
      and return $meta->{$attrib};
    return;
}    # get_table_meta_attr

sub set_table_meta_attr
{
    my ( $class, $meta, $attrib, $value ) = @_;
    exists $compat_map{$attrib}
      and $attrib = $compat_map{$attrib};
    $class->table_meta_attr_changed( $meta, $attrib, $value );
    $meta->{$attrib} = $value;
}    # set_table_meta_attr

sub table_meta_attr_changed
{
    my ( $class, $meta, $attrib, $value ) = @_;
    defined $reset_on_modify{$attrib}
      and delete @$meta{ @{ $reset_on_modify{$attrib} } }
      and $meta->{initialized} = 0;
}    # table_meta_attr_changed

sub open_data
{
    my ( $self, $meta, $attrs, $flags ) = @_;

    $meta->{sql_data_source}
      or croak "Table " . $meta->{table_name} . " not completely initialized";
    $meta->{sql_data_source}->open_data( $meta, $attrs, $flags );

    return;
}    # open_data


sub new
{
    my ( $className, $data, $attrs, $flags ) = @_;
    my $dbh = $data->{Database};

    my ( $tblnm, $meta ) = $className->get_table_meta( $dbh, $attrs->{table}, 1 )
      or croak "Cannot find appropriate table '$attrs->{table}'";
    $attrs->{table} = $tblnm;

    # Being a bit dirty here, as SQL::Statement::Structure does not offer
    # me an interface to the data I want
    $flags->{createMode} && $data->{sql_stmt}{table_defs}
      and $meta->{table_defs} = $data->{sql_stmt}{table_defs};

    # open_file must be called before inherited new is invoked
    # because column name mapping is initialized in constructor ...
    $className->open_data( $meta, $attrs, $flags );

    my $tbl = {
                %{$attrs},
                meta      => $meta,
                col_names => $meta->{col_names} || [],
              };
    return $className->SUPER::new($tbl);
}    # new

1;

