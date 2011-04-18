#!/usr/bin/perl
# Copyright (c) 2011, Mitchell Cooper

# adds GRANT command.
# ^ requires the grant oper flag
# parameters: <nick> <priv> [<priv>] [...]

# adds UNGRANT command.
# ^ requires the ungrant oper flag
# parameters: <nick> <priv> [<priv>] [...]

# adds PRIVS command.
# ^ requires the privs oper flag
# parameters: <nick>

# this module requires 1.0.1 and above

package module::grant;

use warnings;
use strict;

use API::Module;
use API::Command;
use utils 'snotice';

# register the module to API::Module
register_module('grant', 0.4, 'Easily manage your oper flags.', \&init, sub { return 1 });

sub init {

    # register commands
    register_command('grant', 'Grant oper privs to a user.', \&handle_grant) or return;
    register_command('ungrant', 'Remove oper privs from a user.', \&handle_ungrant) or return;
    register_command('privs', 'View a user\'s oper flags.', \&handle_privs) or return;

    return 1
}

sub handle_grant {
    my ($user, @args) = (shift, (split /\s+/, shift));

    # parameter check
    if (!defined $args[2]) {
        $user->numeric(461, 'GRANT');
        return
    }

    # check for required permission
    if ($user->can('grant')) {

        # check for existing nick
        my $target = user::nickexists($args[1]);
        if (!$target) {
            $user->numeric(401, $args[1]);
            return
        }

        # add the privs
        my @privs = @args[2..$#args];
        $target->add_privs(@privs);

        # success
        snotice("$$user{nick} granted privs on $$target{nick}: ".(join q. ., @privs));
        $user->snt('grant', $target->nick.' now has privs: '.(scalar @{$target->{privs}} ? join q. ., @{$target->{privs}} : '(none)'));
        return 1

    }

    # incorrect permission
    else {
        $user->numeric(481)
    }

    return
}

sub handle_ungrant {
    my ($user, @args) = (shift, (split /\s+/, shift));

    # parameter check
    if (!defined $args[2]) {
        $user->numeric(461, 'UNGRANT');
        return
    }

    # check for required permission
    if ($user->can('ungrant')) {

        # check for existing nick
        my $target = user::nickexists($args[1]);
        if (!$target) {
            $user->numeric(401, $args[1]);
            return
        }

        # add the privs
        my @privs = @args[2..$#args];
        $target->del_privs(@privs);

        # success
        snotice("$$user{nick} ungranted privs from $$target{nick}: ".(join q. ., @privs));
        $user->snt('ungrant', $target->nick.' now has privs: '.(scalar @{$target->{privs}} ? join q. ., @{$target->{privs}} : '(none)'));
        return 1

    }

    # incorrect permission
    else {
        $user->numeric(481)
    }

    return
}

sub handle_privs {
    my ($user, @args) = (shift, (split /\s+/, shift));

    # parameter check
    if (!defined $args[1]) {
        $user->numeric(461, 'PRIVS');
        return
    }

    # check that they can use privs
    if (!$user->can('privs')) {
        $user->numeric(481);
        return
    }

    # check for existing nick
    my $target = user::nickexists($args[1]);
    if (!$target) {
        $user->numeric(401, $args[1]);
        return
    }

    $user->snt('privs', $target->nick.' has privs: '.(scalar @{$target->{privs}} ? join q. ., @{$target->{privs}} : '(none)'));

    # success
    return 1

}

1
