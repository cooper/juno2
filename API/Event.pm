#!/usr/bin/perl
# Copyright (c) 2011, Mitchell Cooper
package API::Event;

use warnings;
use strict;
use base 'Exporter';
use feature 'say';

use Exporter;

use utils 'snotice';

our @EXPORT = qw/register_event delete_event event/;
our %EVENT;

# register an event
# parameters: event_name, sub
sub register_event {
    my $package = caller;

    # parameter check
    if ($#_ < 1) {
        notice("not enough parameters for register_event by $package");
        return
    }

    my ($event, $code) = @_;

    # make sure this package hasn't registered this event.
    if (exists $EVENT{$event}{$package}) {
        notice("$package already registered the $event event; aborting.")
    }

    # only accept CODE to prevent fatal errors
    if (ref $code ne 'CODE') {
        notice("not a CODE ref for event $event in register_event by $package\n");
        return
    }

    # all is good
    $EVENT{$event}{$package} = $code;
    return 1

}

# delete an event
sub delete_event {
    my $package = caller;

    # parameter check
    my $event = shift;
    if (!defined $event) {
        notice("no event specified in delete_event by $package; aborting.");
        return
    }

    # success
    notice("deleting event $event from $package");
    delete $EVENT{$event}{$package};
    return 1

}

# run an event
sub event {
    my ($package, $event) = ((caller)[0], shift);
    say "event $event called by $package";

    # run through each registration of this event
    while (my ($pkg, $code) = each %{$EVENT{$event}}) {
        say "calling $pkg for event $event";
        $code->(@_)
    }

    return 1
}

# remove all events by a package
sub delete_package {
    my ($obj, $package) = @_;
    notice('Deleting all events registered by '.$package);
    delete $EVENT{$_}{$package} foreach keys %EVENT;
}

sub notice {
    my $msg = shift;
    say $msg;
    snotice($msg);
    return 1
}

1
