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

sub handle {
    # main command handler
    my ($user, $command) = (shift, uc shift);
    if (exists $commands{$command}) {
        # call to the CODE ref
        $commands{$command}{'code'}($user, shift)
    } else {
        # unknown command
        $user->numeric(421, $command)
    }
}

sub new {
    my ($ssl, $peer) = @_;
    return unless $peer;
    if (!&acceptcheck) {
        # the server is not accepting connections
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

    ::sendpeer($peer, ':'.conf('server','name').' NOTICE * :*** Looking up your hostname...');
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
        'time' => time
    };

    # set PING rate, idle time, and other timers
    handle::user_reset_timer($user, 0);

    $user->servernotice('*** Could not resolve hostname; using IP address instead');
    $connection{$peer} = $user;
    return $user
}

sub setmode {
    # this is where the actual mode setting is done; mode handling is done in hmodes()
    my ($user, $modes, $silent) = @_;
    $user->send(':'.$user->nick.' MODE '.$user->nick.' :+'.$modes) unless $silent;
    foreach (split //, $modes) {
        $user->{'mode'}->{$_} = time;
        next if $_ =~ m/i/;
        if ($_ eq 'x' && conf('enabled','cloaking')) {
            # use . for IPv4 and : for IPv6
            my $sep = ($user->{'ipv'} == 6 ? ':' : '\.');

            # set the hidden host
            $user->setcloak(host2cloak($sep, $user->{'host'}));
        }
    }
}

sub ismode {
    my ($user, $mode) = @_;
    return $user->{'mode'}->{$mode} if exists $user->{'mode'}->{$mode};
    return
}

sub unsetmode {
    # once again, this is where the actual mode unsetting is done; mode handling is done in hmodes()
    my ($user, $modes, $silent) = @_;
    $user->send(':'.$user->nick.' MODE '.$user->nick.' :-'.$modes) unless $silent;
    foreach (split //, $modes) {
        delete $user->{'mode'}->{$_};
        next if $_ =~ m/(i|S)/;
        if ($_ eq 'x' && conf('enabled', 'cloaking')) {
            # restore the original cloak
            $user->unsetcloak;
        } elsif ($_ eq 'o') {
            # delete the user's IRCop
            delete $user->{'oper'};

            # unset server notices if set
            $user->unsetmode('S') if $user->ismode('S');
        }
    }
}

sub hmodes {
    my ($user,$modes) = @_;
    return unless $modes;

    # modes that always exist, whether or not a feature is enabled or disabled
    my @enabled_modes = 'i';

    push @enabled_modes, 'x' if conf('enabled', 'cloaking');
    my $state = 1;
    foreach my $piece (split //, $modes) {
        given ($piece) {
            when ('+') {
                $state = 1
            } when ('-') {
                $state = 0
            } when ('Z') {
                # modes that cannot be set or unset
                next
            } when (/(o|S)/) {
                # oper-only modes
                if ($user->ismode('o')) {
                    if ($state) {
                        $user->setmode($piece)
                    } else {
                        $user->unsetmode($piece)
                    }
                }
                # otherwise just ignore it
            } when ($_ ~~ @enabled_modes) {
                # modes that actually exist!
                if ($state) {
                    $user->setmode($piece)
                } else {
                    $user->unsetmode($piece)
                }
            } default {
                # unknown mode
                $user->numeric(501, $piece)
            }
        }
    }
}

sub setcloak {
    my ($user, $cloak) = @_;
    $user->numeric(396, $cloak);
    $user->{'cloak'} = $cloak;
    return $cloak
}

sub host2cloak {
    my @pieces = ();
    my $sep = shift;
    foreach (split $sep, shift) {
        my $part = sha1_hex($_, conf('cloak', 'salt'), $#pieces);

        # create six-character section
        $part = ($part =~ m/....../g)[0];

        push @pieces, $part;
    }

    # since split requires . to be escaped
    $sep = '.' if $sep eq '\.';

    return (join $sep, @pieces)
}

sub unsetcloak {
    # restore a user's original host
    my $user = shift;
    $user->numeric(396, $user->host);
    $user->{'cloak'} = $user->host;
    return $user->host
}

sub lookup {
    my $peer = shift;
    return $connection{$peer} if exists $connection{$peer};

    # no such user
    return
}

sub send {
    ::sendpeer(shift->obj, @_)
}

sub can {
    # check for an oper flag
    my ($user, $priv) = @_;
    return unless defined $user->{'oper'};
    foreach (split / /, oper($user->{'oper'}, 'privs')) {
        return 1 if $_ eq $priv;
    }

    # they don't have that priv
    return
}
sub quit {
    my ($user, $reason, $silent, $display) = @_;

    # relay the quit to all users in a common channel, but only once.
    my %sent;
    foreach my $channel (values %channel::channels) {
        if ($user->ison($channel)) {
            foreach (keys %{$channel->{'users'}}) {
                lookupbyid($_)->send(':'.$user->fullcloak.' QUIT :'.($display?$display:$reason)) unless $sent{$_};
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
    &acceptcheck
}
sub servernotice {
    # send a NOTICE from the server
    # :server NOTICE nick :message
    my $user = shift;
    $user->send(':'.conf('server','name').' NOTICE '.$user->nick." :@_");
}

sub snt {
    # server notice for a command such as CHGHOST
    shift->servernotice(sprintf '*** %s: %s', shift, shift)
}

sub sendnum {
    # deprecated; use numeric() instead.
    # (this is still used in the start() function as those numerics are only used once,
    # or at least until the VERSION command is complete.)
    my $user = shift;
    $user->send(':'.conf('server','name').' '.shift().' '.$user->nick." @_")
}

sub numeric {
    # send a numeric
    # numerics are defined in the %numerics hash
    my ($user, $num) = (shift, shift);
    $user->send(join q. ., ':'.conf('server', 'name'), (int $num), $user->nick, (sprintf $utils::numerics{$num}, @_))
}

sub sendserv {
    # send from the server
    # :server data
    shift->send(':'.conf('server','name').' '.(sprintf shift, @_))
}

sub sendservj {
    # send from the server, using join(' ') for each argument
    shift->send(':'.conf('server','name').' '.(join q. ., @_))
}

sub sendfrom {
    # send from a server or user
    shift->send(':'.shift().' '.(sprintf shift, @_))
}

sub sendfromj {
    # send from a server or user, using join(' ') for each argument
    shift->send(':'.shift().' '.(join q. ., @_))
}

sub fullcloak {
    # the entire mask, using the displayed host
    my $user = shift;
    return $user->{'nick'}.'!'.$user->{'ident'}.'@'.$user->{'cloak'} if $user->{'ready'};
    return '*'
}

sub recvprivmsg {
    # who knows why this has its own function? it's only used once...
    my ($user,$from,$target,$msg,$cmd) = @_;
    $user->send(':'.(join q. ., $from, $cmd, $target).' :'.$msg)
}

sub mode {
    # look for a usermode set on the user
    my ($user, $mode) = @_;

    # found one
    return $user->{'mode'}->{$mode} if exists $user->{'mode'}->{$mode};

    # doesn't exit
    return
}

sub fullhost {
    # the entire mask, using the actual host
    my $user = shift;
    return $user->{'nick'}.'!'.$user->{'ident'}.'@'.$user->{'host'} if defined $user->{'ready'};
    return '*'
}

sub nick {
    # user's nick or * if they haven't registered
    my $user = shift;
    return $user->{'nick'} if $user->{'nick'};
    return '*'
}

sub start {
    # called by handle.pm after the user registers
    my $user = shift;
    return if $user->checkkline;
    snotice('client connecting: '.$user->fullhost.' ['.$user->{'ip'}.']');
    $user->sendnum('001',':Welcome to the '.conf('server','network').' Internet Relay Chat Network '.$user->nick);
    $user->sendnum('002',':Your host is '.conf('server','name').', running version juno-'.$::VERSION);
    $user->sendnum('003',':This server was created '.POSIX::strftime('%a %b %d %Y at %H:%M:%S %Z',localtime $::TIME));
    $user->sendnum('004',conf('server','name').' juno-'.$::VERSION.' ix o bei');
    $user->sendnum('005','CHANTYPES=# EXCEPTS INVEX CHANMODES=AeIbZ,,l,imntz PREFIX=(qaohv)~&@%+ NETWORK='.conf('server','network').' MODES='.conf('limit','chanmodes').' NICKLEN='.conf('limit','nick').' TOPICLEN='.conf('limit','topic').' :are supported by this server');

    # make the server think the user sent these commands
    userhandlers::handle_lusers($user);
    userhandlers::handle_motd($user);

    # set automatic modes as defined in the configuration
    $user->setmode(conf('user','automodes').($user->{'ssl'}?'Z':''));

    return 1
}

sub newid {
    # a new ID
    $utils::GV{'cid'}++;
    return $utils::GV{'cid'}-1
}

sub id {
    # the user's UID
    return shift->{'id'}
}

sub obj {
    # the user's IO::Socket object
    return shift->{'obj'}
}

sub server {
    # the ID of the server the user is on
    return shift->{'server'}
}

sub host {
    # user's acutal host
    return shift->{'host'}
}

sub nickexists {
    # check if a nickname exists and return that user's object if it does
    my $nick = shift;
    foreach (values %connection) {
        # found a match
        return $_ if lc $_->{'nick'} eq lc $nick
    }

    # no such nick
    return    
}

sub lookupbyid {
    # find a user by their UID
    my $id = shift;
    foreach (values %connection) {
        # found a match
        return $_ if $_->{'id'} == $id
    }

    # no such UID
    return 
}

sub canoper {
    # check if a user has correct oper credentials
    # TODO: add support for SHA encryption.
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

sub ison {
    # check if a user is on a channel (by objects, not names)
    my ($user, $channel) = @_;
    return 1 if exists $channel->{'users'}->{$user->{'id'}};
    return
}

sub checkkline {
    # check if the user's mask matches a K-Line in the configuration
    my $user = shift;
    foreach (keys %::kline) {
        if (hostmatch($user->fullhost,$_)) {
            # found a match; forcing them to quit
            $user->quit('K-Lined: '.$::kline{$_}{'reason'}, undef, 'K-Lined'.(conf('main', 'showkline')?': '.$::kline{$_}{'reason'}:''));
            return 1
        }
    }

    # they're free to go
    return
}

sub acceptcheck {
    # ensure that the server is accepting connections
    my $i = 0;
    $i++ foreach (values %connection);
    if ($i == conf('limit','clients')) {
        # maximum client count reached
        snotice('No new clients are being accepted. ('.$i.' users)') if $::ACCEPTING != 0;
        $::ACCEPTING = 0;
        return
    } else {
        # person(s) quit; accepting clients again
        snotice('Clients are now being accepted. ('.$i.' users)') if $::ACCEPTING != 1;
        $::ACCEPTING = 1;
        return 1
    }
}

sub ip_accept {
    # make sure the max-per-ip limit has not been reached and that the IP is not zlined.
    my $ip = shift;
    my $count = 0;
    foreach (values %connection) {
        $count++ if $_->{'ip'} eq $ip
    }

    # limit reached
    return (undef, 'Too many connections from this host') if $count >= conf('limit', 'perip');

    foreach (keys %::zline) {
            # IP matches a Z-Line in the configuration
            return (undef, 'Z-Lined: '.$::zline{$_}{'reason'}) if hostmatch($ip, $_)
    }
    return 1
}

sub DigestImport {
    say '        Importing SHA1 support to cloaking module';
    Digest::SHA->import('sha1_hex')
}

sub register_handler {
    # add a command handler
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

sub delete_handler {
    # delete a command handler
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

1
