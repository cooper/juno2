#!/usr/bin/perl -w
# Copyright (c) 2011, Mitchell Cooper
package channel;

use warnings;
use strict;
use feature qw/say switch/;

use utils qw/conf hostmatch snotice/;

our %channels;

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
    } foreach split //, conf('channel', 'automodes');
    $channel->allsend(':%s MODE %s +%s', 0, conf('server', 'name'), $name, conf('channel','automodes')) if conf('channel', 'automodes');

    snotice('channel '.$name.' created by '.$user->fullhost);
    return $channel
}

sub dojoin {
    # the actual join of a user
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

sub banned {
    # check if a user's displayed or actual mask matches any channel bans
    # and if there are no exceptions
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

sub allsend {
    # send to all users of a channel, with an optional exception
    my ($channel, $data, $exception) = (shift, shift, shift);
    foreach (keys %{$channel->{'users'}}) {
        my $usr = user::lookupbyid($_);
        $usr->send(sprintf $data, @_) unless $usr == $exception
    }
    return 1
}

sub opsend {
    # send to users with operator status and above, with an optional exception
    my ($channel, $data, $exception) = (shift, shift, shift);
    foreach (keys %{$channel->{'users'}}) {
        my $usr = user::lookupbyid($_);
        next unless $channel->basicstatus($usr, 1);
        $usr->send(sprintf $data, @_) unless $exception == $usr;
    }
    return 1
}

sub remove {
    # remove user from channel
    my $channel = shift;
    my $id = shift->{'id'};

    # delete their data
    delete $channel->{$_}->{$id} foreach qw/users owners admins ops halfops voices invites/;

    # check if the channel is now empty
    $channel->check;

    return 1
}

sub who {
    # WHO command
    # (who knows why this is here and not in userhandlers.pm?)
    # and heck, this isn't a proper WHO query anyway.
    my $channel = shift;
    my $user = shift;
    foreach (keys %{$channel->{'users'}}) {
        my $u = user::lookupbyid($_);
        my $flags = (defined $u->{'away'}?'G':'H').
        (defined $u->{'oper'}?'*':'').
        (defined $channel->{'owners'}->{$_}?'~':'').
        (defined $channel->{'admins'}->{$_}?'&':'').
        (defined $channel->{'ops'}->{$_}?'@':'').
        (defined $channel->{'halfops'}->{$_}?'%':'').
        (defined $channel->{'voices'}->{$_}?'+':'');

        # this is ugly, but I could care less.
        $user->sendservj(352,
            $user->nick,
            $channel->name,
            $u->{'ident'},
            $u->{'cloak'},
            conf('server','name'),
            $u->nick,
            $flags,
            ':0',
            $u->{'gecos'}
        );
    }
    return 1
}

sub check {
    # check if a channel is empty
    my $channel = shift;
    if (scalar keys %{$channel->{'users'}} <= 0) {
        # it's empty, so delete its data
        delete $channels{lc $channel->name};

        snotice('dead channel: '.$channel->name)
    }
}

sub has {
    # check if a user has status(es) (by name)
    my ($channel, $user, @status) = @_;
    foreach (@status) {
        # say yes, they have this
        return 1 if $channel->{$_.'s'}->{$user->{'id'}}
    }

    # no matches
    return
}

sub names {
    # NAMES comamnd
    # (why is this here and not in userhandlers.pm?)
    my ($channel, $user) = @_;
    my @users = ();

    # find the users
    foreach (keys %{$channel->{'users'}}) {
        my $u = user::lookupbyid($_);
        next if ($u->ismode('i') and !$user->ison($channel));
        push @users, ($channel->prefix($u) ? $channel->prefix($u).$u->nick : $u->nick);
    }

    # send the info
    $user->numeric(353, $channel->name, (join ' ', @users)) unless $#users < 0;
    $user->numeric(366, $channel->name);

    return 1
}

sub prefix {
    # fetch a user's prefix
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

sub chanexists {
    # check if a channel exists (by name)
    my $name = lc shift;

    # found it
    return $channels{$name} if exists $channels{$name};

    # no match
    return
}

sub basicstatus {
    # does this user have halfop or greater?
    # (halfop doesn't count if a third argument is true
    my ($channel, $user) = (shift, shift);
    my $halfop = $channel->has($user, 'halfop');

    # no halfops allowed!
    $halfop = 0 if shift;

    # nope
    return if (!$channel->has($user, 'owner') && !$channel->has($user, 'admin') && !$channel->has($user, 'op') && !$halfop);

    # yep
    return 1
}

sub setmode {
    # do an actual mode set
    # note: the mode handler is handlemode()
    # this actually sets the mode
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

sub ismode {
    # check if a channel is a mode, returning it's value if so
    my ($channel, $mode) = @_;

    # found it
    return $channel->{'mode'}->{$mode} if exists $channel->{'mode'}->{$mode};

    # it's not
    return
}

sub unsetmode {
    # delete mode(s)
    my $channel = shift;
    delete $channel->{'mode'}->{$_} foreach split //, shift;
    return 1
}

sub name {
    # fetch the channel's name
    return shift->{'name'}
}


sub handlemode {
    # main mode handler for channels
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
        last if $i > conf('limit', 'chanmodes');
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
            } else {
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
            } else {
                # we need a parameter.
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
                } else {
                    # uh-oh?
                    $ok = 0
                }
            } else {
                # no parameter, so send the list and continue
                $channel->sendmasklist($user, $mode);
                next
            }
        }

        # modes q, a, o, h, and v
        elsif ($mode ~~ @status_modes) {
            # by the way, this does not use $needs_operator because
            # handlestatus() itself deals with that
            my $target_nick = $parameter->() or next;

            # are they allowed to set this?
            if (my $nickname = $channel->handlestatus($user, $state, $mode, $target_nick)) {
                # handlestatus returns the user's nickname in proper case
                push @finished_parameters, $nickname
            } else {
                # handlestatus returned false! :(
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

sub handlestatus {
    my ($channel, $user, $state, $mode, $tuser) = @_;
    my (@needs, $modename, $longname);

    # define mode names and their requirements
    given ($mode) {
        when ('q') {
            $modename = 'owners';
            @needs = 'owner';
            $longname = 'owner'
        } when ('a') {
            $modename = 'admins';
            @needs = ('owner','admin');
            $longname = 'administrator'
        } when ('o') {
            $modename = 'ops';
            @needs = ('owner','admin','op');
            $longname = 'operator'
        } when ('h') {
            $modename = 'halfops';
            @needs = ('owner','admin','op');
            $longname = 'operator'
        } when ('v') {
            $modename = 'voices';
            @needs = ('owner','admin','op','halfop');
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
    } else {
        # remove their status
        delete $channel->{$modename}->{$target->{'id'}}
    }

    # success!
    # by the way, this returns the nickname to properly relay mode changes in handlemode()
    return $target->nick
}

sub showtopic {
    # send topic numerics
    my ($channel, $user, $halt) = @_;
    if ($channel->{'topic'}) {
        $user->numeric(332, $channel->name, $channel->{'topic'}->{'topic'});
        $user->numeric(333, $channel->name, $channel->{'topic'}->{'setby'}, $channel->{'topic'}->{'time'});
        return 1
    }
    $user->numeric(331, $channel->name) unless $halt;
}

sub settopic {
    # set the topic
    my ($channel, $user, $topic) = @_;
    my $success = 0;

    # see if they can set it
    if ($channel->ismode('t')) {
        $success = 1 if $channel->basicstatus($user);
    } else {
        $success = 1
    }
    if ($success) {
        # they can
        $channel->{'topic'} = {
            'topic' => $topic,
            'time' => time,
            'setby' => (
                conf('main','fullmasktopic')
                ? $user->fullcloak
                : $user->nick
            )
        };
        $channel->allsend(':%s TOPIC %s :%s', 0, $user->fullcloak, $channel->name, $topic)
    } else {
        # they can't.
        $user->numeric(482, $channel->name, 'half-operator')
    }
}

sub canspeakwithstatus {
    # check if a user can speak with the status they have
    my ($channel, $user) = @_;

    # they don't
    return
    if (!$channel->has($user, 'owner')
    && !$channel->has($user, 'admin')
    && !$channel->has($user, 'op')
    && !$channel->has($user, 'halfop')
    && !$channel->has($user, 'voice'));

    # they do
    return 1
}

sub privmsgnotice {
    # send a PRIVMSG or NOTICE
    # I am too lazy to make this prettier. it works the way it is.
    my ($channel, $user, $type, $msg) = @_;

    # you must be in the channel if n is set.
    if (($channel->ismode('n') && !$user->ison($channel))

    # you have to have voice or such to speak in a moderated room
    || ($channel->ismode('m') && !$channel->canspeakwithstatus($user))

    # is this user banned?
    || ((hostmatch($user->fullcloak, keys %{$channel->{'bans'}}) || hostmatch($user->fullhost, keys %{$channel->{'bans'}})

    # is he muted?
    || hostmatch($user->fullcloak,keys %{$channel->{'mutes'}}) || hostmatch($user->fullhost,keys %{$channel->{'mutes'}}))

    # does he have the required status he needs to speak here?
    && !$channel->canspeakwithstatus($user)

    # and doesn't have an exception?
    && !hostmatch($user->fullcloak,keys %{$channel->{'exempts'}}))) {

        # show the ops if z is set
        if ($channel->ismode('z')) {

            # z doesn't work unless you're in the channel.
            # it doesn't allow you to override n
            if (!$user->ison($channel)) {
                $user->numeric(404, $channel->name);
                return
            }

            # okay, they're on the channel, so let's send it to the ops
            $channel->opsend(':'.$user->fullcloak.q( ).(join ' ', $type, $channel->name, ':'.$msg), $user);
            return 1

        # otherwise give them an error
        } else {
            $user->numeric(404, $channel->name);
            return
        }
    }

    # cool, he can send it
    $channel->allsend(':%s %s %s :%s', $user, $user->fullcloak, $type, $channel->name, $msg);
    return 1
}

sub handlemaskmode {
    # handle modes q, a, o, h, and v
    my ($channel, $user, $state, $mode, $mask) = @_;

    # this user can't even set modes... why is he trying to give someone status?
    $user->numeric(482, $channel->name, 'half-operator'), return unless $channel->basicstatus($user);

    # A doesn't check masks because it's the odd one out
    if ($mode ne 'A') {

         # make an idiot's excuse for a mask somewhat acceptable
         if ($mask =~ m/\@/) {
            if ($mask !~ m/\!/) {
                $mask = '*!'.$mask
            }
        } else {
            if ($mask =~ m/\!/) {
                $mask = $mask.'@*'
            } else {
                $mask = $mask.'!*@*'
            }
        }
    } else {
        # handle an auto-access mask
        if ($mask !~ m/^(q|a|o|h|v):/) {
            # we'll assume they meant o
            $mask = 'o:'.$mask
        }
    }

    # get the name of the mode
    my $modename;
    given ($mode) {
        when ('b') {
            $modename = 'bans'
        } when ('Z') {
            $modename = 'mutes'
        } when ('I') {
            $modename = 'invexes'
        } when ('A') {
            $modename = 'autoops';
            return unless $channel->canAmode($user, (split ':', $mask)[0])
        } when ('e') {
            $modename = 'exempts'
        }
    }

    # cool, do the change
    if ($state) {
        # set the mode
        $channel->{$modename}->{lc $mask} = [$user->fullcloak, time, $mask]
    } else {
        # delete the mode
        delete $channel->{$modename}->{lc $mask}
    }

    # success
    return $mask
}

sub sendmasklist {
    my ($channel, $user, $modes) = @_;
    MODES: foreach (split //, $modes) {
        next unless $_ =~ m/^(b|Z|e|I|A)$/;
        my @list;

        # set the numerics, mode names, requirements, etc.
        given ($_) {
            when ('b') {
                @list = (367, 368, 'bans', 0)
            } when ('Z') {
                @list = (728, 729, 'mutes', 0)
            } when ('e') {
                @list = (348, 349, 'exempts', 1)
            } when ('A') {
                @list = (388, 389, 'autoops', 1)
            } when ('I') {
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
    my @users = keys %{$channel->{'users'}};

    # send the name, number of users, and topic.
    $user->numeric(322,
        $channel->name,
        $#users+1,
        $channel->{'topic'}
        ? $channel->{'topic'}->{'topic'}
        : ''
    );
    return 1
}

sub handleparmode {
    # handle a mode with a single parameter
    my ($channel, $user, $mode, $parameter) = @_;
    given ($mode) {
        # channel  limit
        when ('l') {
            # make sure the amount is valid
            if ($parameter !~ m/[^0-9]/ && $parameter != 0) {
                # don't allow limits that are gigantic
                $parameter = 9001 if int $parameter > 9000;
                $channel->setmode('l', $parameter);
                return $parameter
            }
            return
        } default {
            # unknown mode ?
            return
        }
    }
}

sub doauto {
    # apply automatic status (A mode)
    my ($channel, $user) = @_;
    my ($modes, @parameters, %done) = '';
    foreach (keys %{$channel->{'autoops'}}) {
        my @s = split ':', $_, 2;

        # we've already set this mode
        next if $done{$s[0]};

        # if their displayed or actual cloak match, apply the status
        if (hostmatch($user->fullcloak, $s[1]) || hostmatch($user->fullhost, $s[1])) {
            $modes .= $s[0];

            # to keep us from setting the same mode twice
            $done{$s[0]} = 1;

            
            push @parameters, $user->nick;
            given ($s[0]) {
                when ('q') {
                    # set owner
                    $channel->{'owners'}->{$user->{'id'}} = time
                } when ('a') {
                    # set administrator
                    $channel->{'admins'}->{$user->{'id'}} = time
                } when ('o') {
                    # set operator
                    $channel->{'ops'}->{$user->{'id'}} = time
                } when ('h') {
                    # set half-operator
                    $channel->{'halfops'}->{$user->{'id'}} = time
                } when ('v') {
                    # set voice
                    $channel->{'voices'}->{$user->{'id'}} = time
                }
            }
        }
    }

    # relay the mode change unless it's blank
    $channel->allsend(':%s MODE %s +%s %s', 0, conf('server', 'name'), $channel->name, $modes, (join ' ', @parameters)) unless $modes eq '';
    return 1
}

sub canAmode {
    # check if a user is capable of setting an A mode.
    # in order to set q:* for example, he must have owner status.
    my ($channel, $user, $Amode) = @_;

    given ($Amode) {
        when ('q') {
        # check for owner
            if (!$channel->has($user, 'owner')) {
                # they don't have it
                $user->numeric(482, $channel->name, 'owner');
                return
            }
        } when ('a') {
            # check for admin or greater
            if (!$channel->has($user, qw(owner admin))) {
                # they don't have it
                $user->numeric(482, $channel->name, 'administrator');
                return
            }
        } when ('o') {
            # check for op or greater
            if (!$channel->has($user, qw(owner admin op))) {
                # they don't have it
                $user->numeric(482, $channel->name, 'operator');
                return
            }
        } when ('h') {
            # check for op or greater
            if (!$channel->has($user, qw(owner admin op))) {
                # they don't have it
                $user->numeric(482, $channel->name, 'operator');
                return
            }
        }
    }

    # they have what they need
    return 1
}

1
