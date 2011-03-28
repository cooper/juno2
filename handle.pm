#!/usr/bin/perl -w
# Copyright (c) 2011, Mitchell Cooper
package handle;

use warnings;
use strict;
use feature 'switch';

use utils qw/col validnick conf/;

sub user {
    my $user = user::lookup(shift) or return;
    my $data = shift;
    foreach my $line (split "\n", $data) {

        # strip characters that might interfere later
        $line =~ s/(\0|\r|\n)//g;
        my @s = split / /, $line;

        # ignore empty lines
        next unless length $line;

        # reset idle times, ping times, etc.
        user_reset_timer($user, $s[0]);

        if ($user->{'ready'}) {
            $user->handle($s[0], $line);
            next
        }
        given (lc $s[0]) {
            when ('nick') {
                user_handle_nick($user, @s)
            } when('user') {
                user_handle_user($user, $line, @s)
            } default {
                $user->numeric(421, uc $s[0]) if lc $s[0] !~ m/^(PONG|PING|CAP)$/
            }
        }
    }
    return 1
}

sub user_handle_user {
    my ($user, $data, @s) = @_;
    if (!defined $s[4]) {
        $user->numeric(461, 'USER');
        return
    }
    if (validnick($s[1], conf('limit', 'ident'), 1)) {
        $user->{'gecos'} = col((split / /, $data, 5)[4]);
        $user->{'ident'} = '~'.$s[1];
        user_start($user) if exists $user->{'nick'};
        return 1
    }
}

sub user_handle_nick {
    my ($user, @s) = @_;
    if (!defined $s[1]) {
        $user->numeric(461, 'NICK');
        return
    }
    if (validnick($s[1], conf('limit', 'nick'), undef)) {
        if (!user::nickexists($s[1])) {
            $user->{'nick'} = $s[1];
            user_start($user) if exists $user->{'ident'};
            return 1
        } else {
            $user->numeric(433, $s[1])
        }
    } else {
        $user->numeric(432, $s[1])
    }
}

sub user_reset_timer {
    my ($user, $command) = @_;
    $user->{'idle'} = time if $command !~ m/^(ping|pong)$/i;
    $user->{'last'} = time;
    $user->{'ping'} = time;
    return 1
}

sub user_start {
    my $user = shift;
    $user->{'ready'} = 1;
    $user->start
}

1
