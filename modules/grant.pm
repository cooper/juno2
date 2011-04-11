#!/usr/bin/perl
# Copyright (c) 2011, Mitchell Cooper

# This module adds the GRANT and DEOPER commands.
# It adds two oper flags - grant and deoper.

# GRANT parameters: <nick> <priv> [<priv>] [...]
# DEOPER parameters: <nick>

# NOTE: when making temporary oper accounts, they are called _grant*.
# you probably shouldn't have any blocks called _grant* in your configuration.

# ALSO: upon rehashing, all oper accounts are restored and that's for the granted privs.

# BUGS: as of now, dead blocks remain when a user that has been /granted quits.
# this will be fixable when quit hooks are made. it doesn't really cause any problems anyway.

# PLANS: right now, oper privs are string. this was okay until now when we need them to in an array.

package module::grant;

use warnings;
use strict;

use API::Module;
use API::Command;
use utils 'snotice';

register_module('grant', 0.1, 'Grant or remove a user\'s operator privs.', \&init, \&void);

my %grant;

# initialization subroutine
sub init {

    # register the commands
    register_command('grant', 'Grant operator privs to a user.', \&handle_grant) or return;
    register_command('deoper', 'Remove all oper privs from a user.', \&handle_deoper) or return;

    return 1
}

# void subroutine
sub void {

    snotice('grant module is deleting all temporary oper accounts.');

    # delete accounts we made
    while (my ($oper, $user) = each %grant) {
        delete $main::oper{$oper};
        if ($user->{oper} eq $oper) {
            $user->unsetmode('o');
            delete $user->{oper}
        }
    }

    return 1
}

# handle the GRANT command
sub handle_grant {
    my ($user, $data) = @_;
    my @args = split /\s+/, $data;

    # parameter check
    if (!defined $args[2]) {
        $user->numeric(461, 'GRANT');
        return
    }

    my $target = user::nickexists($args[1]);

    # check for an existing nick
    if (!$target) {
        $user->snt('grant', 'no such nick '.$args[1]);
        return
    }

    # check that he can do this
    if ($user->can('grant')) {

        # if they don't have an oper block, make one for them.
        my $oper = $target->{'oper'};
        if (!$oper) {
            $oper = '_grant'.$target->id;
            $grant{$oper} = $target;
            $target->{oper} = $oper;
            $target->setmode('o')
        }

        # privs are separated by space.
        foreach my $priv (@args[2..$#args]) {
            $main::oper{$oper}{privs} .= q. ..$priv
        }

        # success
        $user->snt('grant', $target->nick.' now has privs: '.(join q. ., $main::oper{$oper}{privs}));
        snotice($user->nick.' used GRANT to give '.$target->nick.' privs: '.(join q. ., @args[2..$#args]));
        return 1

    }

    # doesn't have grant flag
    else {
        $user->numeric(481)
    }

    return
}

sub handle_deoper {
    my ($user, $data) = @_;
    my @args = split /\s+/, $data;

    # parameter check
    if (!defined $args[1]) {
        $user->numeric(461, 'DEOPER');
        return
    }

    my $target = user::nickexists($args[1]);

    # check for an existing nick
    if (!$target) {
        $user->snt('deoper', 'no such nick '.$args[1]);
        return
    }

    if ($user->can('deoper')) {

        # see if they have anything in the first place
        if (!$target->{oper}) {
            $user->snt('deoper', $target->nick.' is not opered.');
            return
        }

        my $oper = $target->{oper};

        # if we made this account, delete it.
        if (exists $grant{$oper}) {
            delete $grant{$oper};
            delete $main::oper{$oper}
        }

        # force them to deoper
        delete $target->{oper};
        $user->unsetmode('o');

        # success
        $user->snt('deoper', $target->nick.' has been cleared of all privs.');
        $user->snotice($user->nick.' used DEOPER to remove all privs from '.$target->nick);
        return 1

    }

    # doesn't have deoper flag
    else {
        $user->numeric(481)
    }

    return
}

1
