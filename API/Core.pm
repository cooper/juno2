#!/usr/bin/perl
# Copyright (c) 2011, Mitchell Cooper
package API::Core;

use warnings;
use strict;
use feature 'say';

use API::Module qw/register_module module2package module_exists/;
use API::Command;
use API::Event;
use utils qw/fatal conf snotice/;

# called by main if API is enabled
sub begin {

    # make sure main is calling
    return unless (caller)[0] eq 'main';

    say 'Loading API modules';

    # make sure it's not set to 0 (none)
    if (my $modules = conf qw/main modules/) {

        # modules are separated by spaces
        foreach my $module (split /\s+/, $modules) {

            # load it
            say 'Loading module '.$module;
            $module = "modules/$module.pm";
            do $module

            # or die due to an error
            or fatal("Can't load $module: ".($! ? $! : $@))

        }
    }

    # success
    return 1

}

# API::Core registers itself to API::Module in order to add core commands.
register_module('API', 0.5, 'juno-ircd module interface', \&init, sub { return }) or fatal('Module API refused to load.');

# initialization of this module
sub init {

    # register the two core commands
    register_command('modload', 'Load an API module.', \&handle_modload) or return;
    register_command('modunload', 'Unload an API module.', \&handle_modunload) or return;

    return 1
}

# MODLOAD handler
sub handle_modload {
    my ($user, @args) = (shift, (split /\s+/, shift));

    # parameter check
    if (!defined $args[1]) {
        $user->numeric(461, 'MODLOAD');
        return
    }

    # must have modload flag
    if (!$user->can('modload') || $user->can('modules')) {
        $user->numeric(481);
        return
    }

    my $file = $args[1];
    snotice($user->nick.' is loading API module '.$file);
    say 'Loading module '.$file;
    $file = "modules/$file.pm";

    # attempt to do() it.
    unless (do $file) {
        my $string = "couldn't parse $file: ".($@ ? $@ : ($! ? $! : 'unknown error'));
        $user->snt('modload', $string);
        snotice($string);
        return
    }

    # success
    $user->snt('modload', 'module has been parsed with no error.');
    return 1

}

# MODUNLOAD handler
sub handle_modunload {
        my ($user, @args) = (shift, (split /\s+/, shift));

    # parameter check
    if (!defined $args[1]) {
        $user->numeric(461, 'MODUNLOAD');
        return
    }

    # must have modload flag
    if (!$user->can('modload') || $user->can('modules')) {
        $user->numeric(481);
        return
    }

    my $module = $args[1];

    # does it exist?
    if (module_exists($module)) {
        my $package = module2package($module);
        snotice("$$user{nick} is unloading $module [$package]");
        $user->snt('modunload', 'unloading package '.$package);
        return API::Module::package_unload($package)
    }

    # no such module
    else {
        $user->snt('modunload', 'no such module');
        return
    }

}

1
