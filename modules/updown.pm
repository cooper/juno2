#!/usr/bin/perl
# Copyright (c) 2011, Mitchell Cooper

# module for /up and /down
# this module grants or remove's a user's status
# according to channel mode A.
# this module probably works with 0.9.5 and up

package module::updown;

use warnings;
use strict;

use API::Module 'register_module';
use API::Command 'register_command';
use utils 'conf';

# register the module
register_module('updown', '0.0.1', 'Grant or remove a user\'s channel access according to mode A.', \&init, sub {});

sub init {
    # register the commands
    register_command('up', 'Gain channel privileges according to mode A', \&up);
    register_command('down', 'Remove all channel privileges', \&down);
    return 1
}

sub up {
    my ($user, @args) = (shift, (split /\s+/, shift));

    # parameter check
    if (!defined $args[1]) {
        $user->numeric(461, 'UP');
        return
    }

    my $channel = channel::chanexists($args[1]);

    # make sure the channel exists
    if (!$channel) {
        $user->numeric(401, $args[1]);
        return
    }

    # make sure they're there
    if (!$user->ison($channel)) {
        $user->numeric(422, $channel->name);
        return
    }

    $channel->doauto($user);

    # success
    return 1
}

sub down {
    my ($user, @args) = (shift, (split /\s+/, shift));

    # parameter check
    if (!defined $args[1]) {
        $user->numeric(461, 'DOWN');
        return
    }

    my $channel = channel::chanexists($args[1]);

    # make sure the channel exists
    if (!$channel) {
        $user->numeric(401, $args[1]);
        return
    }

    my @final_modes;

    # check for owner
    push @final_modes, 'q' and
    delete $channel->{'owners'}->{$user->{'id'}}
    if $channel->has($user, 'owner');

    # check for admin
    push @final_modes, 'a' and
    delete $channel->{'admins'}->{$user->{'id'}}
    if $channel->has($user, 'admin');

    # check for op
    push @final_modes, 'o' and
    delete $channel->{'ops'}->{$user->{'id'}}
    if $channel->has($user, 'op');

    # check for halfop
    push @final_modes, 'h' and
    delete $channel->{'halfops'}->{$user->{'id'}}
    if $channel->has($user, 'halfop');

    # check for voice
    push @final_modes, 'v' and
    delete $channel->{'voices'}->{$user->{'id'}}
    if $channel->has($user, 'voice');

    my @final_parameters;
    push @final_parameters, $user->nick for 0..$#final_modes;

    # send the mode string if anything was done
    $channel->allsend(':%s MODE %s -%s %s', 0,
        conf('server', 'name'),
        $channel->name,
        (join q.., @final_modes),
        (join q. ., @final_parameters)
    ) if scalar @final_modes;

    # success
    return 1
}

1
