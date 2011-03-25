#!/usr/bin/perl -w
# Copyright (c) 2011, Mitchell Cooper
package API::Module;

use warnings;
use strict;
use feature qw/say switch/;

use Exporter;
use Class::Unload;

our @EXPORT = qw/register_module module_exists/;
our %MODULE;

# functions that can be imported

sub register_module {
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
    $module{$_} = shift foreach qw(name version desc init void);

    # I was gonna make it check if a module with the same name already exists, but that's kinda
    # pointless because it uses package names; there shouldn't be any issues.

    say 'API module registered: '.$module{'name'}.' from '.$package;
    $MODULE{$package} = \%module;

    # success
    return package_init($package)
}

sub module_exists {
    # by module name, not package name

    my $name = shift;
    foreach (keys %MODULE) {
        return 1 if $MODULE{$_}{'name'} eq $name
    }
    return
}

# internal API functions

sub delete_package {
    # by package name, not module name

    my $package = shift;
    if (exists $MODULE{$package}) {

        # delete the module
        delete $MODULE{$package};

        # unload the package (supposedly)
        Class::Unload->unload($package);

        say 'Unloaded package '.$package;
        return 1
    } else {
        say 'I can\'t unload a module that hasn\'t registered. ('.$package.')';
        return
    }
}

sub package_init {
    my $package = shift;
    if (!exists $MODULE{$package}) {
        say 'Package '.$package.' has not registered to API::Module; aborting initialization.';
        return
    }
    if (ref $MODULE{$package}{'init'} eq 'CODE') {
        say 'Initializing module '.$MODULE{$package};
        $MODULE{$package}{'init'}(caller 0);
    } else {
        say 'Module '.$MODULE{$package}{'name'}.' did not provide a init CODE ref; forcing unload.';
        delete_package($package);
        return
    }
    return 1
}

1
