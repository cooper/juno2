#!/usr/bin/perl -w
package user;
use warnings;
use strict;
use less 'mem';
use utils qw/col conf oper hostmatch snotice validnick/;
$utils::GV{'cid'} = 0;
$utils::GV{'max'} = 0;
our %connection;
our %commands = (
    PONG => sub {},
    USER => sub { shift->numeric(462) },
    SACONNECT => sub { return },
    LUSERS => \&handle_lusers,
    MOTD => \&handle_motd,
    NICK => \&handle_nick,
    PING => \&handle_ping,
    WHOIS => \&handle_whois,
    MODE => \&handle_mode,
    PRIVMSG => \&handle_privmsgnotice,
    NOTICE => \&handle_privmsgnotice,
    AWAY => \&handle_away,
    OPER => \&handle_oper,
    KILL => \&handle_kill,
    JOIN => \&handle_join,
    WHO => \&handle_who,
    NAMES => \&handle_names,
    QUIT => \&handle_quit,
    PART => \&handle_part,
    REHASH => \&handle_rehash,
    LOCOPS => \&handle_locops,
    GLOBOPS => \&handle_locops,
    TOPIC => \&handle_topic,
    KICK => \&handle_kick,
    INVITE => \&handle_invite,
    LIST => \&handle_list,
    ISON => \&handle_ison,
);
our %numerics = (
    251 => ':There are %s users and %s invisible on %s servers',
    265 => '%s %s :Current local users %s, max %s',
    267 => '%s %s :Current global users %s, max %s',
    301 => '%s :%s',
    303 => ':%s',
    305 => ':You are no longer marked as being away',
    306 => ':You have been marked as being away',
    311 => '%s %s %s * :%s',
    312 => '%s %s :%s',
    313 => '%s :is an IRC operator',
    315 => '%s :End of /WHO list',
    317 => '%s %s %s :seconds idle, signon time',
    318 => '%s :End of /WHOIS list',
    321 => 'Channel :Users    Name',
    322 => '%s %s :%s',
    323 => ':End of /LIST',
    324 => '%s +%s %s',
    329 => '%s %s',
    331 => '%s :No topic is set',
    332 => '%s :%s',
    333 => '%s %s %s',
    341 => '%s %s',
    345 => '%s %s :Cannot change nickname while banned on channel',
    346 => '%s %s %s %s',
    347 => '%s :End of channel invite list',
    348 => '%s %s %s %s',
    349 => '%s :End of channel exception list',
    353 => '= %s :%s',
    366 => '%s :End of /NAMES list',
    367 => '%s %s %s %s',
    368 => '%s :End of channel ban list',
    372 => ':- %s',
    375 => '%s message of the day',
    376 => ':End of message of the day.',
    378 => '%s :is connecting from *@%s %s',
    379 => '%s :is using modes +%s',
    381 => '%s :End of /WHOIS list.',
    388 => '%s %s %s %s',
    389 => '%s :End of channel auto-access list',
    396 => '%s :is now your displayed host',
    401 => '%s :No such nick/channel',
    403 => '%s :Invalid channel name',
    404 => '%s :Cannot send to channel',
    412 => ':No text to send',
    421 => '%s :Unknown command',
    422 => '%s :You\'re not on that channel',
    431 => ':No nickname given',
    432 => '%s :Erroneous nickname',
    433 => '%s :Nickname is already in use',
    441 => '%s :User is already on channel',    
    443 => '%s %s :is already on channel',
    461 => '%s :Not enough parameters',
    462 => ':You may not reregister',
    471 => '%s :Cannot join channel (channel limit reached)',
    472 => '%s :No such mode',
    473 => '%s :Cannot join channel (channel is invite only)',
    474 => '%s :Cannot join channel (you\'re banned)',
    481 => ':Permission Denied',
    482 => '%s :You\'re not a channel %s',
    491 => ':Invalid oper credentials',
    501 => '%s :No such mode',
    641 => '%s :is using a secure connection',
    728 => '%s %s %s %s',
    729 => '%s :End of channel mute list',
);
sub new {
    my($ssl,$peer) = @_;
    return unless $peer;
    if (!&acceptcheck) {
        $peer->close;
        return;
    }
    my @ip_accept = ip_accept($peer->peerhost);
    if (!$ip_accept[0]) {
        $peer->syswrite('ERROR :Closing Link: (*@'.$peer->peerhost.') ['.$ip_accept[1].']'."\r\n",POSIX::BUFSIZ);
        $peer->close;
        return;
    }
    $::select->add($peer);
    ::sendpeer($peer,':'.conf('server','name').' NOTICE * :*** Looking up your hostname...');
    my ($ip,$ipv) = ($peer->peerhost,4);
    $ipv = 6 if $ip =~ m/:/;
    my $user = {
        'ssl' => $ssl,
        'server' => $::id,
        'id' => $::id.&newid,
        'obj' => $peer,
        'ip' => $ip,
        'ipv' => $ipv,
        'host' => $ip,
        'cloak' => $ip,
        'time' => time,
        'idle' => time,
        'ping' => time,
        'last' => time
    };
    bless $user;
    $user->servernotice('*** Could not resolve hostname; using IP address instead');
    $connection{$peer} = $user;
    return $user;
}
sub setmode {
    my ($user,$modes,$a) = @_;
    $user->send(':'.$user->nick.' MODE '.$user->nick.' :+'.$modes) unless $a;
    foreach (split //, $modes) {
        $user->{'mode'}->{$_} = time;
        next if $_ =~ m/i/;
        if ($_ eq 'x' && conf('enabled','cloaking')) {
            $user->setcloak(host2cloak($user->{'ipv'}==6?1:0,$user->{'host'}));
        }
    }
}
sub ismode {
    my ($user,$mode) = @_;
    return $user->{'mode'}->{$mode} if exists $user->{'mode'}->{$mode};
    return;
}
sub unsetmode {
    my ($user,$modes,$a) = @_;
    $user->send(':'.$user->nick.' MODE '.$user->nick.' :-'.$modes) unless $a;
    foreach (split //, $modes) {
        delete $user->{'mode'}->{$_};
        next if $_ =~ m/(i|S)/;
        if ($_ eq 'x' && conf('enabled','cloaking')) {
            $user->unsetcloak;
        } elsif ($_ eq 'o') {
            delete $user->{'oper'};
            $user->unsetmode('S') if $user->ismode('S');
        }
    }
}
sub hmodes {
    my ($user,$modes) = @_;
    return unless $modes;
    my ($state,$p,$m) = (1,'','',());
    foreach (split //, $modes) {
        if ($_ eq '+') { $state = 1; next; }
        elsif ($_ eq '-') { $state = 0; next; }
        next if $_ =~ m/Z/; # modes that cannot be unset
        if ($_ =~ m/(i|x)/) { # normal modes
            $user->unsetmode($_) if $state == 0;
            $user->setmode($_) if $state == 1;
        } elsif ($_ =~ m/(o|S)/) { # oper-only modes
            if ($user->ismode('o')) {
                $user->unsetmode($_) if $state == 0;
                $user->setmode($_) if $state == 1;
            }
        } else {
            $user->numeric(501,$_);
        }
    }
}
sub handle {
    my $user = shift;
    my $command = uc shift;
    if (exists($commands{$command})) {
        $commands{$command}($user,shift);
    } else { $user->numeric(421,$command); }
}
sub setcloak {
    my $user = shift;
    my $cloak = shift;
    $user->numeric(396,$cloak);
    $user->{'cloak'} = $cloak;
    return $cloak;
}
sub host2cloak {
    my @pieces = ();
    my $sep = shift;
    foreach (split ($sep?':':'\.'), shift) {
        my $part = Digest::SHA::sha1_hex($_,conf('cloak','salt'),$#pieces);
        push(@pieces,($part=~m/....../g)[0]);
    }
    return join($sep?':':'.',@pieces);
}
sub unsetcloak {
    my $user = shift;
    $user->numeric(396,$user->host);
    $user->{'cloak'} = $user->host;
    return $user->host;
}
sub lookup {
    my $peer = shift;
    return $connection{$peer} if exists $connection{$peer};
    return;
}
sub send {
    ::sendpeer(shift->obj,@_);
}
sub can {
    my $user = shift;
    my $priv = shift;
    return unless defined $user->{'oper'};
    foreach (split ' ', oper($user->{'oper'},'privs')) {
        return 1 if $_ eq $priv;
    }
    return;
}
sub quit {
    my ($user,$r,$no,$display) = @_;
    my %sent;
    foreach (values %channel::channels) {
        if ($user->ison($_)) {
            $_->check;
            foreach (keys %{$_->{'users'}}) {
                lookupbyid($_)->send(':'.$user->fullcloak.' QUIT :'.($display?$display:$r)) unless $sent{$_};
                $sent{$_} = 1;
            }
        }
        $_->remove($user);
    }
    snotice('client exiting: '.$user->fullhost.' ['.$user->{'ip'}.'] ('.$r.')') if $user->{'ready'};
    $user->obj->syswrite('ERROR :Closing Link: ('.(defined $user->{'ident'}?$user->{'ident'}:'*').'@'.$user->host.') ['.$r.']'."\r\n",POSIX::BUFSIZ) unless $no;
    delete $connection{$user->obj};
    $::select->remove($user->obj);
    delete $::outbuffer{$user->obj};
    delete $::timer{$user->obj};
    $user->obj->close;
    undef $user;
    &acceptcheck;
}
sub servernotice {
    my $user = shift;
    $user->send(':'.conf('server','name').' NOTICE '.$user->nick." :@_");
}
sub sendnum {
    # deprecated
    my $user = shift;
    $user->send(':'.conf('server','name').' '.shift().' '.$user->nick." @_");
}
sub numeric {
    my ($user,$num) = (shift,shift);
    $user->send(join(' ',':'.conf('server','name'),$num,$user->nick,sprintf($numerics{$num},@_)));
}
sub sendserv {
    shift->send(':'.conf('server','name').' '.sprintf(shift, @_));
}
sub sendservj {
    shift->send(':'.conf('server','name').' '.join(' ',@_));
}
sub sendfrom {
    shift->send(':'.shift().' '.sprintf(shift, @_));
}
sub sendfromj {
    shift->send(':'.shift().' '.join(' ',@_));
}
sub fullcloak {
    my $user = shift;
    return $user->{'nick'}.'!'.$user->{'ident'}.'@'.$user->{'cloak'} if $user->{'ready'};
    return '*'
}
sub recvprivmsg {
    my ($user,$from,$target,$msg,$cmd) = @_;
    $user->send(':'.join(' ',$from,$cmd,$target).' :'.$msg);
}
sub mode {
    return shift->{'mode'}->{shift()};
}
sub fullhost {
    my $user = shift;
    return $user->{'nick'}.'!'.$user->{'ident'}.'@'.$user->{'host'} if defined $user->{'ready'};
    return '*'
}
sub nick {
    my $user = shift;
    return $user->{'nick'} if $user->{'nick'};
    return '*'
}
sub start {
    my $user = shift;
    return if $user->checkkline;
    snotice('client connecting: '.$user->fullhost.' ['.$user->{'ip'}.']');
    $user->sendnum('001',':Welcome to the '.conf('server','network').' Internet Relay Chat Network '.$user->nick);
    $user->sendnum('002',':Your host is '.conf('server','name').', running version juno-'.$::VERSION);
    $user->sendnum('003',':This server was created '.POSIX::strftime('%a %b %d %Y at %H:%M:%S %Z',localtime $::TIME));
    $user->sendnum('004',conf('server','name').' juno-'.$::VERSION.' ix o bei');
    $user->sendnum('005','CHANTYPES=# EXCEPTS INVEX CHANMODES=AeIbZ,,l,imntz PREFIX=(qaohv)~&@%+ NETWORK='.conf('server','network').' MODES='.conf('limit','chanmodes').' NICKLEN='.conf('limit','nick').' TOPICLEN='.conf('limit','topic').' :are supported by this server');
    $user->handle_lusers;
    $user->handle_motd;
    $user->setmode(conf('user','automodes').($user->{'ssl'}?'Z':''));
    return 1
}
sub newid {
    $utils::GV{'cid'}++;
    return $utils::GV{'cid'}-1;
}
sub id {
    return shift->{'id'}
}
sub obj {
    return shift->{'obj'}
}
sub server {
    return shift->{'server'}
}
sub host {
    return shift->{'host'};
}
sub nickexists {
    my $nick = shift;
    foreach (values %connection) {
        return $_ if lc($_->{'nick'}) eq lc($nick);
    }
    return    
}
sub lookupbyid {
    my $id = shift;
    foreach (values %connection) {
        return $_ if $_->{'id'} == $id;
    }
    return 
}
sub canoper {
    # TODO: add support for SHA encryption.
    my ($user,$oper,$password) = @_;
    return unless exists $::oper{$oper};
    if (oper($oper,'password') eq crypt($password,oper($oper,'salt'))) {
                return $oper if hostmatch($user->fullhost,(split ' ', oper($oper,'host')))
    }
    return
}
sub ison {
    my ($user,$channel) = @_;
    return 1 if exists $channel->{'users'}->{$user->{'id'}};
    return
}
sub checkkline {
    my $user = shift;
    foreach (keys %::kline) {
        if (hostmatch($user->fullhost,$_)) {
            $user->quit('K-Lined: '.$::kline{$_}{'reason'},undef,'K-Lined'.(conf('main','showkline')?': '.$::kline{$_}{'reason'}:''));
            return 1
        }
    }
    return
}
sub acceptcheck {
    my $i = 0;
    $i++ foreach (values %connection);
    if ($i == conf('limit','clients')) {
        snotice('No new clients are being accepted. ('.$i.' users)') if $::ACCEPTING != 0;
        $::ACCEPTING = 0;
        return
    } else {
        snotice('Clients are now being accepted. ('.$i.' users)') if $::ACCEPTING != 1;
        $::ACCEPTING = 1;
        return 1
    }
}
sub ip_accept {
    my $ip = shift;
    my $count = 0;
    foreach (values %connection) {
        $count++ if $_->{'ip'} eq $ip;
    }
    return (undef,'Too many connections from this host') if $count >= conf('limit','perip');
    foreach (keys %::zline) {
            return (undef,'Z-Lined: '.$::zline{$_}{'reason'}) if hostmatch($ip,$_);
    }
    return 1;
}
# HANDLERS
sub handle_lusers {
    my $user = shift;
    my ($i,$ii) = (0,0);
    foreach (values %connection) {
        if ($_->mode('i')) {
            $ii++;
        } else { $i++; }
    } my $t = $i+$ii;
    $utils::GV{'max'} = $t if $utils::GV{'max'} < $t;
    $user->numeric(251,$i,$ii,1);
    $user->numeric(265,$t,$utils::GV{'max'},$t,$utils::GV{'max'});
    $user->numeric(267,$t,$utils::GV{'max'},$t,$utils::GV{'max'});
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
    my @s = split / /, shift;
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
                            push(@users,lookupbyid($_));
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
    my $nick = (split ' ', shift)[1];
    my $modes = '';
    if ($nick) {
        my $target = nickexists($nick);
        if ($target) {
            $modes .= $_ foreach (keys %{$target->{'mode'}});
            $user->numeric(311,$target->nick,$target->{'ident'},$target->{'cloak'},$target->{'gecos'});
            #>> :server 319 nick targetnick :~#chat @#halp
            $user->numeric(312,$target->nick,conf('server','name'),conf('server','desc'));
            $user->numeric(641,$target->nick) if defined $target->{'ssl'};
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
    my $reason = (split ' ', shift, 2)[1];
    $user->sendserv('PONG '.conf('server','name').(defined $reason?' '.$reason:''));
}
sub handle_mode {
    my ($user,$data) = @_;
    my @s = split / /, $data;
    if (defined($s[1])) {
        if (lc($s[1]) eq lc($user->nick)) {
            $user->hmodes($s[2]);
        } else {
            my $target = channel::chanexists($s[1]);
            if ($target) {
                $target->handlemode($user,(split ' ', $data, 3)[2]);
            } else {
                $user->numeric(401,$s[1]);
            }
        }
    } else { $user->numeric(461,'MODE'); }
}
sub handle_privmsgnotice {
    my ($user, $data) = @_;
    my ($n, @s) = (0, (split / /, $data));
    $n = 1 if uc $s[0] eq 'NOTICE';
    if (!defined $s[2]) {
        $user->numeric(461,$n?'NOTICE':'PRIVMSG');
        return
    }
    my $target = nickexists($s[1]);
    my $channel = channel::chanexists($s[1]);
    my $msg = col((split / /, $data, 3)[2]);
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
    my ($user,$reason) = (shift,(split ' ', shift, 2)[1]);
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
    my @s = split / /, $data;
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
    my @s = split / /, $data;
    if (defined $s[2]) {
        if ($user->can('kill')) {
            my $target = nickexists($s[1]);
            if ($target) {
                my $reason = col((split ' ',$data,3)[2]);
                $target->quit('Killed ('.$user->nick.' ('.$reason.'))');
            } else { $user->numeric(401,$s[1]); }
        } else { $user->numeric(481); }
    } else { $user->numeric(461,'KILL'); }
}
sub handle_join {
    my ($user,$data) = @_;
    my @s = split ' ', $data;
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
    my ($user,$query) = (shift,(split ' ',shift)[1]);
    my $target = channel::chanexists($query);
    if ($target) {
        $target->who($user);
    }
    $user->numeric(315,$query);
}
sub handle_names {
    my $user = shift;
    foreach (split ',', (split ' ',shift)[1]) {
        my $target = channel::chanexists($_);
        $target->names($user) if $target;
        $user->numeric(366,$_) unless $target;
    }
}
sub handle_part {
    my ($user,$data) = @_;
    my @s = split / /, $data;
    my $reason = col((split ' ', $data,3)[2]);
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
    my ($user,$reason) = (shift,col((split ' ', shift, 2)[1]));
    $user->quit('Quit: '.$reason);
}
sub handle_rehash {
    my $user = shift;
    if ($user->can('rehash')) {
        (%::config,%::oper,%::kline) = ((),(),());
        snotice($user->nick.' is rehashing server configuration file');
        confparse($::CONFIG);
    } else {
        $user->numeric(481);
    }
}
sub handle_locops {
    my ($user,$data) = @_;
    if ($user->can('globops') || $user->can('locops')) {
        my @s = split / /, $data, 2;
        if (defined $s[1]) {
            snotice('LOCOPS from '.$user->nick.': '.$s[1]);
        } else { $user->numeric(461,uc $s[0]); }
    } else { $user->numeric(481); }
}
sub handle_topic {
    my ($user,$data) = @_;
    my @s = split / /, $data, 3;
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
    my @s = split / /, $data, 4;
    if (defined $s[2]) {
        my $channel = channel::chanexists($s[1]);
        my $target = nickexists($s[2]);
        if ($channel && $target) {
            my $reason = $target->nick;
            $reason = col($s[3]) if defined $s[3];
            $user->numeric(482,$channel->name,'half-operator') unless $channel->kick($user,$target,$reason);
        } else { $user->numeric(401,$s[1]); }
    } else { $user->numeric(461,'KICK'); }
}
sub handle_invite {
    my($user,@s) = (shift,(split ' ', shift));
    if (defined $s[2]) {
        my $someone = nickexists($s[1]);
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
    my($user,@s) = (shift,(split ' ', shift));
    $user->numeric(321);
    if ($s[1]) {
        foreach (split ',' ,$s[1]) {
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
    my($user,@s,@final) = (shift,(split ' ', shift),());
    if (defined $s[1]) {
        foreach (@s[1..$#s]) {
            my $u = nickexists($_);
            push(@final,$u->nick) if $u;
        }
        $user->numeric(303,(join ' ', @final));
    } else { $user->numeric(461,'ISON'); }
}
1
