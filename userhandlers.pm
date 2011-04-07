#!/usr/bin/perl -w
# Copyright (c) 2011, Mitchell Cooper
package userhandlers;

use warnings;
use strict;
use feature qw/switch say/;

use utils qw/col conf oper hostmatch snotice validnick validcloak/;

# command hash
# this will contain more information later when the module API is complete.
my %commands = (
    PONG => {
        'code' => sub {},
        'desc' => 'Reply to PING command'
    },
    SACONNECT => {
        'code' => sub {},
        'desc' => 'Force a user to connect to the server'
    },
    USER => {
        'code' => sub { shift->numeric(462) },
        'desc' => 'fake user command'
    },
    LUSERS => {
        'code' => \&handle_lusers,
        'desc' => 'View the server user statistics'
    },
    MOTD => {
        'code' => \&handle_motd,
        'desc' => 'View the message of the day'
    },
    NICK => { 
        'code' => \&handle_nick,
        'desc' => 'Change your nickname'
    },
    PING => {
        'code' => \&handle_ping,
        'desc' => 'Send a ping to the server'
    },
    WHOIS => {
        'code' => \&handle_whois,
        'desc' => 'View information on a user'
    },
    MODE => {
        'code' => \&handle_mode,
        'desc' => 'Set or view a user or channel mode'
    },
    PRIVMSG => {
        'code' => \&handle_privmsgnotice,
        'desc' => 'Send a message to a channel or user'
    },
    NOTICE => {
        'code' => \&handle_privmsgnotice,
        'desc' => 'Send a notice to a channel or user'
    },
    AWAY => {
        'code' => \&handle_away,
        'desc' => 'Mark yourself as being away'
    },
    OPER => {
        'code' => \&handle_oper,
        'desc' => 'Gain IRCop privileges'
    },
    KILL => {
        'code' => \&handle_kill,
        'desc' => 'Forcibly remove a user from the server'
    },
    JOIN => {
        'code' => \&handle_join,
        'desc' => 'Join a channel'
    },
    WHO => {
        'code' => \&handle_who,
        'desc' => 'View user information'
    },
    NAMES => {
        'code' => \&handle_names,
        'desc' => 'View the users on a channel'
    },
    QUIT => {
        'code' => \&handle_quit,
        'desc' => 'Leave the server'
    },
    PART => {
        'code' => \&handle_part,
        'desc' => 'Leave a channel'
    },
    REHASH => {
        'code' => \&handle_rehash,
        'desc' => 'Reload the server configuration file(s)'
    },
    LOCOPS => {
        'code' => \&handle_locops,
        'desc' => 'Send a message to all IRCops with mode S enabled'
    },
    GLOBOPS => {
        'code' => \&handle_locops,
        'desc' => 'Alias for LOCOPS'
    },
    TOPIC => {
        'code' => \&handle_topic,
        'desc' => 'View or set a channel\'s topic'
    },
    KICK => {
        'code' => \&handle_kick,
        'desc' => 'Forcibly remove a user from a channel'
    },
    INVITE => {
        'code' => \&handle_invite,
        'desc' => 'Invite a user to a channel'
    },
    LIST => {
        'code' => \&handle_list,
        'desc' => 'View channels and their information'
    },
    ISON => {
        'code' => \&handle_ison,
        'desc' => 'Check if users are on the server'
    },
    CHGHOST => {
        'code' => \&handle_chghost,
        'desc' => 'Change a user\'s visible hostname'
    },
    COMMANDS => {
        'code' => \&handle_commands,
        'desc' => 'List commands and their information'
    }
);

# register the handlers
sub get {
    user::register_handler($_, $commands{$_}{'code'}, 'core', $commands{$_}{'desc'}) foreach keys %commands;
    undef %commands;
}

### HANDLERS (see README for information of each command)

# network stats
sub handle_lusers {
    my $user = shift;
    my ($visible, $invisible) = (0, 0);
    foreach my $usr (values %user::connection) {

        # if the user has i set, mark as invisible
        if ($usr->mode('i')) {
            $invisible++
        }

        # not invisible
        else {
            $visible++
        }

    }
    my $total = $visible+$invisible;

    # there are currently x users and y invisible on z servers
    $utils::GV{'max'} = $total if $utils::GV{'max'} < $total;
    $user->numeric(251, $visible, $invisible, 1);

    # local
    $user->numeric(265, $total, $utils::GV{'max'}, $total, $utils::GV{'max'});

    # global
    $user->numeric(267, $total, $utils::GV{'max'}, $total, $utils::GV{'max'});

    return 1
}

# view message of the day
sub handle_motd {
    my $user = shift;

    # MOTD
    $user->numeric(375, conf qw/server name/);

    # as of 0.5.8, the MOTD is stored in GV.
    foreach my $line (split $/, $utils::GV{'motd'}) {
        $user->numeric(372, $line)
    }

    # end of MOTD
    $user->numeric(376);

    return
}

# change nickname
sub handle_nick {

    # such a simple task is much more complicated behind the scenes!

    my $user = shift;
    my @args = split /\s+/, shift;

    # parameter check
    if (!defined $args[1]) {
        $user->numeric(431);
        return
    }

    # I don't feel that this is necessary, but just in case...
    my $newnick = col($args[1]);

    # ignore stupid nick changes
    return if $newnick eq $user->nick;

    # check if the nick is valid
    if (!validnick($newnick, conf qw/limit nick/, undef)) {
        $user->numeric(432, $newnick);
        return
    }

    # make sure it's not taken
    if (!user::nickexists($newnick) || lc $newnick eq lc $user->nick) {

        # we have to be very careful to properly send the nick change to users in common,
        # without sending the same thing multiple times.

        # we start with only this user
        my @done = $user->{'id'};

        # check each channel first to check if the user is banned and then to send the nick
        # change to all users of the channel
        foreach my $channel (values %channel::channels) {

            # if they aren't there, don't do anything
            next unless $user->ison($channel);

            # check for bans, no exceptions, etc.
            if ($channel->banned($user)) {

                # if they have voice or greater, allow the nick change even though they're banned
                if (!$channel->canspeakwithstatus($user)) {
                    $user->numeric(345, $newnick, $channel->name);
                    return
                }

            }

            # here, we send the nick change to the users of the channel.

            foreach my $chusr (keys %{$channel->{users}}) {

                # if we already sent to them, skip them
                next if $chusr ~~ @done;

                push @done, $chusr
            }

        }

        # now that we have all of the users' IDs in an array, we can send the nick change to them.
        (user::lookupbyid($_) or next)->sendfrom($user->fullcloak, 'NICK :'.$newnick) foreach @done;

        # congratulations, you are now known as $newnick.
        $user->{'nick'} = $newnick;
        return 1

    }

    # nickname is taken >:(
    else {
        $user->numeric(433, $newnick)
    }
    return

}

# WHOIS query
sub handle_whois {

    # there is probably such thing as having *too* many comments, but meh.

    my $user = shift;
    my @args = split /\s+/, shift;
    my (@modes, @channels);

    # parameter check
    if (!defined $args[1]) {
        $user->numeric(461, 'WHOIS');
        return
    }

    # WHOIS can take a server parameter optionally
    my ($nick, $server);
    if (defined $args[2]) {
        $nick = $args[2];
        $server = $args[1];

        # make sure the server exists (nick is also acceptable)
        if ((lc $server ne lc conf qw/server name/) && (lc $server ne lc $user->nick)) {
            $user->numeric(402, $server);
            return
        }

    }

    # he only provided nick
    else {
        $nick = $args[1]
    }

    # find the user we're querying and make sure they exist
    my $target = user::nickexists($nick);
    if (!$target) {
        $user->numeric(401, $nick);
        return
    }

    $nick = $target->nick;

    # username, visible host, and real name
    $user->numeric(311, $nick, $target->{'ident'}, $target->{'cloak'}, $target->{'gecos'});

    # channels
    foreach my $channel (values %channel::channels) {
            push @channels,

            # get their prefix in the channel
            ($channel->prefix($target) ? $channel->prefix($target).$channel->name : $channel->name)
            if $target->ison($channel)

    }

    $user->numeric(319, $nick, (join q. ., @channels))

    # they're not on any channels.
    unless $#channels < 0;

    # server the user is on
    $user->numeric(312, $nick, (conf qw/server name/), (conf qw/server desc/));

    # using an SSL connection?
    $user->numeric(641, $nick) if $target->{'ssl'};

    # AWAY reason
    $user->numeric(301, $nick, $target->{'away'}) if defined $target->{'away'};

    # is an IRC operator
    $user->numeric(313, $nick)

        # (only available to opers)
        if $target->ismode('o');

    # enabled modes
    push @modes, $_ foreach keys %{$target->{'mode'}};
    $user->numeric(379, $nick, (join q.., @modes))

        # (only available to opers)
        if $user->ismode('o');

    # actual IP
    $user->numeric(378, $nick, $target->{'host'}, $target->{'ip'})

        # a user can see it if the target is not cloaked, and opers can always see it.
        if (!$user->{'mode'}->{'x'} || $user->ismode('o'));

    # idle time
    # only show it if he provided a server
    if ($server) {
        $user->numeric(317, $target->nick, (time-$target->{'idle'}), $target->{'time'})
    }

    # end of query
    $user->numeric(318, $nick);
    return 1

}

# PING request
sub handle_ping {
    my $user = shift;
    my $reason = (split /\s+/, shift, 2)[1];

    # only send a parameter if they supplied one
    $user->sendserv('PONG '.conf('server','name').(defined $reason ? q. ..$reason : q..));

    return 1
}

# setting a mode
# actual user mode handling is done by user::hmodes()
# actual channel mode handling is done by channel::handlemode()
sub handle_mode {
    my ($user, $data) = @_;
    my @args = split /\s+/, $data;

    # parameter check
    if (!defined $args[1]) {
        $user->numeric(461,'MODE');
        return
    }

    # is it a user mode?
    if (lc $args[1] eq lc $user->nick) {

        # yes it is!
        $user->hmodes($args[2]);

    }

    # nope, must be a channel mode.
    else {

        # find the channel

        if (my $target = channel::chanexists($args[2])) {
            $target->handlemode($user, (split /\s+/, $data, 3)[2]);
        }

        # no such channel
        else {
            $user->numeric(401, $args[1]);
            return
        }

    }

    # success
    return 1
}

# NOTICE and PRIVMSG
# these two are so similar that it's pointless to have two
# of the same subroutine with different names
sub handle_privmsgnotice {
    my ($user, $data) = @_;
    my @args = split /\s+/, $data;
    my $command = uc $args[0];

    # parameter check
    if (!defined $args[2]) {
        $user->numeric(461, $command);
        return
    }

    # make sure the message is at least 1 character
    my $msg = col((split q. ., $data, 3)[2]);
    if (!length $msg) {
        $user->numeric(412);
        return
    }

    # first, check for a user
    my $target = user::nickexists($args[1]);
    if ($target) {
        $target->recvprivmsg($user->fullcloak, $target->nick, $msg, $command);
        return 1
    }

    # not a user, so check for a channel
    my $channel = channel::chanexists($args[1]);
    if ($channel) {
        $channel->privmsgnotice($user, $command, $msg);
        return 1
    }

    # no such nick or channel
    $user->numeric(401, $args[1]);
    return

}

# mark as away or return from being away
sub handle_away {
    my ($user, $reason) = (shift, (split /\s+/, shift, 2)[1]);

    # if they're away, return
    if (defined $user->{'away'}) {
        $user->{'away'} = undef;
        $user->numeric(305);
        return 1
    }

    # otherwise set their away reason
    $user->{'away'} = col($reason);
    $user->numeric(306);
    return 1
}

# become an IRC operator
sub handle_oper {
    my ($user, $data) = @_;
    my @args = split /\s+/, $data;

    # parameter check
    if (defined $args[2]) {
        $user->numeric(461, 'OPER'); 
    }

    # attempt to oper
    if (my $oper = $user->canoper($args[1], $args[2])) {

        # set their cloak if the oper block has a vhost
        my $vhost = oper($oper,'vhost');
        $user->setcloak($vhost) if defined $vhost;

        # set oper-up modes
        $user->setmode('o'.(oper($oper, 'snotice') ? 'S' : q..));

        # cool
        $user->{'oper'} = $oper;
        snotice($user->fullhost." is now an IRC operator using name $oper");
        snotice("user $$user{nick} now has oper privs: ".oper($oper, 'privs'));
        return 1
    }

    # incorrect credentials!
    else {
        $user->numeric(491)
    }

    return
}

# forcibly remove a user from server
sub handle_kill {
    my ($user, $data) = @_;
    my @args = split /\s+/, $data;

    # parameter check
    if (!defined $args[2]) {
        $user->numeric(461, 'KILL');
        return
    }

    # make sure the user has kill flag
    if (!$user->can('kill')) {
        $user->numeric(481);
        return
    }

    # see if the victim exists
    if (my $target = user::nickexists($args[1])) {
        # it does, so kill it
        my $quit_string = 'Killed ('.$user->nick.' ('.col((split q. ., $data, 3)[2]).'))';
        $target->send(':'.$user->fullcloak.' QUIT :'.$quit_string);
        $target->quit($quit_string);
        return 1
    }

    # he doesn't :/
    else {
        $user->numeric(401, $args[1])
    }

    return
}

# join a channel
sub handle_join {
    my ($user, $data) = @_;
    my @args = split /\s+/, $data;

    # parameter check
    if (!defined $args[1]) {
        $user->numeric(461, 'JOIN');
        return
    }

    # channels are separated by commas.
    foreach my $channel (split q/,/, col($args[1])) {

        # if the channel exists, join
        if (my $target = channel::chanexists($channel)) {
            $target->dojoin($user)

            # unless they're already there, of course
            unless $user->ison($target);

        }

        # create a new channel if it's a valid name
        else {
            if ($channel =~ m/^#/) {
                channel::new($user, $channel)
            }

            # invalid channel name
            else {
                $user->numeric(403, $channel);
                return
            }

        }
    }

    # success
    return 1
}

# WHO query
# this is NOT the proper way to handle a WHO query,
# but it's the most commonly used by clients
sub handle_who {
    my ($user, $query) = (shift, (split /\s+/, shift)[1]);

    # if the channel exists, send them the query.
    if (my $target = channel::chanexists($query)) {
        $target->who($user)
    }

    # WHO queries never fail; they simply don't send information they don't have
    $user->numeric(315, $query);

    # always success
    return 1
}

# view users in a channel
sub handle_names {
    my $user = shift;

    # channels separated by commas
    foreach my $channel (split q/,/, (split /\s+/,shift)[1]) {

        # find the channel
        my $target = channel::chanexists($channel);

        # have channel.pm take it from here if the channel exists
        $target->names($user) if $target;

        # no such channel, but still send the end of query.
        # like WHO, NAMES never fails.
        $user->numeric(366, $channel) unless $target;

    }

    # always success
    return 1
}

# PART a channel
sub handle_part {
    my ($user, $data) = @_;
    my @args = split /\s+/, $data;

    # parameter check
    if (!defined $args[1]) {
        $user->numeric(461, 'PART');
        return
    }

    my $reason = col((split ' ', $data, 3)[2]);

    # channels separated by commas
    foreach my $chan (split q/,/, $args[1]) {

        # find the channel
        if (my $channel = channel::chanexists($chan)) {

            # make sure they're in the channel
            if (!$user->ison($channel)) {
                $user->numeric(422, $channel->name);
                return
            }

            # send the part to all users of the channel and delete the user's data in the channel
            $channel->allsend(':%s PART %s%s', 0, $user->fullcloak, $channel->name, (defined $reason ? " :$reason" : q..));
            $channel->remove($user);
            next
        }

        # no such channel
        $user->numeric(401, $chan);
        next

    }
    return 1
}

# quit from the server
sub handle_quit {
    my ($user, $reason) = (shift, col((split /\s+/, shift, 2)[1]));

    # delete the user's data
    $user->quit("Quit: $reason");

    # not much can go wrong in a quit...
    return 1

}

# reload server configuration file
sub handle_rehash {
    my $user = shift;

    # needs rehash flag
    if ($user->can('rehash')) {
        snotice($user->nick.' is rehashing server configuration file');

        # as of 0.8.*, confparse() automatically clears former values.
        main::confparse($main::CONFIG);

        return 1
    }

    # user doesn't have privs to rehash
    else {
        $user->numeric(481)
    }

    return
}

# send a notice to all operators with mode S enabled
sub handle_locops {
    my ($user, $data) = @_;
    my @args = split /\s+/, $data, 2;

    # parameter check
    if (!defined $args[1]) {
        $user->numeric(461, uc $args[0]);
        return
    }

    # either locops or globops works here; they're the same.
    if ($user->can('globops') || $user->can('locops')) {
        snotice('LOCOPS from '.$user->nick.': '.$args[1]);
        return 1
    }

    # incorrect privs
    else {
        $user->numeric(481);
    }

    return
}

# view or set a channel topic
sub handle_topic {
    my ($user, $data) = @_;
    my @args = split /\s+/, $data, 3;

    # parameter check
    if (!defined $args[1]) {
        $user->numeric(461, 'TOPIC');
        return
    }

    # find the channel
    if (my $channel = channel::chanexists($args[1])) {

        # if they gave a parameter, they probably want to set the topic
        if (defined $args[2]) {

            # limit it to the number of chars defined by limit:topic
            my $overflow = (length $args[2]) - (conf qw/limit topic/) + 1;
            my $topic = substr $args[2], 0, -$overflow if length $args[2] > conf qw/limit topic/;

            # set the topic
            $channel->settopic($user, col($topic));
            return 1

        }

        # no parameter means viewing the topic
        else {
            $channel->showtopic($user);
            return 1
        }
    }

    # no such channel
    else {
        $user->numeric(401, $args[1])
    }

    return
}

# forcibly remove user from channel
sub handle_kick {
    my($user, $data) = @_;
    my @args = split /\s+/, $data, 4;

    # not enough parameters
    if (!defined $args[2]) {
        $user->numeric(461, 'KICK');
        return
    }
    my $channel = channel::chanexists($args[1]);
    my $target = user::nickexists($args[2]);

    # no such channel or nick
    # or they aren't in this channel
    if (!$channel || !$target || !$target->ison($channel)) {
        $user->numeric(401, $args[1]);
        return
    }

    my $reason = $target->nick;
    $reason = col($args[3]) if defined $args[3];

    # give them an error for not having correct status
    $user->numeric(482.1, $channel->name) and return

    # unless it was successful
    unless $channel->kick($user, $target, $reason);

    # success!
    return 1
}

# invite a user to a channel
sub handle_invite {
    my($user, @args) = (shift,(split /\s+/, shift));
    if (!defined $args[2]) {
        $user->numeric(461,'INVITE');
        return
    }

    # find the user and the channel
    my $someone = user::nickexists($args[1]);
    my $somewhere = channel::chanexists($args[2]);

    # make sure the user exists
    if (!$someone) {
        $user->numeric(401, $args[1]);
        return
    }

    # ignore dumb invitations
    return if $someone == $user;

    # make sure the channel exists
    if (!$somewhere) {
        $user->numeric(401, $args[2]); 
        return
    }


    # make sure the user is there in the first place
    if ($user->ison($somewhere)) {

        # INVITE requires halfop and above.
        if (!$somewhere->basicstatus($user)) {
            $user->numeric(482, $somewhere->name, 'half-operator');
            return
        }

        # make sure the user isn't already there
        if ($someone->ison($somewhere)) {
            $user->numeric(433, $someone->nick, $somewhere->name);
            return 
        }

        # cool, no problems
        $somewhere->{'invites'}->{$someone->{'id'}} = time;
        $someone->sendfrom($user->nick, ' INVITE '.$someone->nick.' :'.$somewhere->name);
        $user->numeric(341, $someone->nick, $somewhere->name);
        return 1

    }

    # you have to be on a channel to invite someone to it
    else {
        $user->numeric(422, $somewhere->name)
    }

    # :(
    return

}

# view channel information
sub handle_list {
    my ($user, @args) = (shift, (split /\s+/, shift));
    $user->numeric(321);

    # if there are no arguments, give them the entire list
    if (!defined $args[1]) {
        $_->list($user) foreach values %channel::channels;
    }

    # arguments means they want info on specific channels
    # separated by commas, of course
    else {
        foreach my $chan (split q/,/, $args[1]) {

            # find the channel
            if (my $channel = channel::chanexists($chan)) {
                $channel->list($user);
            }

            # no such channel
            else {
                $user->numeric(401, $chan);
            }

        }
    }

    $user->numeric(323);
    return 1
}

# find online users
sub handle_ison {
    my ($user, @args) = (shift, (split /\s+/, shift));
    my @final = ();

    # parameter check
    if (!defined $args[1]) {
        $user->numeric(461, 'ISON');
    }

    # in ISON, nicks are separated by spaces
    foreach my $nick (@args[1..$#args]) {
        my $usr = user::nickexists($nick);
        push @final, $usr->nick if $usr
    }

    # and replied in a single numeric
    $user->numeric(303, (join q. ., @final));

    return 1
}

# change a user's displayed host
sub handle_chghost {
    my ($user, @args) = (shift, (split /\s+/, shift));
    if (!defined $args[2]) {
        $user->numeric(461, 'CHGHOST');
        return
    }
    if (!$user->can('chghost')) {
        $user->numeric(481);
        return
    }

    # check that the nickname exists

    if (my $target = user::nickexists($args[1])) {

        # make sure the host is valid
        if (validcloak($args[2])) {

            # success
            $target->setcloak($args[2]);
            snotice(sprintf '%s used CHGHOST to change %s\'s cloak to %s', $user->nick, $target->nick, $args[2]);
            $user->snt('CHGHOST', $target->nick.'\'s cloak has been changed to '.$args[2]);
            return 1

        }

        # not a valid cloak
        $user->snt('CHGHOST', 'invalid characters');

    }

    # no such nick
    else {
        $user->numeric(401, $args[1])
    }

    return
}

# view the registered command list
sub handle_commands {
    my $user = shift;

    # send a notice for each command
    while (my ($command, $cv) = each %user::commands) {
        $user->servernotice("$command [$$cv{source}] $$cv{desc}")
    }

    # always success
    return 1
}

1
