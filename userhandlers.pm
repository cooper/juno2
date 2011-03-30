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
        'code' => sub {}
    },
    SACONNECT => {
        'code' => sub {}
    },
    USER => {
        'code' => sub { shift->numeric(462) }
    },
    LUSERS => {
        'code' => \&handle_lusers
    },
    MOTD => {
        'code' => \&handle_motd
    },
    NICK => { 
        'code' => \&handle_nick
    },
    PING => {
        'code' => \&handle_ping
    },
    WHOIS => {
        'code' => \&handle_whois
    },
    MODE => {
        'code' => \&handle_mode
    },
    PRIVMSG => {
        'code' => \&handle_privmsgnotice
    },
    NOTICE => {
        'code' => \&handle_privmsgnotice
    },
    AWAY => {
        'code' => \&handle_away
    },
    OPER => {
        'code' => \&handle_oper
    },
    KILL => {
        'code' => \&handle_kill
    },
    JOIN => {
        'code' => \&handle_join
    },
    WHO => {
        'code' => \&handle_who
    },
    NAMES => {
        'code' => \&handle_names
    },
    QUIT => {
        'code' => \&handle_quit
    },
    PART => {
        'code' => \&handle_part
    },
    REHASH => {
        'code' => \&handle_rehash
    },
    LOCOPS => {
        'code' => \&handle_locops
    },
    GLOBOPS => {
        'code' => \&handle_locops
    },
    TOPIC => {
        'code' => \&handle_topic
    },
    KICK => {
        'code' => \&handle_kick
    },
    INVITE => {
        'code' => \&handle_invite
    },
    LIST => {
        'code' => \&handle_list
    },
    ISON => {
        'code' => \&handle_ison
    },
    CHGHOST => {
        'code' => \&handle_chghost
    }
);

# register the handlers
sub get {
    user::register_handler($_, $commands{$_}{'code'}) foreach keys %commands
}

# HANDLERS (see README for information of each command)

sub handle_lusers {
    my $user = shift;
    my ($i, $ii) = (0, 0);
    foreach (values %user::connection) {
        if ($_->mode('i')) {
            $ii++;
        } else { $i++; }
    } my $t = $i+$ii;

    # there are currently x users and y invisible on z servers
    $utils::GV{'max'} = $t if $utils::GV{'max'} < $t;
    $user->numeric(251, $i, $ii, 1);

    # local
    $user->numeric(265, $t, $utils::GV{'max'}, $t, $utils::GV{'max'});

    # global
    $user->numeric(267, $t, $utils::GV{'max'}, $t, $utils::GV{'max'});

    return 1
}

sub handle_motd {
    my $user = shift;
    $user->numeric(375,conf('server','name'));
    foreach my $line (split $/, $utils::GV{'motd'}) {
        $user->numeric(372,$line);
    }
    $user->numeric(376);
}

sub handle_nick {
    my $user = shift;
    my @s = split /\s+/, shift;
    if ($s[1]) {
        return if $s[1] eq $user->nick;
        if (validnick($s[1],conf('limit','nick'),undef)) {
            if(!user::nickexists($s[1]) || lc($s[1]) eq lc($user->nick)) {
                my %sent;
                my @users = $user;
                $sent{$user->{'id'}} = 1;
                foreach my $channel (values %channel::channels) {
                    if ($user->ison($channel)) {
                        if (hostmatch($user->fullcloak,keys %{$channel->{'bans'}}) || hostmatch($user->fullhost,keys %{$channel->{'bans'}}) &&
                        !hostmatch($user->fullhost,keys %{$channel->{'exempts'}})) {
                            $user->numeric(345,$s[1],$channel->name), return unless $channel->canspeakwithstatus($user);
                        }
                        $channel->check;
                        foreach (keys %{$channel->{'users'}}) {
                            next if $sent{$_};
                            push(@users,user::lookupbyid($_));
                            $sent{$_} = 1;
                        }
                    }
                }
                $_->send(':'.$user->fullcloak.' NICK :'.$s[1]) foreach @users;
                $user->{'nick'} = $s[1];
            } else { $user->numeric(433,$s[1]); }
        } else { $user->numeric(432,$s[1]); }
    } else { $user->numeric(431); }
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
    my ($user,$data) = @_;
    my @s = split /\s+/, $data;
    if (defined $s[2]) {
        if ($user->can('kill')) {
            my $target = user::nickexists($s[1]);
            if ($target) {
                my $reason = col((split /\s+/,$data,3)[2]);
                $target->quit('Killed ('.$user->nick.' ('.$reason.'))');
            } else { $user->numeric(401,$s[1]); }
        } else { $user->numeric(481); }
    } else { $user->numeric(461,'KILL'); }
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
    my($user,$data) = @_;
    my @s = split /\s+/, $data, 4;
    if (defined $s[2]) {
        my $channel = channel::chanexists($s[1]);
        my $target = user::nickexists($s[2]);
        if ($channel && $target) {
            my $reason = $target->nick;
            $reason = col($s[3]) if defined $s[3];
            $user->numeric(482,$channel->name,'half-operator') unless $channel->kick($user,$target,$reason);
        } else { $user->numeric(401,$s[1]); }
    } else { $user->numeric(461,'KICK'); }
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

1
