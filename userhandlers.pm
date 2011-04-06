#!/usr/bin/perl -w
# Copyright (c) 2011, Mitchell Cooper
# this is messy; I'm working on it.
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
    my ($i, $ii) = (0, 0);
    foreach my $usr (values %user::connection) {

        # if the user has i set, mark as invisible
        if ($usr->mode('i')) {
            $ii++
        }

        # not invisible
        else {
            $i++
        }

    }
    my $t = $i+$ii;

    # there are currently x users and y invisible on z servers
    $utils::GV{'max'} = $t if $utils::GV{'max'} < $t;
    $user->numeric(251, $i, $ii, 1);

    # local
    $user->numeric(265, $t, $utils::GV{'max'}, $t, $utils::GV{'max'});

    # global
    $user->numeric(267, $t, $utils::GV{'max'}, $t, $utils::GV{'max'});

    return 1
}

# view message of the day
sub handle_motd {
    my $user = shift;
    $user->numeric(375, conf qw/server name/);
    foreach my $line (split $/, $utils::GV{'motd'}) {
        $user->numeric(372,$line);
    }
    $user->numeric(376);
}

# change nickname
sub handle_nick {

    # such a simple task is much more complicated behind the scenes!

    my $user = shift;
    my @s = split /\s+/, shift;

    # parameter check
    if (!defined $s[1]) {
        $user->numeric(431);
        return
    }

    # I don't feel that this is necessary, but just in case...
    my $newnick = col($s[1]);

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
        (user::lookupbyid($_) or next)->sendfrom($user->nick, 'NICK :'.$newnick) foreach @done;

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

sub handle_whois {
    my $user = shift;
    my $nick = (split /\s+/, shift)[1];
    my $modes = '';
    if ($nick) {
        my $target = user::nickexists($nick);
        if ($target) {
            $modes .= $_ foreach (keys %{$target->{'mode'}});
            $user->numeric(311,$target->nick,$target->{'ident'},$target->{'cloak'},$target->{'gecos'});
            my @channels = ();
            foreach my $channel (values %channel::channels) {
                if ($user->ison($channel)) {
                    push @channels, ($channel->prefix($user) ? $channel->prefix($user).$channel->name : $channel->name);
                }
            }
            $user->numeric(319,$target->nick,(join ' ', @channels)) unless $#channels < 0;
            $user->numeric(312,$target->nick,conf('server','name'),conf('server','desc'));
            $user->numeric(641,$target->nick) if $target->{'ssl'};
            $user->numeric(301,$target->nick,$target->{'away'}) if defined $target->{'away'};
            $user->numeric(313,$target->nick) if $target->ismode('o');
            $user->numeric(379,$target->nick,$modes) if $user->ismode('o');
            $user->numeric(378,$target->nick,$target->{'host'},$target->{'ip'}) if (!$user->{'mode'}->{'x'} || $user->ismode('o'));
            $user->numeric(317,$target->nick,(time-$target->{'idle'}),$target->{'time'});
        } else {
            $user->numeric(401,$nick);
        }
        $user->numeric(318,$nick);
    } else { $user->numeric(461,'WHOIS'); }
}

sub handle_ping {
    my $user = shift;
    my $reason = (split /\s+/, shift, 2)[1];
    $user->sendserv('PONG '.conf('server','name').(defined $reason?' '.$reason:''));
}

sub handle_mode {
    my ($user,$data) = @_;
    my @s = split /\s+/, $data;
    if (defined($s[1])) {
        if (lc($s[1]) eq lc($user->nick)) {
            $user->hmodes($s[2]);
        } else {
            my $target = channel::chanexists($s[1]);
            if ($target) {
                $target->handlemode($user,(split /\s+/, $data, 3)[2]);
            } else {
                $user->numeric(401,$s[1]);
            }
        }
    } else { $user->numeric(461,'MODE'); }
}

sub handle_privmsgnotice {
    my ($user, $data) = @_;
    my ($n, @s) = (0, (split /\s+/, $data));
    $n = 1 if uc $s[0] eq 'NOTICE';
    if (!defined $s[2]) {
        $user->numeric(461,$n?'NOTICE':'PRIVMSG');
        return
    }
    my $target = user::nickexists($s[1]);
    my $channel = channel::chanexists($s[1]);
    my $msg = col((split /\s+/, $data, 3)[2]);
    if (!length $msg) {
        $user->numeric(412);
        return
    }
    if ($target) {
        $target->recvprivmsg($user->fullcloak,$target->nick,$msg,($n?'NOTICE':'PRIVMSG'));
    } elsif ($channel) {
        $channel->privmsgnotice($user,($n?'NOTICE':'PRIVMSG'),$msg);
    } else {
        $user->numeric(401,$s[1]);
    }
}

sub handle_away {
    my ($user,$reason) = (shift,(split /\s+/, shift, 2)[1]);
    if (defined $user->{'away'}) {
        $user->{'away'} = undef;
        $user->numeric(305);
        return;
    }
    $user->{'away'} = col($reason);
    $user->numeric(306);
}

sub handle_oper {
    my ($user,$data) = @_;
    my @s = split /\s+/, $data;
    if (defined $s[2]) {
        my $oper = $user->canoper($s[1],$s[2]);
        if ($oper) {
            $user->{'oper'} = $oper;
            my $vhost = oper($oper,'vhost');
            $user->setcloak($vhost) if defined $vhost;
            $user->setmode('o'.(oper($oper,'snotice')?'S':''));
            snotice($user->fullhost.' is now an IRC operator using name '.$oper);
            snotice('user '.$user->nick.' now has oper privs: '.oper($oper,'privs'));
        } else { $user->numeric(491); }
    } else { $user->numeric(461,'OPER'); }
}

sub handle_kill {
    my ($user, $data) = @_;
    my @s = split /\s+/, $data;

    # parameter check
    if (!defined $s[2]) {
        $user->numeric(461, 'KILL');
        return
    }

    # make sure the user has kill flag
    if (!$user->can('kill')) {
        $user->numeric(481);
        return
    }

    # see if the victim exists
    if (my $target = user::nickexists($s[1])) {
        # it does, so kill it
        my $quit_string = 'Killed ('.$user->nick.' ('.col((split /\s+/,$data,3)[2]).'))';
        $target->send(':'.$user->fullcloak.' QUIT :'.$quit_string);
        $target->quit($quit_string);
    }

    # if it doesn't, so give the user an error
    else {
        $user->numeric(401, $s[1]);
        return
    }
}

sub handle_join {
    my ($user,$data) = @_;
    my @s = split /\s+/, $data;
    if (defined($s[1])) {
        $s[1] = col($s[1]);
        foreach(split ',', $s[1]) {
            my $target = channel::chanexists($_);
            if ($target) {
                $target->dojoin($user) unless $user->ison($target);
            } else {
                if ($_ =~ m/^#/) {
                    channel::new($user,$_);
                } else {
                    $user->numeric(403,$_);
                }
            }
        }
    } else { $user->numeric(461,'JOIN'); }
}

sub handle_who {
    my ($user,$query) = (shift,(split /\s+/,shift)[1]);
    my $target = channel::chanexists($query);
    if ($target) {
        $target->who($user);
    }
    $user->numeric(315,$query);
}

sub handle_names {
    my $user = shift;
    foreach (split ',', (split /\s+/,shift)[1]) {
        my $target = channel::chanexists($_);
        $target->names($user) if $target;
        $user->numeric(366,$_) unless $target;
    }
}

sub handle_part {
    my ($user,$data) = @_;
    my @s = split /\s+/, $data;
    my $reason = col((split /\s+/, $data,3)[2]);
    if ($s[1]) {
        foreach (split ',', $s[1]) {
            my $channel = channel::chanexists($_);
            if ($channel) {
                if ($user->ison($channel)) {
                    $channel->allsend(':%s PART %s%s',0,$user->fullcloak,$channel->name,(defined $reason?' :'.$reason:''));
                    $channel->remove($user);
                } else { $user->numeric(422,$channel->name); }
            } else {
                $user->numeric(401,$_);
            }
        }
    } else { $user->numeric(461,'PART'); }
}

sub handle_quit {
    my ($user,$reason) = (shift,col((split /\s+/, shift, 2)[1]));
    $user->quit('Quit: '.$reason);
}

sub handle_rehash {
    my $user = shift;
    if ($user->can('rehash')) {
        undef %::config;
        undef %::oper;
        undef %::kline;
        snotice($user->nick.' is rehashing server configuration file');
        ::confparse($::CONFIG);
    } else {
        $user->numeric(481);
    }
}

sub handle_locops {
    my ($user, $data) = @_;
    my @s = split /\s+/, $data, 2;
    if (defined $s[1]) {
        if ($user->can('globops') || $user->can('locops')) {
            my @s = split /\s+/, $data, 2;
            snotice('LOCOPS from '.$user->nick.': '.$s[1]);
            return 1
        } else {
            $user->numeric(481)
        }
    } else {
        $user->numeric(461,uc $s[0])
    }
}

sub handle_topic {
    my ($user,$data) = @_;
    my @s = split /\s+/, $data, 3;
    if (defined $s[1]) {
        my $channel = channel::chanexists($s[1]);
        if ($channel) {
            if (defined $s[2]) {
                $s[2] = substr($s[2],0,-(length($s[2])-(conf('limit','topic')+1))) if (length $s[2] > conf('limit','topic'));
                $channel->settopic($user,col($s[2]));
            } else {
                $channel->showtopic($user);
            }
        } else { $user->numeric(401,$s[1]); }
    } else {
        $user->numeric(461,'TOPIC');
    }
}

sub handle_kick {
    my($user, $data) = @_;
    my @s = split /\s+/, $data, 4;

    # not enough parameters
    if (!defined $s[2]) {
        $user->numeric(461, 'KICK');
        return
    }
    my $channel = channel::chanexists($s[1]);
    my $target = user::nickexists($s[2]);

    # no such channel or nick
    # or they aren't in this channel
    if (!$channel || !$target || !$target->ison($channel)) {
        $user->numeric(401, $s[1]);
        return
    }

    my $reason = $target->nick;
    $reason = col($s[3]) if defined $s[3];

    # give them an error for not having correct status
    $user->numeric(482.1, $channel->name) and return

    # unless it was successful
    unless $channel->kick($user, $target, $reason);

    # success!
    return 1
}

sub handle_invite {
    my($user,@s) = (shift,(split /\s+/, shift));
    if (defined $s[2]) {
        my $someone = user::nickexists($s[1]);
        my $somewhere = channel::chanexists($s[2]);
        if (!$someone) {
            $user->numeric(401,$s[1]);
            return
        }
        return if $someone == $user;
        if (!$somewhere) {
            $user->numeric(401,$s[2]); 
            return
        }
        if (!$user->ison($somewhere)) {
            $user->numeric(422,$somewhere->name);
            return
        }
        if (!$somewhere->basicstatus($user)) {
            $user->numeric(482,$somewhere->name,'half-operator');
            return
        }
        if ($someone->ison($somewhere)) {
            $user->numeric(433,$someone->nick,$somewhere->name);
            return
        }
        $somewhere->{'invites'}->{$someone->{'id'}} = time;
        $someone->sendfrom($user->nick,' INVITE '.$someone->nick.' :'.$somewhere->name);
        $user->numeric(341,$someone->nick,$somewhere->name)
    } else {
        $user->numeric(461,'INVITE')
    }
}

sub handle_list {
    my($user,@s) = (shift, (split /\s+/, shift));
    $user->numeric(321);
    if ($s[1]) {
        foreach (split ',', $s[1]) {
            my $channel = channel::chanexists($_);
            if ($channel) {
                $channel->list($user);
            } else {
                $user->numeric(401,$_);
            }
        }
    } else {
        $_->list($user) foreach values %channel::channels;
    }
    $user->numeric(323);
}

sub handle_ison {
    my($user,@s,@final) = (shift, (split /\s+/, shift), ());
    if (defined $s[1]) {
        foreach (@s[1..$#s]) {
            my $u = user::nickexists($_);
            push @final, $u->nick if $u;
        }
        $user->numeric(303,(join ' ', @final));
    } else {
        $user->numeric(461,'ISON');
    }
}

sub handle_chghost {
    my ($user, @s) = (shift, (split /\s+/, shift));
    if (!defined $s[2]) {
        $user->numeric(461, 'CHGHOST');
        return
    }
    if (!$user->can('chghost')) {
        $user->numeric(481);
        return
    }
    my $target = user::nickexists($s[1]);
    if ($target) {
        if (validcloak($s[2])) {
            snotice(sprintf '%s used CHGHOST to change %s\'s cloak to %s', $user->nick, $target->nick, $s[2]);
            $target->setcloak($s[2]);
            $user->snt('CHGHOST', $target->nick.'\'s cloak has been changed to '.$s[2]);
            return 1
        } else {
            $user->snt('CHGHOST', 'invalid characters');
        }
    } else {
        $user->numeric(401, $s[1]);
    }
}

sub handle_commands {
    my $user = shift;
    while (my ($command, $cv) = each %user::commands) {
        $user->servernotice($cv->{'source'}.q(.).$command.': '.$cv->{'desc'})
    }
    return 1
}

1
