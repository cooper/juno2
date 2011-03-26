#!/usr/bin/perl -w
# Copyright (c) 2011, Mitchell Cooper
package API::Command;

use warnings;
use strict;
use feature 'say';

use Exporter;
use API::Module;

our @EXPORT = qw/command_register command_exists/;
our %COMMAND;

sub command_register {
    # arguments: command coderef
    my $package = caller 0;
    my ($command, $code) = @_;

    if (exists $COMMAND{$command}{$package}) {
        say 'Command '.$command.' has already been registered by '.$package.'; aborting register.';
        return
    }

    # make sure they gave the required arguments
    if ($#_ < 1) {
        say 'Not enough arguments for command_register given by package '.$package;
        return
    }

    # create the command
    $COMMAND{$command}{$package} = {
        'name' => $command,
        'code' => $code
    };

    # success
    say 'Command '.$command.' registered successfully by '.$package;
    return 1
}

sub command_exists {
    my $command = shift;
}

1
