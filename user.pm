#!/usr/bin/perl -w
use warnings;
use strict;
use less 'mem';
package user;
my $cid = 0;
my $max = 0;
our %connection;
my %commands = (
  PONG => sub{},
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
  GLOBOPS => \&handle_globops,
  TOPIC => \&handle_topic,
  KICK => \&handle_kick,
  INVITE => \&handle_invite,
	LIST => \&handle_list,
	ISON => \&handle_ison
);
my %numerics = (
  461 => '%s :Not enough parameters', 
  401 => '%s :No such nick/channel',
  422 => '%s :You\'re not on that channel',
  482 => '%s :You\'re not a channel operator',
  443 => '%s %s :is already on channel',
  341 => '%s %s',
	322 => '%s %s :%s',
	323 => ':End of /LIST',
	303 => ':%s'
);
sub new {
#user::new($peer)
  my $ssl = shift;
  my $peer = shift;
  return unless $peer;
  my ($success,$host,$ipv);
  $::select->add($peer);
  ::sendpeer($peer,':'.::conf('server','name').' NOTICE * :*** Looking up your hostname...');
  my $ip = $peer->peerhost;
  if ($ip =~ m/:/) { $ipv = 6; } else { $ipv = 4; }
  $success = 0;
  $host = $ip;
  my $this = {
    'ssl' => $ssl,
    'server' => $::id,
    'id' => $::id.&newid,
    'obj' => $peer,
    'ip' => $ip,
    'ipv' => $ipv,
    'host' => $host,
    'cloak' => $host,
    'res' => $success,
    'mode' => {},
    'time' => time,
    'idle' => time,
    'ping' => time,
    'last' => time
  };
  bless $this;
  if ($success) { $this->servernotice('*** Found your hostname ('.$this->{'host'}.')'); }
  else { $this->servernotice('*** Could not resolve hostname; using IP address instead'); }
  $connection{$peer} = $this;
  return $this;
}
sub setmode {
  my ($user,$modes,$a) = @_;
  $user->send(':'.$user->nick.' MODE '.$user->nick.' :+'.$modes) unless $a;
  foreach (split(//,$modes)) {
    $user->{'mode'}->{$_} = time;
    next if $_ =~ m/i/;
    if ($_ eq 'x' && ::conf('enabled','cloaking')) {
      $user->{'cloak'} = $user->setcloak;
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
  foreach (split(//,$modes)) {
    delete $user->{'mode'}->{$_};
    next if $_ =~ m/(i|S)/;
    if ($_ eq 'x' && ::conf('enabled','cloaking')) {
      $user->{'cloak'} = $user->unsetcloak;
    } elsif ($_ eq 'o') {
      delete $user->{'oper'};
      $user->unsetmode('S') if $user->ismode('S');
    }
  }
}
sub hmodes {
  # modes: ix
  my ($user,$modes) = @_;
  return unless $modes;
  my ($state,$p,$m) = (1,'','',());
  foreach (split(//,$modes)) {
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
      $user->sendserv('501 '.$user->nick.' '.$_.' :no such mode');
    }
  }
}
sub handle {
  my $user = shift;
  my $command = uc shift;
  if (exists($commands{$command})) {
    $commands{$command}($user,shift);
  } else { $user->sendserv('421 '.$user->nick.' '.$command.' :Unknown command'); }
}
sub setcloak {
  my $user = shift;
	my $cloak = host2cloak($user->{'ipv'}==6?1:0,$user->{'host'});
  $user->sendserv('396 '.$user->nick.' '.$cloak.' :is now your displayed host');
  return $cloak;
}
sub host2cloak {
	my @pieces = ();
	my $sep = shift;
	foreach (split(($sep?':':'\.'),shift)) {
		my $part = Digest::SHA::sha1_hex($_,::conf('cloak','salt'),$#pieces);
  	push(@pieces,($part=~m/....../g)[0]);
	}
	return join($sep?':':'.',@pieces);
}
sub unsetcloak {
  my $user = shift;
  $user->sendserv('396 '.$user->nick.' '.$user->host.' :is now your displayed host');
  return $user->host;
}
#user::lookup($peer)
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
  foreach (split(' ',::oper($user->{'oper'},'privs'))) {
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
  ::snotice('client exiting: '.$user->fullhost.' ['.$user->{'ip'}.'] ('.$r.')') if $user->{'ready'};
  $user->obj->syswrite('ERROR :Closing Link: ('.(defined $user->{'ident'}?$user->{'ident'}:'*').'@'.$user->host.') ['.$r.']'."\r\n",POSIX::BUFSIZ) unless $no;
  delete $connection{$user->obj};
  $::select->remove($user->obj);
  delete $::outbuffer{$user->obj};
  delete $::timer{$user->obj};
  $user->obj->close;
  undef $user;
}
sub servernotice {
  my $user = shift;
  $user->send(':'.::conf('server','name').' NOTICE '.$user->nick." :@_");
}
sub sendnum {
  my $user = shift;
  $user->send(':'.::conf('server','name').' '.shift().' '.$user->nick." @_");
}
sub numeric {
  my $user = shift;
  my $num = shift;
  $user->send(join(' ',':'.::conf('server','name'),$num,$user->nick,sprintf($numerics{$num},@_)));
}
sub sendserv {
  shift->send(':'.::conf('server','name').' '.sprintf(shift, @_));
}
sub sendservj {
  shift->send(':'.::conf('server','name').' '.join(' ',@_));
}
sub sendfrom {
  shift->send(':'.shift().' '.sprintf(shift, @_));
}
sub sendfromj {
  shift->send(':'.shift().' '.join(' ',@_));
}
sub fullcloak {
  my $user = shift;
  if ($user->{'ready'}) {
    return $user->{'nick'}.'!'.$user->{'ident'}.'@'.$user->{'cloak'};
  } else { return '*'; }
}
sub recvprivmsg {
  my ($user,$from,$target,$msg,$cmd) = @_;
  $user->send(':'.$from.' '.$cmd.' '.$target.' :'.$msg);
}
sub mode {
  return shift->{'mode'}->{shift()};
}
sub fullhost {
#$obj->fullhost
  my $user = shift;
  if (defined $user->{'ready'}) {
    return $user->{'nick'}.'!'.$user->{'ident'}.'@'.$user->{'host'};
  } else { return '*'; }
}
sub nick {
#$obj->nick
  my $user = shift;
  if ($user->{'nick'}) {
    return $user->{'nick'};
  } else { return '*'; }
}
sub start {
  my $user = shift;
  return if $user->checkkline;
  $user->sendnum('001',':Welcome to the '.::conf('server','network').' Internet Relay Chat Network '.$user->nick);
  $user->sendnum('002',':Your host is '.::conf('server','name').', running version juno-'.$::VERSION);
  $user->sendnum('003',':This server was created '.POSIX::strftime('%a %b %d %Y at %H:%M:%S %Z',localtime $::TIME));
  # modes
  $user->sendnum('004',::conf('server','name').' juno-'.$::VERSION.' ix o bei');
  $user->sendnum('005','CHANTYPES=# EXCEPTS INVEX CHANMODES=eIbZ,,,mntz PREFIX=(qaohv)~&@%+ NETWORK='.::conf('server','network').' MODES='.::conf('limit','chanmodes').' NICKLEN='.::conf('limit','nick').' TOPICLEN='.::conf('limit','topic').' :are supported by this server');
  $user->handle_lusers;
  $user->handle_motd;
  $user->setmode(::conf('user','automodes').($user->{'ssl'}?'Z':''));
  ::snotice('client connecting: '.$user->fullhost.' ['.$user->{'ip'}.']');
}
sub newid {
  $cid++;
  return $cid-1;
}
sub id { return shift->{'id'}; }
sub obj { return shift->{'obj'}; }
sub server { return shift->{'server'}; }
sub host { return shift->{'host'}; }
sub nickexists {
  my $nick = shift;
  foreach (values %connection) {
    return $_ if lc($_->{'nick'}) eq lc($nick);
  }
  return;  
}
sub lookupbyid {
  my $id = shift;
  foreach (values %connection) {
    return $_ if $_->{'id'} == $id;
  }
  return;  
}
sub canoper {
  my ($user,$oper,$password) = @_;
  return unless exists $::oper{$oper};
  if (::oper($oper,'password') eq crypt($password,::oper($oper,'salt'))) {
        return $oper if ::hostmatch($user->fullhost,split(' ',::oper($oper,'host')));
  }
  return;
}
sub ison {
  my ($user,$channel) = @_;
  return 1 if exists $channel->{'users'}->{$user->{'id'}};
  return;
}
sub checkkline {
  my $user = shift;
  foreach (keys %::kline) {
    if (::hostmatch($user->fullhost,$_)) {
      $user->quit('K-Lined: '.$::kline{$_}{'reason'},undef,'K-Lined'.(::conf('main','showkline')?': '.$::kline{$_}{'reason'}:''));
      return 1;
    }
  }
  return;
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
  $max = $t if $max < $t;
  $user->sendnum(251,':There are '.$i.' users are '.$ii.' invisible on 1 servers');
  $user->sendnum(265,$t.' '.$max.' :Current local users '.$t.', max '.$max);
  $user->sendnum(267,$t.' '.$max.' :Current global users '.$t.', max '.$max);
}
sub handle_motd {
  my $user = shift;
  open(my $MOTD,::conf('server','motd')) or $user->sendnum(376,':MOTD file missing.');
  $user->sendnum(375,':'.::conf('server','name').' message of the day');
  while (my $line = <$MOTD>) {
    chomp $line;
    $user->sendnum(372,':- '.$line);
  }
  $user->sendnum(376,':End of message of the day.');
  close $MOTD;
}
sub handle_nick {
  my $user = shift;
  my @s = split(' ',shift);
  if ($s[1]) {
    return if $s[1] eq $user->nick;
    if (::validnick($s[1],::conf('limit','nick'),undef)) {
      unless(user::nickexists($s[1])) {
        my %sent = ();
        foreach (values %channel::channels) {
          if ($user->ison($_)) {
            $_->check;
            foreach (keys %{$_->{'users'}}) {
              next if $sent{$_};
              lookupbyid($_)->send(':'.$user->fullcloak.' NICK :'.$s[1]);
              $sent{$_} = 1;
            }
          }
        }
        undef %sent;
        $user->{'nick'} = $s[1];
      } else { $user->sendserv('432 '.$user->nick.' '.$s[1].' :Nickname is already in use.'); }
    } else { $user->sendserv('432 '.$user->nick.' '.$s[1].' :Erroneous nickname'); }
  } else { $user->sendnum(431,':No nickname given'); }
}
sub handle_whois {
  my $user = shift;
  my $nick = (split(' ',shift))[1];
  my $modes = '';
  if ($nick) {
    my $target = nickexists($nick);
    if ($target) {
      $modes .= $_ foreach (keys %{$target->{'mode'}});
      $user->sendserv('311 '.$user->nick.' '.$target->nick.' '.$target->{'ident'}.' '.$target->{'cloak'}.' * :'.$target->{'gecos'});
      #>> :server 319 nick targetnick :~#chat @#halp
      $user->sendserv('312 '.$user->nick.' '.$target->nick.' '.::conf('server','name').' :'.::conf('server','desc')); # only until linking
      $user->sendserv('641 '.$user->nick.' '.$target->nick.' :is using a secure connection') if $target->{'ssl'};
      $user->sendserv('301 '.$user->nick.' '.$target->nick.' :'.$target->{'away'}) if defined $target->{'away'};
      $user->sendserv('313 '.$user->nick.' '.$target->nick.' :is an IRC operator') if $target->ismode('o');
      $user->sendserv('379 '.$user->nick.' '.$target->nick.' :is using modes +'.$modes) if $user->ismode('o');
      $user->sendserv('378 '.$user->nick.' '.$target->nick.' :is connecting from *@'.$target->{'host'}.' '.$target->{'ip'}) if (!$user->{'mode'}->{'x'} || $user->ismode('o')); 
      $user->sendserv('317 '.$user->nick.' '.$target->nick.' '.(time-$target->{'idle'}).' '.$target->{'time'}.' :seconds idle, signon time');

    } else {
      $user->sendserv('401 '.$user->nick.' '.$nick.' :No suck nick/channel');
    }
    $user->sendserv('318 '.$user->nick.' '.$nick.' :End of /WHOIS list.');
  } else { $user->sendserv('461 '.$user->nick.' WHOIS :Not enough parameters'); }

}
sub handle_ping {
  my $user = shift;
  my $reason = (split(' ',shift,2))[1];
  $user->sendserv('PONG '.::conf('server','name').($reason?' '.$reason:''));
}
sub handle_mode {
  my ($user,$data) = @_;
  my @s = split(' ',$data);
	if (defined($s[1])) {
		if (lc($s[1]) eq lc($user->nick)) {
		  $user->hmodes($s[2]);
		} else {
		  my $target = channel::chanexists($s[1]);
		  if ($target) {
		    $target->handlemode($user,(split(' ',$data,3))[2]);
		  } else {
		    $user->sendserv('401 '.$user->nick.' '.$s[1].' :No suck nick/channel');
		  }
		}
	} else { $user->numeric(461,'MODE'); }
}
sub handle_privmsgnotice {
  my ($user,$data) = @_;
  my $n = 0;
  my @s = split(' ',$data);
  if (uc $s[0] eq 'NOTICE') { $n = 1; }
  my $target = nickexists($s[1]);
  my $channel = channel::chanexists($s[1]);
  my $msg = ::col((split(' ',$data,3))[2]);
  if ($target) {
    if (defined $s[2]) {
      if ($msg ne '') { 
        $target->recvprivmsg($user->fullcloak,$target->nick,$msg,($n?'NOTICE':'PRIVMSG'));
      } else { $user->sendserv('412 '.$user->nick.' :No text to send'); }
    } else { $user->sendserv('461 '.$user->nick.' '.($n?'NOTICE':'PRIVMSG').' :Not enough parameters.'); }
  } elsif ($channel) {
    $channel->privmsgnotice($user,($n?'NOTICE':'PRIVMSG'),$msg);
  } else {
    $user->sendserv('401 '.$user->nick.' '.$s[1].' :No suck nick/channel');
  }
}
sub handle_away {
  my ($user,$reason) = (shift,(split(' ',shift,2))[1]);
  if (defined $user->{'away'}) {
    $user->{'away'} = undef;
    $user->sendserv('305 '.$user->nick.' :You are no longer marked as being away');
    return;
  }
  $user->{'away'} = ::col($reason);
  $user->sendserv('306 '.$user->nick.' :You have been marked as being away');
}
sub handle_oper {
  my ($user,$data) = @_;
  my @s = split(' ',$data);
  if (defined $s[2]) {
    my $oper = $user->canoper($s[1],$s[2]);
    if ($oper) {
      $user->{'oper'} = $oper;
      $user->setmode('o'.(::oper($oper,'snotice')?'S':''));
      ::snotice($user->fullhost.' is now an IRC operator using name '.$oper);
      ::snotice('user '.$user->nick.' now has oper privs: '.::oper($oper,'privs'));
    } else { $user->sendserv('491 '.$user->nick.' :Invalid oper credentials'); }
  } else { $user->sendserv('461 '.$user->nick.' OPER :Not enough parameters.'); }
}
sub handle_kill {
  my ($user,$data) = @_;
  my @s = split(' ',$data);
  if (defined $s[2]) {
    if ($user->can('kill')) {
      my $target = nickexists($s[1]);
      if ($target) {
        my $reason = ::col((split(' ',$data,3))[2]);
        $target->quit('Killed ('.$user->nick.' ('.$reason.'))');
      } else { $user->sendserv('401 '.$user->nick.' nightly :No such nick/channel'); }
    } else { $user->sendserv('481 '.$user->nick.' :Permission Denied'); }
  } else { $user->sendserv('461 '.$user->nick.' KILL :Not enough parameters.'); }
}
sub handle_join {
  my ($user,$data) = @_;
  my @s = split(' ',$data);
  if (defined($s[1])) {
    $s[1] = ::col($s[1]);
    foreach(split(',',$s[1])) {
      my $target = channel::chanexists($_);
      if ($target) {
        $target->dojoin($user) unless $user->ison($target);
      } else {
        if ($_ =~ m/^#/) {
          channel::new($user,$_);
        } else {
          $user->sendserv('403 '.$user->nick.' '.$_.' :Invalid channel name');
        }
      }
    }
  } else { $user->sendserv('461 '.$user->nick.' JOIN :Not enough parameters.'); }
}
sub handle_who {
  my ($user,$query) = (shift,(split(' ',shift))[1]);
  my $target = channel::chanexists($query);
  if ($target) {
    $target->who($user);
  }
  $user->sendserv('315 '.$user->nick.' '.$query.' :End of /WHO list.');
}
sub handle_names {
  my $user = shift;
  foreach (split(',',(split(' ',shift))[1])) { 
    my $target = channel::chanexists($_);
    $target->names($user) if $target;
    $user->sendserv('366 '.$user->nick.' '.$_.' :End of /NAMES list.') unless $target;
  }
}
sub handle_part {
  my ($user,$data) = @_;
  my @s = split(' ',$data);
  my $reason = ::col((split(' ',$data,3))[2]);
  if ($s[1]) {
    foreach (split(',',$s[1])) {
      my $channel = channel::chanexists($_);
      if ($channel) {
        if ($user->ison($channel)) {
          $channel->allsend(':'.$user->fullcloak.' PART '.$channel->name.(defined $reason?' :'.$reason:''),undef);
          $channel->remove($user);
        } else { $user->sendserv('422 '.$user->nick.' '.$channel->name.' :You\'re not on that channel'); }
      } else {
        $user->sendserv('401 '.$user->nick.' '.$_.' :No such nick/channel');
      }
    }
  } else { $user->sendserv('461 '.$user->nick.' JOIN :Not enough parameters.'); }
}
sub handle_quit {
  my ($user,$reason) = (shift,::col((split(' ',shift,2))[1]));
  $user->quit('Quit: '.$reason);
}
sub handle_rehash {
  my $user = shift;
  if ($user->can('rehash')) {
    (%::config,%::oper,%::kline) = ((),(),());
    ::snotice($user->nick.' is rehashing server configuration file');
    ::confparse($::CONFIG);
  } else {
    $user->sendserv('481 '.$user->nick.' :Permission Denied');
  }
}
sub handle_globops {
  my ($user,$data) = @_;
  if ($user->can('globops')) {
    my @s = split(' ',$data,2);
    if (defined $s[1]) {
      ::snotice('GLOBOPS from '.$user->nick.': '.$s[1]);
    } else { $user->sendserv('461 '.$user->nick.' GLOBOPS :Not enough parameters.'); }
  } else { $user->sendserv('481 '.$user->nick.' :Permission Denied'); }
}
sub handle_topic {
  my ($user,$data) = @_;
  my @s = split(' ',$data,3);
  if (defined $s[1]) {
    my $channel = channel::chanexists($s[1]);
    if ($channel) {
      if (defined $s[2]) {
        $s[2] = substr($s[2],0,-(length($s[2])-(::conf('limit','topic')+1))) if (length $s[2] > ::conf('limit','topic'));
        $channel->settopic($user,::col($s[2]));
      } else {
        $channel->showtopic($user);
      }
    } else { $user->sendserv('401 '.$user->nick.' '.$s[1].' :No such nick/channel'); }
  } else {
    $user->sendserv('461 '.$user->nick.' TOPIC :Not enough parameters.');
  }
}
sub handle_kick {
  my($user,$data) = @_;
  my @s = split(' ',$data,4);
  if (defined $s[2]) {
    my $channel = channel::chanexists($s[1]);
    my $target = nickexists($s[2]);
    if ($channel && $target) {
      my $reason = $target->nick;
      $reason = ::col($s[3]) if defined $s[3];
      $user->sendserv('482 '.$user->nick.' '.$channel->name.' :You do not have the proper privileges to kick this user') unless $channel->kick($user,$target,$reason);
    } else { $user->numeric(401,$s[1]); }
  } else { $user->numeric(461,'KICK'); }
}
sub handle_invite {
  my($user,@s) = (shift,split(' ',shift));
  if (defined $s[2]) {
    my $someone = nickexists($s[1]);
    my $somewhere = channel::chanexists($s[2]);
    if ($someone) {
			return if $someone == $user;
      if ($somewhere) {
        if ($user->ison($somewhere)) {
          if ($somewhere->basicstatus($user)) {
            unless ($someone->ison($somewhere)) {
              $somewhere->{'invites'}->{$someone->{'id'}} = time;
              $someone->sendfrom($user->nick,' INVITE '.$someone->nick.' :'.$somewhere->name);
              $user->numeric(341,$someone->nick,$somewhere->name);
            } else { $user->numeric(433,$someone->nick,$somewhere->name); }
          } else { $user->numeric(482,$somewhere->name); }
        } else { $user->numeric(422,$somewhere->name); }
      } else { $user->numeric(401,$s[2]); }
    } else { $user->numeric(401,$s[1]); }
  } else { $user->numeric(461,'INVITE'); }
}
sub handle_list {
	my($user,@s) = (shift,split(' ',shift));
	$user->sendserv('321 %s Channel :Users  Name',$user->nick);
	if ($s[1]) {
		foreach(split(',',$s[1])) {
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
	my($user,@s,@final) = (shift,split(' ',shift),());
	if (defined $s[1]) {
		foreach (@s[1..$#s]) {
			my $u = nickexists($_);
			if ($u) {
				push(@final,$u->nick);
			}
		}
		$user->numeric(303,join(' ',@final));
	} else { $user->numeric(461,'ISON'); }
}
1
