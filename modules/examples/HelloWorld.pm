#!/usr/bin/perl
# Copyright (c) 2011, Mitchell Cooper

# all modules must have a unique package name
package module::HelloWorld;

use warnings;
use strict;
use feature 'say';

# all modules must use API::Module
use API::Module 'register_module';
use API::Command 'register_command';

# register the module to API::Module
# all modules *MUST* do this.
# parameters are as follows:
#   module name
#   module version
#   description
#   init coderef
#   void coderef
register_module('HelloWorld', 0.1, 'Hello world!', \&init, \&void);

sub init {
    # this will be called my API::Module upon loading of the module

    # register the HELLO command.
    # parameters for register_command are command_name and a coderef.

    register_command('hello', 'Hello world!', sub {
        # register_command provides the user who sent the data
        # and the value of the data.
        my ($user, $data) = @_;

        # send them a notice
        $user->servernotice('Hello world!');

        # it's probably a good idea to return true with these too,
        # to satisfy user.pm
        return 1
    });

    # success!
    # all modules must return a true value to tell API::Module that it
    # was loaded successfully, otherwise it will be forced to unload.
    return 1
}

sub void {
    # this will be called my API::Module upon unloading of the module.

    # Unlike in the old API, you no longer have to delete commands and
    # other things that were registered in init(). It's done automatically
    # by API::Module now.

    say 'Goodbye world!';

    # once again, the module will not unload unless this subroutine returns
    # a true value. If in any case a module should not be unloaded, return
    # a false value here, and API::Module will consider it to be permanent
    # and ignore the attempt to unload it.
    return 1
}

# all packages must be true
1
