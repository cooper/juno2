#!/usr/bin/perl -w
# Copyright (c) 2011, Mitchell Cooper
package channel;

use warnings;
use strict;
use feature qw/say switch/;

use utils qw/conf hostmatch snotice cut_to_limit/;

our %channels;

# create a new channel
sub new {
    my ($this, $user, $name) = @_;

    # create the channel object
    bless my $channel = {
        name => $name,
        time => time,
        first => time,
        creator => $user->nick,
        owners => {
            # they get owner on join
            $user->{'id'} => time
        },
        ops => {
            # they get op on join
            $user->{'id'} => time
        }
    }, $this;
    $channels{lc $name} = $channel;

    # do the actual user join
    $channel->dojoin($user);

    # set auto modes
    $channel->automodes($user);

    snotice('channel '.$name.' created by '.$user->fullhost);
    return $channel
}

# the actual join of a user
sub dojoin {
    my ($channel, $user, $key) = @_;
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

        # check if the user has the proper key
        my $letmein = $channel->ismode('k');
        if (defined $letmein &&
          (not defined $key or $letmein->{params} ne $key)) {
            $user->numeric(475, $channel->name);
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
        ($u->ismode('o') ? '*' : q..).
        (defined $channel->{'owners'}->{$_} ? '~' : q..).
        (defined $channel->{'admins'}->{$_} ? '&' : q..).
        (defined $channel->{'ops'}->{$_} ? '@' : q..).
        (defined $channel->{'halfops'}->{$_} ? '%': q..).
        (defined $channel->{'voices'}->{$_} ? '+' : q..);

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
        time => time,
        params => (
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
    my @parameter_modes = qw/l k/;

    # some modes such as l do not need a parameter to unset but do to set.
    # these must also be in @parameter_modes.
    my @no_unset = qw/l/;

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

            # if it's a mode like l that doesn't need a parameter on unset,
            # just unset it
            if (!$state && $mode ~~ @no_unset) {
                $channel->unsetmode($mode)
            }

            # it needs a parameter for both unset and set
            # or this a set not an unset.
            else {
                if (defined (my $par = $parameter->())) {
                    if (my $cool_it_worked = $channel->handleparmode($user, $mode, $state, $par)) {
                        push @finished_parameters, $cool_it_worked
                    }
                    else {
                        $ok = 0
                    }
                }

                # we need a parameter.
                else {
                    $ok = 0
                }

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

            # handlestatus() returned false :(
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
                $cstate = $state
            }
            $finished_string .= $mode
        }
    }

    # show them a "requires half-operator" numeric if some mode(s) failed
    $user->numeric(482, $channel->name, 'half-operator') unless $success;

    $finished_string =~ s/\+-/-/g;
    $channel->allsend(':%s MODE %s %s %s', 0, $user->fullcloak, $channel->name, $finished_string, (join q. ., @finished_parameters))

    # this is what we started with
    unless $finished_string eq '+';

    # success
    return 1

}

# send channel modes
sub showmodes {
    my ($channel, $user) = @_;
    my (@modes, @parameters);
    while (my ($mode, $ref) = each %{$channel->{'mode'}}) {
        push @modes, $mode;
        if (defined $ref->{'params'}) {
            push @parameters, $ref->{'params'}
        }
    }
    $user->numeric(324, $channel->name, (join q.., @modes), (join q.., @parameters));
    $user->numeric(329, $channel->name, $channel->{'first'});
}

# handle modes q, a, o, h, and v
sub handlestatus {
    my ($channel, $user, $state, $mode, $tuser) = @_;
    my (@needs, $modename, $longname);

    # define mode names and their requirements
    given ($mode) {
        when ('q') {
            $modename = 'owners';
            @needs = 'owner';
            $longname = 'owner'
        }
        when ('a') {
            $modename = 'admins';
            @needs = qw/owner admin/;
            $longname = 'administrator'
        }
        when ('o') {
            $modename = 'ops';
            @needs = qw/owner admin op/;
            $longname = 'operator'
        }
        when ('h') {
            $modename = 'halfops';
            @needs = qw/owner admin op/;
            $longname = 'operator'
        }
        when ('v') {
            $modename = 'voices';
            @needs = qw/owner admin op halfop/;
            $longname = 'half-operator'
        }
    }

    # check if the user has what they need to set this mode
    if (!$channel->has($user, @needs)) {

        # they don't.
        $user->numeric(482, $channel->name, $longname);
        return

    }

    my $target = user::nickexists($tuser);

    # make sure the user exists
    if (!$target) {

        # they don't.
        $user->numeric(401, $tuser);
        return

    }

    # are they on the channel?
    if (!$target->ison($channel)) {

        # no, they aren't.
        $user->numeric(441, $target->nick, $channel->name);
        return

    }

    if ($state) {

        # give them the status
        $channel->{$modename}->{$target->{'id'}} = time

    }
    else {

        # remove their status
        delete $channel->{$modename}->{$target->{'id'}}

    }

    # success!
    # by the way, this returns the nickname to properly relay mode changes in handlemode()
    return $target->nick

}

# send topic numerics
sub showtopic {
    # $halt it used on channel join
    # because if no topic is set when you join, these numerics aren't sent at all
    my ($channel, $user, $halt) = @_;
    if ($channel->{'topic'}) {
        $user->numeric(332, $channel->name, $channel->{'topic'}->{'topic'});
        $user->numeric(333, $channel->name, $channel->{'topic'}->{'setby'}, $channel->{'topic'}->{'time'});
        return 1
    }

    # send "no topic is set"
    $user->numeric(331, $channel->name) unless $halt;
    return

}

# set the topic
sub settopic {
    my ($channel, $user, $topic) = @_;
    my $success = 0;

    # see if they can set it
    if ($channel->ismode('t')) {
        $success = 1 if $channel->basicstatus($user)
    }

    # if it's not +t, anyone can
    else {
        $success = 1
    }

    # they can
    if ($success) {
        $channel->{'topic'} = {
            topic => $topic,
            time => time,
            setby => (
                (conf qw/main fullmasktopic/)
                ? $user->fullcloak
                : $user->nick
            )
        };
        $channel->allsend(':%s TOPIC %s :%s', 0, $user->fullcloak, $channel->name, $topic);
        return 1
    }

    # they can't.
    else {
        $user->numeric(482, $channel->name, 'half-operator')
    }

    return
}

# check if a user can speak with the status they have
sub canspeakwithstatus {
    my ($channel, $user) = @_;

    # they don't have what they need
    return
    if (!$channel->has($user, 'owner')
    && !$channel->has($user, 'admin')
    && !$channel->has($user, 'op')
    && !$channel->has($user, 'halfop')
    && !$channel->has($user, 'voice'));

    # they can speak
    return 1

}

# send a PRIVMSG or NOTICE
# I am too lazy to make this prettier. it works the way it is.
# since it's so messy, I commented it line-by-line
sub privmsgnotice {
    my ($channel, $user, $type, $msg) = @_;

    # you must be in the channel if n is set.
    if (($channel->ismode('n') && !$user->ison($channel))

    # you have to have voice or such to speak in a moderated room
    || ($channel->ismode('m') && !$channel->canspeakwithstatus($user))

    # is this user banned?
    || ((hostmatch($user->fullcloak, keys %{$channel->{'bans'}}) || hostmatch($user->fullhost, keys %{$channel->{'bans'}})

    # is he muted?
    || hostmatch($user->fullcloak, keys %{$channel->{'mutes'}}) || hostmatch($user->fullhost, keys %{$channel->{'mutes'}}))

    # does he have the required status he needs to speak here?
    && !$channel->canspeakwithstatus($user)

    # and doesn't have an exception?
    && !hostmatch($user->fullcloak, keys %{$channel->{'exempts'}}))) {

        # show the ops if z is set
        if ($channel->ismode('z')) {

            # z doesn't work unless you're in the channel.
            # it doesn't allow you to override n
            if (!$user->ison($channel)) {
                $user->numeric(404, $channel->name);
                return
            }

            # okay, they're on the channel, so let's send it to the ops
            $channel->opsend(':'.$user->fullcloak.q( ).(join q. ., $type, $channel->name, ':'.$msg), $user);
            return 1

        }

        # otherwise give them an error
        else {
            $user->numeric(404, $channel->name);
            return
        }

    }

    # cool, he can send it
    $channel->allsend(':%s %s %s :%s', $user, $user->fullcloak, $type, $channel->name, $msg);
    return 1

}

# handle modes such as b
sub handlemaskmode {
    my ($channel, $user, $state, $mode, $mask) = @_;

    # this user can't even set modes... why is he trying to do this in the first place?
    $user->numeric(482, $channel->name, 'half-operator'), return unless $channel->basicstatus($user);

    # A doesn't check masks because it's the odd one out
    if ($mode ne 'A') {

         # make an idiot's excuse for a mask somewhat acceptable
         if ($mask =~ m/\@/) {
            if ($mask !~ m/\!/) {
                $mask = '*!'.$mask
            }
        }
        else {
            if ($mask =~ m/\!/) {
                $mask = $mask.'@*'
            }
            else {
                $mask = $mask.'!*@*'
            }
        }
    }


    # handle an auto-access mask
    else {
        my @m = split ':', $mask, 2;
        if ($#m) {

            # now we can do more than 1 setting in 1 mode :D
            my $finished_modes = q..;
            my %done;
            foreach my $status_mode (split //, $m[0]) {

                # make sure it's a legal mode first
                # and it's not already been used
                if ($status_mode =~ m/(q|a|o|h|v)/ && !$done{$status_mode}) {
                    $done{$status_mode} = 1;
                    $finished_modes .= $status_mode
                }

            }

            # put in form of modes:mask
            $mask = $finished_modes.q(:).$m[1]

        }

        # no mode type provided
        else {

            # we'll assume they meant o
            $mask = 'o:'.$mask

        }

    }

    # get the name of the mode
    my $modename;
    given ($mode) {
        when ('b') {
            $modename = 'bans'
        }
        when ('Z') {
            $modename = 'mutes'
        }
        when ('I') {
            $modename = 'invexes'
        }
        when ('A') {
            $modename = 'autoops';
            return unless $channel->canAmode($user, (split ':', $mask)[0])
        }
        when ('e') {
            $modename = 'exempts'
        }
    }

    # cool, do the change
    if ($state) {
        # set the mode
        my $from = $user->fullcloak;

        # if it's a server, remove anything but the server name
        $from = (split '!', $from)[0] if $user->nick =~ m/\./;

        $channel->{$modename}->{lc $mask} = [$from, time, $mask]
    }
    else {
        # delete the mode
        delete $channel->{$modename}->{lc $mask}
    }

    # success
    return $mask

}

sub sendmasklist {
    my ($channel, $user, $modes) = @_;
    MODES: foreach (split //, $modes) {

        # ignore non-mask modes
        next unless $_ =~ m/^(b|Z|e|I|A)$/;

        my @list;

        # set the numerics, mode names, requirements, etc.
        given ($_) {
            when ('b') {
                @list = (367, 368, 'bans', 0)
            }
            when ('Z') {
                @list = (728, 729, 'mutes', 0)
            }
            when ('e') {
                @list = (348, 349, 'exempts', 1)
            }
            when ('A') {
                @list = (388, 389, 'autoops', 1)
            }
            when ('I') {
                @list = (346, 347, 'invexes', 1)
            }
        }

        # if they need op (mode e, for example), check for it
        if ($list[3] && !$channel->basicstatus($user)) {
            # sux4u
            $user->numeric(482, $channel->name, 'half-operator');
            next MODES
        }

        # send the list
        foreach (keys %{$channel->{$list[2]}}) {
            $user->numeric($list[0],
                $channel->name,
                $channel->{$list[2]}->{$_}->[2],
                $channel->{$list[2]}->{$_}->[0],
                $channel->{$list[2]}->{$_}->[1]
            );
        }
        $user->numeric($list[1], $channel->name)

    }
    return 1
}

sub kick {
    # kick a user if possible
    # this is an ugly subroutine
    # but not everyone can be beautiful, studies conclude.
    my ($channel, $user, $target, $reason) = @_;
    return unless $channel->basicstatus($user);
    return if ($channel->has($target, 'owner') && !$channel->has($user, 'owner'));
    return if ($channel->has($target, 'admin') && !$channel->has($user, 'owner') && !$channel->has($user, 'admin'));
    return if ($channel->has($target, 'op') && !$channel->has($user, 'owner') && !$channel->has($user, 'admin') && !$channel->has($user, 'op'));
    return if ($channel->has($target, 'halfop') && !$channel->has($user, 'owner') && !$channel->has($user, 'admin') && !$channel->has($user, 'op'));

    # they can, so do it
    $channel->allsend(':%s KICK %s %s :%s', 0, $user->fullcloak, $channel->name, $target->nick, $reason);
    $channel->remove($target);
    return 1

}

sub list {
    # information for a channel shown in LIST command
    my ($channel, $user) = @_;

    # send the name, number of users, and topic.
    $user->numeric(322,
        $channel->name,
        scalar keys %{$channel->{'users'}},
        $channel->{'topic'}
        ? $channel->{'topic'}->{'topic'}
        : q..
    );

    return 1
}

# handle a mode with a single parameter
sub handleparmode {
    my ($channel, $user, $mode, $state, $parameter) = @_;
    given ($mode) {

        # channel  limit
        when ('l') {

            # -l does not required a parameter, so this is not the right place to handle it.
            return unless $state;

            # make sure the amount is valid
            if ($parameter !~ m/[^0-9]/ && $parameter != 0) {

                # don't allow limits that are gigantic
                $parameter = 9001 if int $parameter > 9000;

                $channel->setmode('l', $parameter);
                return $parameter
            }

            # invalid amount
            return

        }

        # channel key
        when ('k') {


            # if setting, go ahead and set it
            if ($state) {
                $parameter = cut_to_limit('chankey', $parameter);
                $parameter =~ s/,//;
                $channel->setmode('k', $parameter);
                return $parameter
            }

            return unless $channel->ismode('k');

            # if they are unsetting it and the parameter is right

            my $m = $channel->ismode('k');
            if ($parameter eq $m->{params}) {
                $channel->unsetmode('k');
                return $parameter
            }
           
        }

        # unknown mode ?

    }

    return
}

# apply automatic status (A mode)
sub doauto {
    my ($channel, $user) = @_;
    my (@modes, @parameters, %done);
    foreach (keys %{$channel->{'autoops'}}) {
        my ($mode, $mask) = split ':', $_, 2;

        foreach my $status_mode (split //, $mode) {
            # we've already set this mode
            next if $done{$status_mode};

            # if their displayed or actual cloak match, apply the status
            if (hostmatch($user->fullcloak, $mask) || hostmatch($user->fullhost, $mask)) {

                # to keep us from setting the same mode twice
                $done{$status_mode} = 1;

                my $name = mode2name($status_mode);

                # they already have that mode
                next if $channel->has($user, $name);
                
                push @parameters, $user->nick;
                push @modes, $status_mode;
                $channel->{$name.'s'}->{$user->{'id'}} = time
            }
       }
    }

    # relay the mode change unless it's blank
    $channel->allsend(':%s MODE %s +%s %s', 0, (conf qw/server name/), $channel->name, (join q.., @modes), (join q. ., @parameters)) if scalar @modes;

    return 1
}

# check if a user is capable of setting an A mode.
# in order to set q:* for example, he must have owner status.
sub canAmode {
    my ($channel, $user, $modes) = @_;

    # we support more than 1 status in a single mode now :)
    foreach my $Amode (split //, $modes) {
        given ($Amode) {

            # check for owner
            when ('q') {
                if (!$channel->has($user, 'owner')) {

                    # they don't have it
                    $user->numeric(482, $channel->name, 'owner');
                    return

                }
            }

            # check for admin or greater
            when ('a') {
                if (!$channel->has($user, qw(owner admin))) {

                    # they don't have it
                    $user->numeric(482, $channel->name, 'administrator');
                    return

                }
            }

            # check for op or greater
            when ('o') {
                if (!$channel->has($user, qw(owner admin op))) {

                    # they don't have it
                    $user->numeric(482, $channel->name, 'operator');
                    return

                }
            }

            # check for op or greater
            when ('h') {
                if (!$channel->has($user, qw(owner admin op))) {

                    # they don't have it
                    $user->numeric(482, $channel->name, 'operator');
                    return

                }
            }

        }
    }

    # they have what they need
    return 1

}

# change a mode to a mode name
sub mode2name {
    my $mode = shift;
    given ($mode) {
        when ('q') {
            return 'owner'
        }
        when ('a') {
            return 'admin'
        }
        when ('o') {
            return 'op'
        }
        when ('h') {
            return 'halfop'
        }
        when ('v') {
            return 'voice'
        }
    }

    # unknown
    return

}

# set auto channel modes
sub automodes {
    my ($channel, $user) = @_;
    my $modestr = conf qw/channel automodes/;
    next unless $modestr;

    # you'll find this funny, but I'm lazy.
    # like, seriously.
    my $oldnick = $user->nick;
    $user->{nick} = conf qw/server name/;
    $channel->handlemode($user, $modestr);
    $user->{nick} = $oldnick;

    return 1
}

1
