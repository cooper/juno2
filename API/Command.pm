#!/usr/bin/perl -w
# Copyright (c) 2011, Mitchell Cooper
package API::Command;

use warnings;
use strict;
use feature 'say';
use base 'Exporter';

use Exporter;
use API::Module;
use utils 'snotice';

our @EXPORT = 'register_command';
our %COMMAND;

# reigster a command
sub register_command {
    # arguments: command coderef description
    my @caller = caller;
    my $package = $caller[0];
    my ($command, $desc, $code) = @_;

    # make sure they're calling from inside a subroutine such as the init one
    # (this is to ensure that commands are not registered before a module's
    #  init sub returns a false value, causing the command to register without
    #  a parent package)
    if (!scalar @caller) {
        notice('Command '.$command.' can\'t be registered from outside of a subroutine');
        return
    }

    # see if it already exists
    if (exists $COMMAND{$command}{$package}) {
        notice('Command '.$command.' has already been registered by '.$package.'; aborting register.');
        return
    }

    # make sure they gave the required arguments
    if ($#_ < 2) {
        notice('Not enough arguments for command_register given by package '.$package);
        return
    }

    # see if user.pm will accept it
    if (user::register_handler($command, $code, $API::Module::MODULE{$package}{'name'}.q[-].$API::Module::MODULE{$package}{'version'}, $desc)) {
        # success
        notice('Command '.$command.' registered successfully by '.$package)
    }

    # failed
    else {
        notice('Command '.$command.' refused to load by user package');
        return
    }

    # create the command
    $COMMAND{$command} = {
        'package' => $package,
        'name' => $command,
        'code' => $code,
        'desc' => $desc
    };

    # success
    return 1
}

# delete a package by its name
sub delete_package {

    # delete all commands registered by a package
    my ($obj, $package) = (shift, shift);
    notice('Deleting all commands registered by '.$package);

    # check each command for a hook to this module
    foreach my $command (keys %COMMAND) {
        # check if we found one
        if ($COMMAND{$command}{'package'} eq $package) {
            # delete it
            delete $COMMAND{$command};
            user::delete_handler($command);
            notice('Deleted command '.$command.' by '.$package)
        }
    }

    # success
    return 1

}

sub notice {
    my $msg = shift;
    say $msg;
    snotice($msg);
    return 1
}

1
