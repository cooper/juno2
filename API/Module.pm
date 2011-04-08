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
use utils 'snotice';

our @EXPORT = qw/register_module module_exists module2package/;
our %MODULE;
our $LAST_INIT;

# functions that can be imported

sub register_module {
    # parameters: module_name module_version module_description initiate_code void_code
    my $package = caller 0;

    # make sure that this module hasn't already registered itself.
    if (exists $MODULE{$package}) {
        notice('Package '.$package.' attempted to register multiple modules; aborting register.');
        return
    }

    # make sure they have all of the required parameters
    if ($#_ < 4) {
        notice('Incorrect number of parameters for register_module; aborting register.');
        return
    }

    # make sure that they aren't attempting to register from main
    if ($package eq 'main') {
        notice('Modules must have unique package names; main is not acceptable. Aborting register.');
        return
    }

    my %module = ();
    $module{$_} = shift foreach qw/name version desc init void/;

    # I was gonna make it check if a module with the same name already exists, but that's kinda
    # pointless because it uses package names; there shouldn't be any issues.

    notice('API module registered: '.$module{'name'}.' from '.$package);
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
    notice('Unloading package '.$package.' by force');

    # make sure it exists
    if (exists $MODULE{$package}) {

        # delete any commands registered
        API::Command::delete_package($package);

        # delete the module
        delete $MODULE{$package};

        # unload the package (supposedly)
        Class::Unload->unload($package);

        notice('Unloaded package '.$package);
        return 1
    }

    # it hasn't registered, so give up
    else {
        notice('I can\'t unload a module that hasn\'t registered. ('.$package.')');
        return
    }

    return
}

sub package_init {
    my $package = shift;
    $LAST_INIT = $package;

    # make sure the module is registered
    if (!exists $MODULE{$package}) {
        notice('Package '.$package.' has not registered to API::Module; aborting initialization.');
        return
    }

    # make sure it's a coderef
    if (ref $MODULE{$package}{'init'} eq 'CODE') {
        notice('Initializing module '.$MODULE{$package}{'name'});
        # it is, so run it
        if ($MODULE{$package}{'init'}(caller)) {
            # it returned true
            notice('Module initialized successfully.');
            return 1
        } else {
            # it failed
            notice('Module refused to load; aborting.');
            delete_package($package);
            return
        }
    } else {
        # it's not a coderef, so force the package to unload
        notice('Module '.$MODULE{$package}{'name'}.' did not provide a init CODE ref; forcing unload.');
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

# call void() and unlod
sub package_unload {
    my $package = shift;

    notice('Calling void subroutine for '.$package);

    # make sure it exists
    if (exists $MODULE{$package}) {

        # found it; call void()
        if ($MODULE{$package}{'void'}()) {
            notice('Success.');
            return delete_package($package)
        }

        # it refuses to unload
        else {
            notice($package.' refused to unload.');
            return
        }

    }

    # it hasn't registered, so give up
    else {
        notice('I can\'t unload a module that hasn\'t registered. ('.$package.')');
        return
    }
}

sub module2package {
    my $request = shift;
    foreach my $module (keys %MODULE) {
        return $module if $MODULE{$module}{name} eq $request
    }

    # no such module
    return
}

sub notice {
    my $msg = shift;
    say $msg;
    snotice($msg);
    return 1
}

1
