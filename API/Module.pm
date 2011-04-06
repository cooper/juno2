#!/usr/bin/perl -w
# Copyright (c) 2011, Mitchell Cooper
package API::Module;

use warnings;
use strict;
use feature 'say';
use base 'Exporter';

use Exporter;
use Class::Unload;

use API::Command;

our @EXPORT = qw/register_module module_exists/;
our %MODULE;
our $LAST_INIT;

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
        say 'Incorrect number of parameters for register_module; aborting register.';
        return
    }

    # make sure that they aren't attempting to register from main
    if ($package eq 'main') {
        say 'Modules must have unique package names; main is not acceptable. Aborting register.';
        return
    }

    my %module = ();
    $module{$_} = shift foreach qw/name version desc init void/;

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
    say 'Unloading package '.$package.' by force';

    # make sure it exists
    if (exists $MODULE{$package}) {

        # delete any commands registered
        API::Command::delete_package($package);

        # delete the module
        delete $MODULE{$package};

        # unload the package (supposedly)
        Class::Unload->unload($package);

        say 'Unloaded package '.$package;
        return 1
    }

    # it hasn't registered, so give up
    else {
        say 'I can\'t unload a module that hasn\'t registered. ('.$package.')';
        return
    }

    return
}

sub package_init {
    my $package = shift;
    $LAST_INIT = $package;

    # make sure the module is registered
    if (!exists $MODULE{$package}) {
        say 'Package '.$package.' has not registered to API::Module; aborting initialization.';
        return
    }

    # make sure it's a coderef
    if (ref $MODULE{$package}{'init'} eq 'CODE') {
        say 'Initializing module '.$MODULE{$package}{'name'};
        # it is, so run it
        if ($MODULE{$package}{'init'}(caller 0)) {
            # it returned true
            say 'Module initialized successfully.';
            return 1
        } else {
            # it failed
            say 'Module refused to load; aborting.';
            delete_package($package);
            return
        }
    } else {
        # it's not a coderef, so force the package to unload
        say 'Module '.$MODULE{$package}{'name'}.' did not provide a init CODE ref; forcing unload.';
        delete_package($package);
        return
    }

    # success
    return 1
}

sub package_exists {
    my $package = shift;
    return $MODULE{$package} if exists $MODULE{$package};
    return
}

1
