#!/usr/bin/perl -w
# Copyright (c) 2011, Mitchell Cooper
package user;

use warnings;
use strict;
use feature qw/say switch/;

use utils qw/col conf oper hostmatch snotice validnick validcloak/;
use userhandlers;

$utils::GV{'cid'} = 0;
$utils::GV{'max'} = 0;
our %connection;
our %commands;

# register the command handlers in userhandlers.pm
&userhandlers::get;

# main command handler
sub handle {
    my ($user, $command) = (shift, uc shift);

    if (exists $commands{$command}) {

        # call the CODE
        return $commands{$command}{'code'}($user, shift)

    }

    # unknown command
    else {
        $user->numeric(421, $command)
    }

    return
}

# create a new user
sub new {
    my ($ssl, $peer) = @_;
    return unless $peer;

    # the server is not accepting connections
    if (!&acceptcheck) {
        $peer->close;
        return
    }

    # check and make sure the IP is not Z-Lined, blacklisted, or if it has reached its max-per-IP limit
    my @ip_accept = ip_accept($peer->peerhost);
    if (!$ip_accept[0]) {

        # we can't use main::sendpeer here because the outbuffer will be cleared before the main loop gets a chance to send the data
        $peer->syswrite('ERROR :Closing Link: (*@'.$peer->peerhost.') ['.$ip_accept[1].']'."\r\n", POSIX::BUFSIZ);

        $peer->close;
        return
    }

    # add the user the IO::Select object
    $::select->add($peer);

    ::sendpeer($peer, ':'.(conf qw/server name/).' NOTICE * :*** Looking up your hostname...');
    my $ip = $peer->peerhost;
    my $ipv = ($ip =~ m/:/ ? 6 : 4);

    # create the user
    bless my $user = {
        'ssl' => $ssl,
        'server' => $::id,
        'id' => $::id.&newid,
        'obj' => $peer,
        'ip' => $ip,
        'ipv' => $ipv,
        'host' => $ip,
        'cloak' => $ip,
        'time' => time,
        'privs' => []
    };

    # set PING rate, idle time, and other timers
    handle::user_reset_timer($user, 0);

    $user->servernotice('*** Could not resolve hostname; using IP address instead');
    $connection{$peer} = $user;
    return $user
}

# this is where the actual mode setting is done; mode handling is done in hmodes()
sub setmode {
    my ($user, $modes, $silent) = @_;
    $user->send(':'.$user->nick.' MODE '.$user->nick.' :+'.$modes) unless $silent;
    foreach (split //, $modes) {
        $user->{'mode'}->{$_} = time;

        # don't do anything for these modes
        next if $_ =~ m/i/;

        if ($_ eq 'x' && conf qw/enabled cloaking/) {

            # use . for IPv4 and : for IPv6
            my $sep = ($user->{'ipv'} == 6 ? ':' : '\.');

            # set the hidden host
            $user->setcloak(host2cloak($sep, $user->{'host'}))

        }
    }
}

sub ismode {
    my ($user, $mode) = @_;
    return $user->{'mode'}->{$mode} if exists $user->{'mode'}->{$mode};
    return
}

# this is where the actual mode unsetting is done; mode handling is done in hmodes()
sub unsetmode {
    my ($user, $modes, $silent) = @_;
    $user->send(':'.$user->nick.' MODE '.$user->nick.' :-'.$modes) unless $silent;
    foreach (split //, $modes) {
        delete $user->{'mode'}->{$_};
        next if $_ =~ m/(i|S)/;
        if ($_ eq 'x' && conf qw/enabled cloaking/) {

            # restore the original cloak
            $user->unsetcloak;

        }
        elsif ($_ eq 'o') {

            # remove all privs
            $user->{privs} = [];

            # unset server notices if set
            $user->unsetmode('S') if $user->ismode('S');

        }
    }
}

sub hmodes {
    my ($user, $modes) = @_;
    return unless $modes;

    # modes that always exist, whether or not a feature is enabled or disabled
    my @enabled_modes = 'i';

    push @enabled_modes, 'x' if conf qw/enabled cloaking/;
    my $state = 1;
    foreach my $piece (split //, $modes) {
        given ($piece) {
            when ('+') {
                $state = 1
            }
            when ('-') {
                $state = 0
            }

            # modes that cannot be set or unset
            when ('Z') {
                next
            }

            # oper-only modes
            when (/(o|S)/) {
                if ($user->ismode('o')) {
                    if ($state) {
                        $user->setmode($piece)
                    }
                    else {
                        $user->unsetmode($piece)
                    }
                }
                # otherwise just ignore it
            }

            # normal modes
            when ($_ ~~ @enabled_modes) {
                if ($state) {
                    $user->setmode($piece)
                }
                else {
                    $user->unsetmode($piece)
                }
            }

            # unknown mode
            default {
                $user->numeric(501, $piece)
            }

        }
    }
}

# set the displayed host of a user
sub setcloak {
    my ($user, $cloak) = @_;
    $user->numeric(396, $cloak);
    $user->{'cloak'} = $cloak;
    return $cloak
}

# create an SHA cloak of a host
sub host2cloak {
    my @pieces = ();
    my $sep = shift;
    foreach (split $sep, shift) {
        my $part = sha1_hex($_, (conf qw/cloak salt/), $#pieces);

        # create six-character section
        $part = ($part =~ m/....../g)[0];

        push @pieces, $part;
    }

    # since split requires . to be escaped
    $sep = '.' if $sep eq '\.';

    return (join $sep, @pieces)
}

# restore original host
sub unsetcloak {
    my $user = shift;
    $user->numeric(396, $user->host);
    $user->{'cloak'} = $user->host;
    return $user->host
}

# find a user by their socket object
sub lookup {
    my $peer = shift;
    return $connection{$peer} if exists $connection{$peer};

    # no such user
    return
}

# send data
sub send {
    return ::sendpeer(shift->obj, @_)
}

# check for an oper flag
sub can {
    my ($user, $priv) = @_;

    return 1 if $priv ~~ @{$user->{privs}};

    # they don't have that priv
    return

}

# user quit
sub quit {
    my ($user, $reason, $silent, $display) = @_;

    # relay the quit to all users in a common channel, but only once.
    my %sent;
    foreach my $channel (values %channel::channels) {
        if ($user->ison($channel)) {
            foreach (keys %{$channel->{'users'}}) {
                lookupbyid($_)->send(':'.$user->fullcloak.' QUIT :'.($display ? $display : $reason)) unless $sent{$_};
                $sent{$_} = 1
            }

        }

        # remove the user from the channel
        # this has to be outside of the ison() because some data (such as invites) do not require that the user is in the channel
        $channel->remove($user)
    }

    snotice('client exiting: '.$user->fullhost.' ['.$user->{'ip'}.'] ('.$reason.')') if $user->{'ready'};

    # we can't use main::sendpeer here because the outbuffer will be cleared before the main loop gets a chance to send the data
    $user->obj->syswrite('ERROR :Closing Link: ('.(defined $user->{'ident'}?$user->{'ident'}:'*').'@'.$user->host.') ['.$reason.']'."\r\n", POSIX::BUFSIZ) unless $silent;

    # delete their data
    delete $connection{$user->obj};
    delete $::outbuffer{$user->obj};
    delete $::timer{$user->obj};

    # remove the user from the IO::Select object and close the socket
    $::select->remove($user->obj);
    $user->obj->close;

    undef $user;

    # double-check if the server is ready to accept new connections
    &acceptcheck;

    return 1
}

# send a NOTICE from the server
# :server NOTICE nick :message
sub servernotice {
    my $user = shift;
    return $user->send(':'.(conf qw/server name/).' NOTICE '.$user->nick." :@_")
}

# server notice for a command such as CHGHOST
sub snt {
    return shift->servernotice(sprintf '*** %s: %s', shift, shift)
}

# send a numeric
# deprecated; use numeric() instead.
# (this is still used in the start() function as those numerics are only used once,
# or at least until the VERSION command is complete.)
sub sendnum {
    my $user = shift;
    return $user->send(':'.(conf qw/server name/).' '.shift().' '.$user->nick." @_")
}

# new way to send a numeric
# numerics are defined in the %utils::numerics hash
# a single numeric can have multiple strings since int() is used.
sub numeric {
    my ($user, $num) = (shift, shift);
    return $user->send(join q. ., ':'.(conf qw/server name/), (int $num), $user->nick, (sprintf $utils::numerics{$num}, @_))
}

# send data from the server
sub sendserv {
    return shift->send(':'.(conf qw/server name/).' '.(sprintf shift, @_))
}

# send from the server, join()ing the arguments by a space
sub sendservj {
    return shift->send(':'.(conf qw/server name/).' '.(join q. ., @_))
}

# send data from a server or user
sub sendfrom {
    return shift->send(':'.shift().' '.(sprintf shift, @_))
}

# send from a server or user, using join(' ') for each argument
sub sendfromj {
    return shift->send(':'.shift().' '.(join q. ., @_))
}

# the entire mask, using the displayed host
sub fullcloak {
    my $user = shift;
    return $user->{'nick'}.'!'.$user->{'ident'}.'@'.$user->{'cloak'} if $user->{'ready'};
    return '*'
}

# sends a privmsg to a user
# who knows why this has its own function? it's only used once...
sub recvprivmsg {
    my ($user, $from, $target, $msg, $cmd) = @_;
    return $user->send(':'.(join q. ., $from, $cmd, $target).' :'.$msg)
}

# look for a usermode set on the user
sub mode {
    my ($user, $mode) = @_;

    # found it
    return $user->{'mode'}->{$mode} if exists $user->{'mode'}->{$mode};

    # doesn't have mode set
    return

}

# the entire mask, using the actual host
sub fullhost {
    my $user = shift;
    return $user->{'nick'}.'!'.$user->{'ident'}.'@'.$user->{'host'} if defined $user->{'ready'};
    return '*'
}

# user's nick
sub nick {
    my $user = shift;
    return $user->{'nick'} if $user->{'nick'};
    return '*'
}

# called by handle.pm after the user registers
sub start {
    my $user = shift;
    return if $user->checkkline;
    snotice('client connecting: '.$user->fullhost.' ['.$user->{'ip'}.']');
    $user->sendnum('001', ':Welcome to the '.(conf qw/server network/).' Internet Relay Chat Network '.$user->nick);
    $user->sendnum('002', ':Your host is '.(conf qw/server name/).', running version juno-'.$::VERSION);
    $user->sendnum('003', ':This server was created '.POSIX::strftime('%a %b %d %Y at %H:%M:%S %Z',localtime $::TIME));
    $user->sendnum('004', (conf qw/server name/).' juno-'.$::VERSION.' SZiox AIZbelimntz');
    $user->sendnum('005', 'CHANTYPES=# EXCEPTS INVEX CHANMODES=AeIbZ,,l,imntz PREFIX=(qaohv)~&@%+ NETWORK='.(conf qw/server network/).' MODES='.(conf qw/limit chanmodes/).' NICKLEN='.(conf qw/limit nick/).' TOPICLEN='.(conf qw/limit topic/).' :are supported by this server');

    # make the server think the user sent these commands
    userhandlers::handle_lusers($user);
    userhandlers::handle_motd($user);

    # set automatic modes as defined in the configuration
    $user->setmode((conf qw/user automodes/).($user->{'ssl'}?'Z':''));

    return 1
}

# a new user ID (ID, not UID)
sub newid {
    $utils::GV{'cid'}++;
    return $utils::GV{'cid'}-1
}

# the user's UID
sub id {
    return shift->{'id'}
}

# the user's IO::Socket object
sub obj {
    return shift->{'obj'}
}

# the ID of the server the user is on
sub server {
    return shift->{'server'}
}

# user's acutal host
sub host {
    return shift->{'host'}
}

# check if a nickname exists and return that user's object if it does
sub nickexists {
    my $nick = shift;
    foreach (values %connection) {

        # found a match
        return $_ if lc $_->{'nick'} eq lc $nick

    }

    # no such nick
    return

}

# find a user by their UID
sub lookupbyid {
    my $id = shift;
    foreach (values %connection) {
        # found a match
        return $_ if $_->{'id'} == $id
    }

    # no such UID
    return

}

# check if a user has correct oper credentials
# TODO: add support for SHA encryption.
sub canoper {
    my ($user, $oper, $password) = @_;
    return unless exists $::oper{$oper};

    # check if the password is correct
    if (oper($oper, 'password') eq crypt($password, oper($oper, 'salt'))) {

                # check if the mask is correct
                return $oper if hostmatch($user->fullhost, (split / /, oper($oper, 'host')))

    }

    # invalid credentials
    return

}

# check if a user is on a channel (by objects, not names)
sub ison {
    my ($user, $channel) = @_;
    return 1 if exists $channel->{'users'}->{$user->{'id'}};
    return
}

# check if the user's mask matches a K-Line in the configuration
# if it does, force them to quit
sub checkkline {
    my $user = shift;
    foreach (keys %::kline) {
        if (hostmatch($user->fullhost, $_)) {
            # found a match; forcing them to quit
            $user->quit('K-Lined: '.$::kline{$_}{'reason'}, undef, 'K-Lined'.((conf qw/main showkline/) ? ': '.$::kline{$_}{'reason'}:''));
            return 1
        }
    }

    # they're free to go
    return

}

# ensure that the server is accepting connections
sub acceptcheck {
    my $i = scalar keys %connection;

    # maximum client count reached
    if ($i == conf qw/limit clients/) {
        snotice('No new clients are being accepted. ('.$i.' users)') if $::ACCEPTING != 0;
        $::ACCEPTING = 0;
        return

    }

    # person(s) quit; accepting clients again
    else {
        snotice('Clients are now being accepted. ('.$i.' users)') if $::ACCEPTING != 1;
        $::ACCEPTING = 1;
        return 1
    }

}

# make sure the max-per-ip limit has not been reached and that the IP is not zlined.
sub ip_accept {
    my $ip = shift;
    my $count = 0;
    foreach (values %connection) {
        $count++ if $_->{'ip'} eq $ip
    }

    # limit reached
    return (undef, 'Too many connections from this host') if $count >= conf qw/limit perip/;

    foreach (keys %::zline) {
            # IP matches a Z-Line in the configuration
            return (undef, 'Z-Lined: '.$::zline{$_}{'reason'}) if hostmatch($ip, $_)
    }

    # they're free to go
    return 1

}

# import the selected encrypting
sub DigestImport {
    say '        Importing SHA1 support to cloaking module';
    Digest::SHA->import('sha1_hex')
}

# add a command handler
# do NOT call this from an API module.
# see API::Command to do that.
sub register_handler {
    my ($handler, $code, $source, $desc) = (uc shift, shift, shift, shift);
    if (exists $commands{$handler}) {

        # command already exists
        say 'register_handler failed; '.$handler.' already exists.';
        return

    }

    # success
    $commands{$handler} = {
        'code' => $code,
        'desc' => $desc,
        'source' => $source
    };
    say $source.' registered handler '.$handler.': '.$desc;
    return 1

}

# delete a command handler
sub delete_handler {
    
    my $command = uc shift;

    # if it exists, delete it
    if (exists $commands{$command}) {
        delete $commands{$command};
        return 1
    }

    # it doesn't
    say 'delete_handler failed; '.$command.' does not exist.';
    return

}

# add oper privs
sub add_privs {
    my $user = shift;

    # set o if not opered
    $user->setmode('o') unless scalar @{$user->{privs}};

    foreach my $priv (@_) {

        # already has it
        next if $priv ~~ @{$user->{privs}};

        # doesn't have it
        push @{$user->{privs}}, $priv

    }

    return 1
}

sub del_privs {
    my $user = shift;
    my @finished;

    foreach my $priv (@{$user->{privs}}) {
        next if $priv ~~ @_;
        push @finished, $priv
    }

    $user->{privs} = [@finished];

    # check if they are still opered just in case
    $user->unsetmode('o') unless scalar @{$user->{privs}};

    return 1
}

1
