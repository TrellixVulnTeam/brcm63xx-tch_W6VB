package Locale::Codes::Language;

use strict;
require 5.006;
use warnings;

require Exporter;
use Carp;
use Locale::Codes;
use Locale::Codes::Constants;
use Locale::Codes::Language_Codes;
use Locale::Codes::Language_Retired;


our($VERSION,@ISA,@EXPORT,@EXPORT_OK);

$VERSION='3.30';
@ISA       = qw(Exporter);
@EXPORT    = qw(code2language
                language2code
                all_language_codes
                all_language_names
                language_code2code
                LOCALE_LANG_ALPHA_2
                LOCALE_LANG_ALPHA_3
                LOCALE_LANG_TERM
               );

sub code2language {
   return Locale::Codes::_code2name('language',@_);
}

sub language2code {
   return Locale::Codes::_name2code('language',@_);
}

sub language_code2code {
   return Locale::Codes::_code2code('language',@_);
}

sub all_language_codes {
   return Locale::Codes::_all_codes('language',@_);
}

sub all_language_names {
   return Locale::Codes::_all_names('language',@_);
}

sub rename_language {
   return Locale::Codes::_rename('language',@_);
}

sub add_language {
   return Locale::Codes::_add_code('language',@_);
}

sub delete_language {
   return Locale::Codes::_delete_code('language',@_);
}

sub add_language_alias {
   return Locale::Codes::_add_alias('language',@_);
}

sub delete_language_alias {
   return Locale::Codes::_delete_alias('language',@_);
}

sub rename_language_code {
   return Locale::Codes::_rename_code('language',@_);
}

sub add_language_code_alias {
   return Locale::Codes::_add_code_alias('language',@_);
}

sub delete_language_code_alias {
   return Locale::Codes::_delete_code_alias('language',@_);
}

1;
