#!/usr/bin/perl
# Copyright (c) 2011, Mitchell Cooper

# API module with a loop example
# If you are new to the module API, please see the HelloWorld module before this one.
# It explains several expectations of API modules.

package module::loop;

use warnings;
use strict;
use feature 'say';

use API::Module;
use API::Command;
use API::Loop;

# register the module
register_module('loop_example', 0.1, 'Humpty dumpty sat on a wall...', \&init, \&void);

my @humpty = (
    'Humpty Dumpty sat on a wall,',
    'Humpty Dumpty had a great fall.',
    'All the king\'s horses and all the king\'s men',
    'Couldn\'t put Humpty together again.'
);
my %humpty;

# init subroutine
sub init {

    # create the command
    register_command('humpty', 'Humpty dumpty sat on a wall...', \&create_loop) or return;

    # tell API::Module it worked
    return 1
}

# void subroutine
sub void {
    say 'bye Humpty. :(';

    # we don't need to delete any loops or commands here
    # because API::Module handles all of that behind the scenes.

    return 1
}

# this is executed when the humpty command is used
sub create_loop {
    my $user = shift;

    $humpty{$user} = [@humpty];

    # create a loop
    # 1. the name of the loop (must be unique in this module)
    # 2. a coderef or anonymous subroutine
    # it returns the loop ID
    my $loop = register_loop('Humpty dumpty', sub {

        # see if there's more in our array
        if (!scalar @{$humpty{$user}}) {

            # delete the loop
            # the only value in @_ is always the ID of the loop
            # note: we can't use delete_loop in this subroutine
            finish_loop(shift);

            return
        }


        # send them server notices each time the loop is run through
        $user->servernotice(shift @{$humpty{$user}});

    }) or return;

    # tell API::Module it worked
    return 1

}

# delete the loop
# normally, delete_loop would be called from outside of the loop itself.
# but in this case, we want to delete the loop when it is finished.
# that requires that we delete it here, outside of the loop subroutine
# (note that this sub is called from the loop)
sub finish_loop {
    delete_loop(shift)
}

1
