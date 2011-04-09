#!/usr/bin/perl
# Copyright (c) 2011, Mitchell Cooper

# API::Loop was LITERALLY copied directly from denny.
# we can't really expect it to be perfect!

package API::Loop;

use warnings;
use strict;
use feature 'say';
use base 'Exporter';

use Exporter;
use API::Module;
use utils 'snotice';

our @EXPORT = qw/register_loop delete_loop/;
our %LOOP;

# register a loop
sub register_loop {
    # parameters: name coderef
    # returns a loop id

    my $package = caller;
    my ($name, $code) = @_;

    if (!exists $API::Module::MODULE{$package}) {
        say 'Can\'t register_loop before register_module; aborting.';
        return
    }

    # make sure it's a coderef
    if (ref $code ne 'CODE') {
        say 'Not a CODE reference in register_loop; aborting register.';
        return
    }

    # attempt to register the loop
    my $id = main::register_loop($name, $package, $code) or return;

    # add to %LOOP
    $LOOP{$package}{$id} = {
        name => $name,
        package => $package,
        id => $id
    };

    # success
    say "Registered loop $name [$id] by $package";
    return $id

}

# delete a loop by its ID
sub delete_loop {
    my $package = caller;
    my $id = shift;
 
    # make sure it exists
    if (!exists $LOOP{$package}{$id}) {
        say 'No such loop in delete_loop; aborting';
        return
    }

    # success
    say "Deleting loop $LOOP{$package}{$id}{name} [$id]";
    delete $LOOP{$package}{$id};
    main::delete_loop($id);
    return 1

}

# delete all loops from a package
sub delete_package {
    my ($obj, $package) = (shift, shift);
    notice('Deleting all loops registered by '.$package);

    # delete each loop
    foreach my $id (keys %{$LOOP{$package}}) {
        say "Deleting loop $LOOP{$package}{$id}{name} [$id]";
        main::delete_loop($id);
    }

    delete $LOOP{$package};

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
