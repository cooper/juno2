#!/usr/bin/perl
# Copyright (c) 2011, Mitchell Cooper

# adds GRANT command.
# ^ requires the grant oper flag
# parameters: <nick> <priv> [<priv>] [...]
# this module requires 1.0.1 and above

package module::grant;

use warnings;
use strict;

use API::Module;
use API::Command;
use utils 'snotice';

# register the module to API::Module
register_module('grant', 0.2, 'Easily manage your oper flags.', \&init, sub { return 1 });

sub init {

    # register command to API::Command
    register_command('grant', 'Grant oper privs to a user.', \&handle_grant) or return;

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
        $user->snt('grant', $target->nick.' now has privs: '.(join q. ., @{$target->{privs}}));
        return 1

    }

    # incorrect permission
    else {
        $user->numeric(481)
    }

    return
}

1
