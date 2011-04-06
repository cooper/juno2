#!/usr/bin/perl -w
# Copyright (c) 2011, Mitchell Cooper
package handle;

use warnings;
use strict;
use feature 'switch';

use utils qw/col validnick conf/;

# handle data from a user
sub user {

    # find the user
    my $user = user::lookup(shift)

    # *SOMETIMES* (very seldomly), nonexistent users' data runs through here.
    # this happens when a user disconnects just milliseconds after the handler is called.
    # we gotta double check, just in case.
    or return;

    my $data = shift;
    foreach my $line (split "\n", $data) {

        # strip characters that might interfere later
        $line =~ s/(\0|\r|\n)//g;
        my @s = split /\s+/, $line;

        # ignore empty lines
        next unless length $line;

        # reset idle times, ping times, etc.
        user_reset_timer($user, $s[0]);

        # if the user is registered, throw the data at the user package to handle it.
        if ($user->{'ready'}) {
            $user->handle($s[0], $line);
            next
        }

        given (lc $s[0]) {
            when ('nick') {
                user_handle_nick($user, @s)
            } when('user') {
                user_handle_user($user, $line, @s)
            }

            # unknown command
            default {
                $user->numeric(421, uc $s[0])

                # ignore pings, pongs, and CAP
                unless lc $s[0] != m/^(PONG|PING|CAP)$/

            }
        }
    }
    return 1
}

# handle USER command
sub user_handle_user {
    my ($user, $data, @s) = @_;

    # parameter check
    if (!defined $s[4]) {
        $user->numeric(461, 'USER');
        return
    }

    # if it's valid, ok
    if (validnick($s[1], conf('limit', 'ident'), 1)) {
        $user->{'gecos'} = col((split / /, $data, 5)[4]);
        $user->{'ident'} = '~'.$s[1];
        user_start($user) if exists $user->{'nick'};
        return 1
    }

    # invalid
    $user->numeric(461.1);
    return

}

# handle NICK command
sub user_handle_nick {
    my ($user, @s) = @_;

    # parameter check
    if (!defined $s[1]) {
        $user->numeric(461, 'NICK');
        return
    }

    # make sure the nick is valid
    if (validnick($s[1], conf('limit', 'nick'), undef)) {

        # check if the nickname is in use by someone else
        if (!user::nickexists($s[1])) {
            $user->{'nick'} = $s[1];
            user_start($user) if exists $user->{'ident'};
            return 1
        }

        # nick taken
        else {
            $user->numeric(433, $s[1]);
            return
        }

    }

    # invalid nick
    $user->numeric(432, $s[1]);
    return

}


# reset PING, idle, and last response timers
sub user_reset_timer {
    my ($user, $command) = @_;
    $user->{'idle'} = time

    # if they're sending a PING or PONG, don't reset their idle time
    if $command !~ m/^(ping|pong)$/i;

    $user->{'last'} = time;
    $user->{'ping'} = time;
    return 1
}

# tell user package that the user is ready and send connect numberics
sub user_start {
    my $user = shift;
    $user->{'ready'} = 1;
    $user->start
}

1
