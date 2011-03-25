#!/usr/bin/perl -w
package API::Module;

use warnings;
use strict;
use feature qw/say switch/;

our %MODULE;

sub register {

    # parameters: module_name module_version module_description initiate_code void_code
    my $package = caller 0;

    # make sure that this module hasn't already registered itself.
    if (exists $MODULE{$package}) {
        say 'Package '.$package.' attempted to register multiple modules; aborting register.';
        return
    }

    # make sure they have all of the required parameters
    if ($#_ < 4) {
        say 'Incorrect number of parameters for API::Module::register; aborting register.';
        return
    }

    # make sure that they aren't attempting to register from main
    if ($package eq 'main') {
        say 'Modules must have unique package names; main is not acceptable. Aborting register.';
        return
    }

    my %module = ();
    $module{$_} = shift foreach ('name','version','desc','init','void');

    # I was gonna make it check if a module with the same name already exists, but that's kinda
    # pointless because it uses package names; there shouldn't be any issues.

    say 'API module registered: '.$module{'name'}.' from '.$package;
    $MODULE{$package} = \%module;

    # success
    return 1

}

1
