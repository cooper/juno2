#!/usr/bin/perl -w
# Copyright (c) 2011, Mitchell Cooper
package channel;

use warnings;
use strict;
use feature qw/say switch/;

use utils qw/conf hostmatch snotice/;

our %channels;

# create a new channel
sub new {
    my ($user, $name) = @_;

    # create the channel object
    bless my $channel = {
        'name' => $name,
        'time' => time,
        'first' => time,
        'creator' => $user->nick,
        'owners' => {
            # they get owner on join
            $user->{'id'} => time
        },
        'ops' => {
            # they get op on join
            $user->{'id'} => time
        }
    };
    $channels{lc $name} = $channel;

    # do the actual user join
    $channel->dojoin($user);

    # set auto modes
    $channel->{'mode'}->{$_} = {
        'time' => time,
        'params' => undef
    } foreach split //, conf qw/channel automodes/;
    $channel->allsend(':%s MODE %s +%s', 0, (conf qw/server name/), $name, (conf qw/channel automodes/)) if conf qw/channel automodes/;

    snotice('channel '.$name.' created by '.$user->fullhost);
    return $channel
}

# the actual join of a user
sub dojoin {
    my ($channel, $user) = @_;
    my @users = keys %{$channel->{'users'}};

        # check for bans without exceptions
        if ($channel->banned($user)) {
            # can't join; banned
            $user->numeric(474, $channel->name);
            return
        }

        # check if the channel is invite-only
        if ($channel->ismode('i')

        # and if they don't have an invite exception
        && !hostmatch($user->fullcloak, keys %{$channel->{'invexes'}})

        # and if they have not been invited
        && !$channel->{'invites'}->{$user->{'id'}}) {
            # can't join; not invited.
            $user->numeric(473, $channel->name);
            return
        }

        # check if the channel has a user count limit set
        if ($channel->ismode('l')

        # and if the limit is reached
        && $#users+1 >= $channel->{'mode'}->{'l'}->{'params'}) {
            # can't join; channel full
            $user->numeric(471, $channel->name);
            return
        }

        # delete their invitation, if any
        delete $channel->{'invites'}->{$user->{'id'}};

        # add them to the user list
        $channel->{'users'}->{$user->{'id'}} = time;

        # relay their join to channel users
        $channel->allsend(':%s JOIN :%s', 0, $user->fullcloak, $channel->name);

        # send the topic and NAMES numerics
        $channel->showtopic($user, 1);
        $channel->names($user);

        # set any status that applies to this user's mask (mode A)
        $channel->doauto($user);

        # success
        return 1

}

# check if a user's displayed or actual mask matches any channel bans
# and if there are no exceptions
sub banned {
    my ($channel, $user) = @_;
    return 1 if (
        (hostmatch($user->fullcloak, keys %{$channel->{'bans'}})
            || hostmatch($user->fullhost, keys %{$channel->{'bans'}}))
        and (
                !hostmatch($user->fullcloak, keys %{$channel->{'exempts'}})
                && !hostmatch($user->fullhost, keys %{$channel->{'exempts'}})
           )
    );

    # not banned
    return

}

# send to all users of a channel, with an optional exception
sub allsend {
    my ($channel, $data, $exception) = (shift, shift, shift);
    foreach (keys %{$channel->{'users'}}) {
        my $usr = user::lookupbyid($_);
        $usr->send(sprintf $data, @_) unless $usr == $exception
    }
    return 1
}

 # send to users with operator status and above, with an optional exception
sub opsend {
    my ($channel, $data, $exception) = (shift, shift, shift);
    foreach (keys %{$channel->{'users'}}) {
        my $usr = user::lookupbyid($_);
        next unless $channel->basicstatus($usr, 1);
        $usr->send(sprintf $data, @_) unless $exception == $usr
    }
    return 1
}

# remove user from channel
sub remove {
    my $channel = shift;
    my $id = shift->{'id'};

    # delete their data
    delete $channel->{$_}->{$id} foreach qw/users owners admins ops halfops voices invites/;

    # check if the channel is now empty
    $channel->check;

    return 1
}

# fail WHO command
# (who knows why this is here and not in userhandlers.pm?)
sub who {
    my $channel = shift;
    my $user = shift;
    foreach (keys %{$channel->{'users'}}) {
        my $u = user::lookupbyid($_);
        my $flags = (defined $u->{'away'} ? 'G' : 'H').
        (defined $u->{'oper'} ? '*' : q..).
        (defined $channel->{'owners'}->{$_} ? '~' : q..).
        (defined $channel->{'admins'}->{$_} ? '&' : q..).
        (defined $channel->{'ops'}->{$_} ? '@' : q..).
        (defined $channel->{'halfops'}->{$_}? '%': q..).
        (defined $channel->{'voices'}->{$_}? '+' : q..);

        # this is ugly, but I could care less.
        $user->sendservj(352,
            $user->nick,
            $channel->name,
            $u->{'ident'},
            $u->{'cloak'},
            (conf qw/server name/),
            $u->nick,
            $flags,
            ':0',
            $u->{'gecos'}
        );

    }
    return 1
}

# check if a channel is empty
sub check {
    my $channel = shift;

    if (!scalar keys %{$channel->{'users'}}) {

        # it's empty, so delete its data
        delete $channels{lc $channel->name};
        snotice('dead channel: '.$channel->name);
        return

    }

    # it still exists
    return 1

}

# check if a user has status(es) (by name)
sub has {
    my ($channel, $user, @status) = @_;
    foreach (@status) {
        # say yes, they have this
        return 1 if $channel->{$_.'s'}->{$user->{'id'}}
    }

    # no matches
    return

}

# NAMES comamnd
# (why is this here and not in userhandlers.pm?)
sub names {
    my ($channel, $user) = @_;
    my @users = ();

    # find the users
    foreach (keys %{$channel->{'users'}}) {
        my $u = user::lookupbyid($_);
        next if ($u->ismode('i') and !$user->ison($channel));
        push @users, ($channel->prefix($u) ? $channel->prefix($u).$u->nick : $u->nick);
    }

    # send the info
    $user->numeric(353, $channel->name, (join q. ., @users)) unless $#users < 0;
    $user->numeric(366, $channel->name);

    return 1
}

# fetch a user's prefix
sub prefix {
    my ($channel, $user) = @_;
    if ($channel->has($user, 'owner')) {
        return '~'
    }
    if ($channel->has($user, 'admin')) {
        return '&'
    }
    if ($channel->has($user, 'op')) {
        return '@'
    }
    if ($channel->has($user, 'halfop')) {
        return '%'
    }
    if ($channel->has($user, 'voice')) {
        return '+'
    }

    # they don't have any special status
    return
}

# check if a channel exists (by name)
sub chanexists {
    my $name = lc shift;

    # found it
    return $channels{$name} if exists $channels{$name};

    # no match
    return
}

# does this user have halfop or greater?
# (halfop doesn't count if a third argument is true
sub basicstatus {
    my ($channel, $user) = (shift, shift);
    my $halfop = $channel->has($user, 'halfop');

    # no halfops allowed!
    $halfop = 0 if shift;

    # nope
    return if (!$channel->has($user, 'owner') && !$channel->has($user, 'admin') && !$channel->has($user, 'op') && !$halfop);

    # yep
    return 1

}

# do an actual mode set
# note: the mode handler is handlemode()
# this actually sets the mode
sub setmode {
    my ($channel, $mode, $parameter) = @_;

    # set the mode
    $channel->{'mode'}->{$mode} = {
        'time' => time,
        'params' => (
            # if there's a parameter, set it
            defined $parameter ?
                $parameter

            # otherwise use undef I guess..
            : undef
        )
    };

    return 1
}

# check if a channel is a mode, returning it's value if so
sub ismode {
    my ($channel, $mode) = @_;

    # found it
    return $channel->{'mode'}->{$mode} if exists $channel->{'mode'}->{$mode};

    # it's not
    return
}

# delete mode(s)
sub unsetmode {
    my $channel = shift;
    delete $channel->{'mode'}->{$_} foreach split //, shift;
    return 1
}

# fetch the channel's name
sub name {
    return shift->{'name'}
}


# main mode handler for channels
sub handlemode {
    my ($channel, $user) = (shift, shift);    
    if (!defined $_[0] || !length $_[0]) {
        # no string, so sending them a mode numeric
        $channel->showmodes($user);
        return
    }

    my @mode_string = split /\s+/, shift;
    my $modes = shift @mode_string;

    # modes without parameters
    my @normal_modes = qw/n t m i z/;

    # modes with a nickname as a parameter
    my @status_modes = qw/q a o h v/;

    # modes that require a mask
    my @mask_modes = qw/b e I Z A/;

    # modes with a parameter
    my @parameter_modes = qw/l/;

    # some modes (such as mask lists) do not require operator status.
    # qaohv are not here because they handle it in handlestatus().
    # these modes require op
    my @needs_op = qw/n t m i z l/;

    # if $success is false by the end of this mode string, a numeric is sent
    # reading that the user must have half-operator or above
    my $success = 1;

    # returns the next parameter or false if no parameters are left
    my $parameter = sub {
        if (my $result = shift @mode_string) {
            return $result
        }
        return
    };

    my @finished_parameters = ();
    my $finished_string = '+';
    my ($state, $cstate, $ok, $i) = (1, 1, 1, 0);

    # handle each mode individually
    foreach my $mode (split //, $modes) {
        $ok = 1;

        # if the mode limit is reached
        last if $i > conf qw/limit chanmodes/;
        $i++;

        # if they need op and don't have it, give up
        if ($mode ~~ @needs_op && !$channel->basicstatus($user)) {
            $success = 0;
            next
        }

        # setting or unsetting?
        $state = 1, next if $mode eq '+';
        $state = 0, next if $mode eq '-';

        # normal modes without parameters
        if ($mode ~~ @normal_modes) {
            if ($state) {
                $channel->setmode($mode)
            }
            else {
                $channel->unsetmode($mode)
            }
        }

        # modes with a parameter
        elsif ($mode ~~ @parameter_modes) {
            if (defined (my $par = $parameter->())) {
                if (my $cool_it_worked = $channel->handleparmode($user, $mode, $par)) {
                    push @finished_parameters, $cool_it_worked
                }

                # that'll send a numeric if there's a problem

            }

            # we need a parameter.
            else {
                $ok = 0
            }

        }

        # modes with masks as their parameters
        elsif ($mode ~~ @mask_modes) {
            my $par = $parameter->();
            if (defined $par) {
                my $result = $channel->handlemaskmode($user, $state, $mode, $par);
                if (defined $result) {

                    # worked!
                    push @finished_parameters, $result

                }

                # uh-oh? handlemaskmode() said no
                else {
                    $ok = 0

                }

            }

            # no parameter, so send the list and continue
            else {
                $channel->sendmasklist($user, $mode);
                next
            }

        }

        # modes q, a, o, h, and v
        elsif ($mode ~~ @status_modes) {
            my $target_nick = $parameter->() or next;

            # are they allowed to set this?
            if (my $nickname = $channel->handlestatus($user, $state, $mode, $target_nick)) {

                # handlestatus returns the user's nickname in proper case
                push @finished_parameters, $nickname

            }

            # handlestatus returned false :(
            else {
                $ok = 0
            }

        }

        # unknown mode
        else {
            $user->numeric(472, $mode);
            next
        }

        # $ok is set to false if there was an error or something, and it's not added to the final string
        if ($ok) {
            if ($cstate != $state) {
                $finished_string .= ($state ? '+' : '-');
                $cstate = $