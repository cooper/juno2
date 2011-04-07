#!/usr/bin/perl
# Copyright (c) 2011, Mitchell Cooper

# this module provides SYNC command - a simple way to grant users' access
# all at once as set by channel mode A.

package module::sync;

use warnings;
use strict;

use API::Module 'register_module';
use API::Command 'register_command';

# register the module
register_module('sync', 0.1, 'Sync channel access modes to the auto-access list.', \&init, sub {});

# initialization subroutine
sub init {

    # register the SYNC command
    register_command('sync', 'Sync channel access modes to the auto-access list.', \&sync) or return;

    return 1
}

# handle the SYNC command
sub sync {
    my ($user, @args) = (shift, (split /\s+/, shift));

    # parameter check
    if (!defined $args[1]) {
        $user->numeric(461, 'SYNC');
        return
    }

    my $channel = channel::chanexists($args[1]);

    # make sure the channel exists
    if (!$channel) {
        $user->numeric(401, $args[1]);
        return
    }

    # check for privs
    if ($channel->has($user, 'owner')) {

        # check each user for access
        $channel->doauto(user::lookupbyid($_)) foreach keys %{$channel->{users}};

        return 1
    }

    # permission denied
    else {
        $user->numeric(482, $channel->name, 'owner')
    }

    return
}

1
