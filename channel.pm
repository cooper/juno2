#!/usr/bin/perl -w
use warnings;
use strict;
use less 'mem';
package channel;
our %channels;
sub new {
  my ($user,$name) = @_;
  my $this = {
    'name' => $name,
    'time' => time,
    'first' => time,
    'mode' => {}, # (time => time, params => something or undef), qaohvbieIZ don't count
    'creator' => $user->nick,
    'users' => {},
    'owners' => {$user->{'id'}=>time},
    'admins' => {},
    'ops' => {$user->{'id'}=>time},
    'halfops' => {},
    'voices' => {},
    'bans' => {}, # array ref [setby,time]
    'mutes' => {},
    'invexes' => {},
    'exempts' => {},
    'invites' => {}
  };
  bless $this;
  $channels{lc($name)} = $this;
  $this->dojoin($user);
  $this->{'mode'}->{$_} = {time => time, params => undef} foreach (split //, ::conf('channel','automodes'));
  $this->allsend(':%s MODE %s +%s',0,::conf('server','name'),$name,::conf('channel','automodes')) if ::conf('channel','automodes');
  ::snotice('channel '.$name.' created by '.$user->fullhost);
  return $this;
}
sub dojoin {
  my ($channel,$user) = @_;
  if (!::hostmatch($user->fullcloak,keys %{$channel->{'bans'}}) && !::hostmatch($user->fullcloak,keys %{$channel->{'exempts'}}) &&
  !::hostmatch($user->fullhost,keys %{$channel->{'bans'}}) && !::hostmatch($user->fullhost,keys %{$channel->{'exempts'}})) {
    if ($channel->ismode('i') && !$channel->{'invites'}->{$user->{'id'}} && !::hostmatch($user->fullcloak,keys %{$channel->{'invexes'}})) {
      $user->numeric(473,$channel->name);
      return
    }
    delete $channel->{'invites'}->{$user->{'id'}};
    $channel->{'users'}->{$user->{'id'}} = time;
    $channel->allsend(':%s JOIN :%s',0,$user->fullcloak,$channel->name);
    $channel->showtopic($user,1);
    $channel->names($user);
  } else { $user->numeric(474,$channel->name); }
}
sub allsend {
  my ($channel,$data) = (shift,shift);
  my $nou = shift;
  foreach (keys %{$channel->{'users'}}) {
    my $u = user::lookupbyid($_);
    $u->send(sprintf($data,@_)) unless $u == $nou;
  }
}
sub opsend {
  my ($channel,$data,$nou) = @_; my $halt;
  foreach (keys %{$channel->{'users'}}) {
    $halt = 0;
    my $u = user::lookupbyid($_);
    next unless $channel->basicstatus($u,1);
    $halt = 1 if defined $nou && $nou == $u;
    $u->send($data) unless $halt;
  }
}
sub remove {
  my $channel = shift;
  my $id = shift->{'id'};
  delete $channel->{$_}->{$id} foreach ('users','owners','admins','ops','halfops','voices','invites');
  $channel->check;
}
sub who {
  my $channel = shift;
  my $user = shift;
  foreach (keys %{$channel->{'users'}}) {
    my $u = user::lookupbyid($_);
    my $flags = (defined $u->{'away'}?'G':'H').
    (defined $u->{'oper'}?'*':'').
    (defined $channel->{'owners'}->{$_}?'~':'').
    (defined $channel->{'admins'}->{$_}?'&':'').
    (defined $channel->{'ops'}->{$_}?'@':'').
    (defined $channel->{'halfops'}->{$_}?'%%':'').
    (defined $channel->{'voices'}->{$_}?'+':'');
    $user->sendservj(352,$user->nick,$channel->name,$u->{'ident'},$u->{'cloak'},::conf('server','name'),$u->nick,$flags,':0',$u->{'gecos'});
  }
}
sub check {
  my $channel = shift;
  my @c = keys %{$channel->{'users'}};
  if($#c < 0) {
    delete $channels{lc($channel->name)};
    ::snotice('dead channel: '.$channel->name)
  }
}
sub has {
  my ($channel,$user,@status) = @_;
  foreach (@status) {
    return 1 if $channel->{$_.'s'}->{$user->{'id'}};
  }
  return;
}
sub names {
  my ($channel,$user) = @_;
  my $names = '';
  foreach (keys %{$channel->{'users'}}) {
    my $u = user::lookupbyid($_);
    next if ($u->ismode('i') and !$user->ison($channel));
    $names .=
    (defined $channel->{'owners'}->{$_}?'~':
    (defined $channel->{'admins'}->{$_}?'&':
    (defined $channel->{'ops'}->{$_}?'@':
    (defined $channel->{'halfops'}->{$_}?'%%':
    (defined $channel->{'voices'}->{$_}?'+':''))))).
    $u->nick.' ';
  }
  $user->numeric(353,$channel->name,$names) unless $names eq '';
  $user->numeric(366,$channel->name);
}
sub chanexists {
  my $name = lc shift;
  return $channels{$name} if exists $channels{$name};
  return undef;
}
sub basicstatus {
  my ($channel,$user,$HOP) = @_;
  my $halfop = $channel->has($user,'halfop');
  $halfop = 0 if $HOP;
  if(!$channel->has($user,'owner') && !$channel->has($user,'admin') && !$channel->has($user,'op') && !$halfop) {
    return;
  } return 1;
}
sub setmode {
  my $channel = shift;
  my $mode = shift;
  my $par = shift;
  $channel->{'mode'}->{$mode}{'time'} = time;
  $channel->{'mode'}->{$mode}{'params'} = (defined $par?$par:undef);
}
sub ismode {
  my $channel = shift;
  my $mode = shift;
  return $channel->{'mode'}->{$mode} if exists $channel->{'mode'}->{$mode};
  return;
}
sub unsetmode {
  my $channel = shift;
  foreach (split //,shift) {
    delete $channel->{'mode'}->{$_};
  }
}
sub name { return shift->{'name'}; }
sub handlemode {
  my ($channel,$user) = (shift,shift);
  my $str = shift || '';
  my @s = split ' ', $str, 2;
  my @args = split ' ',$s[1] if defined $s[1];
  if (!$str || $str eq '') {
    my ($all,$params) = ('','');
    foreach (keys %{$channel->{'mode'}}) {
      $all .= $_;
      $params .= $channel->{'mode'}->{$_}->{'params'}.' ' if defined $channel->{'mode'}->{$_}->{'params'};
    }
    $user->numeric(324,$channel->name,$all,$params);
    $user->numeric(329,$channel->name,$channel->{'first'});
  } else {
    my ($state,$cstate,$i,$failed) = (1,1,1,0);
    my (@par,@final);
    foreach (split //,$s[0]) {
      last if $i > ::conf('limit','chanmodes');
      $i++ if $_ !~ m/(\+|-)/; 
      given($_) {
        when('+') {
          $state = 1;
        } when('-') {
          $state = 0;
        } when(/(n|t|m|i|z)/) {
          $failed = 1, next unless $channel->basicstatus($user);
          $channel->setmode($_) if $state;
          $channel->unsetmode($_) unless $state;
          if ($cstate == $state) {
            push(@final,$_);
          } else {
            push(@final,($state?'+':'-').$_);
          }
          $cstate = $state;
        } when(/(q|a|o|h|v)/) {
          my $target = shift(@args);
          $failed = 1, next unless defined $target;
          my $success = $channel->handlestatus($user,$state,$_,$target);
          if ($success) {
            if ($cstate == $state) {
              push(@final,$_);
            } else {
              push(@final,($state?'+':'-').$_);
            }
            $cstate = $state;
            push(@par,$success);
          }
        } when(/(b|Z|e|I)/) {
          my $target = shift(@args);
          if(!defined $target) {
            $channel->sendmasklist($user,$_); 
            next;
          }
          my $success = $channel->handlemaskmode($user,$state,$_,$target);
          if ($success) {
            if ($cstate == $state) {
              push(@final,$_);
            } else {
              push(@final,($state?'+':'-').$_);
            }
            $cstate = $state;
            push(@par,$success);
          }
        } default {
          $user->numeric(472,$_);
        }
      }
    }
    unshift(@final,'+');
    my $finished = join('',@final);
    $finished =~ s/\+-/-/g;
    $user->numeric(482,$channel->name,'half-operator') if $failed;
    $channel->allsend(':%s MODE %s %s %s',0,$user->fullcloak,$channel->name,$finished,join(' ',@par)) unless $finished eq '+';
  }
}
sub handlestatus {
  my($channel,$user,$state,$mode,$tuser) = @_;
  my(@needs,$modename,$longname);
  given($mode) {
    when('q') {
      $modename = 'owners';
      @needs = 'owner';
      $longname = 'owner'
    } when('a') {
      $modename = 'admins';
      @needs = ('owner','admin');
      $longname = 'administrator'
    } when('o') {
      $modename = 'ops';
      @needs = ('owner','admin','op');
      $longname = 'operator'
    } when('h') {
      $modename = 'halfops';
      @needs = ('owner','admin','op');
      $longname = 'operator'
    } when('v') {
      $modename = 'voices';
      @needs = ('owner','admin','op','halfop');
      $longname = 'half-operator'
    }
  }
  if ($channel->has($user,@needs)) {
    my $target = user::nickexists($tuser);
    if ($target) {
      if ($target->ison($channel)) {
        if ($state) {
          $channel->{$modename}->{$target->{'id'}} = time;
        } else {
          delete $channel->{$modename}->{$target->{'id'}};
        }
        return $target->nick;
      } else {
        $user->numeric(441,$target->nick,$channel->name);
        return;
      }
    } else {
      $user->numeric(401,$tuser);
      return;
    }
  } else {
    $user->numeric(482,$channel->name,$longname);
    return;
  }
}
sub showtopic {
  my ($channel,$user,$halt) = @_;
  if ($channel->{'topic'}) {
    $user->numeric(332,$channel->name,$channel->{'topic'}->{'topic'});
    $user->numeric(333,$channel->name,$channel->{'topic'}->{'setby'},$channel->{'topic'}->{'time'});
  } else {
    $user->numeric(331,$channel->name) unless $halt;
  }
}
sub settopic {
  my ($channel,$user,$topic) = @_;
  my $success = 0;
  if ($channel->ismode('t')) {
    $success = 1 if ($channel->has($user,'owner') || $channel->has($user,'admin') || $channel->has($user,'op') || $channel->has($user,'halfop'));
  } else { $success = 1; }
  if ($success) {
    $channel->{'topic'} = {
      'topic' => $topic,
      'time' => time,
      'setby' => (::conf('main','fullmasktopic')?$user->fullcloak:$user->nick)
    };
    $channel->allsend('%s TOPIC %s :%s',0,$user->fullcloak,$channel->name,$topic);
  } else { $user->numeric(482,$channel->name,'half-operator'); }
}
sub canspeakwithstatus {
  my ($channel,$user) = @_;
  if(!$channel->has($user,'owner') && !$channel->has($user,'admin') && !$channel->has($user,'op') && !$channel->has($user,'halfop') && !$channel->has($user,'voice')) {
    return;
  }
  return 1;
}
sub privmsgnotice {
  my ($channel,$user,$type,$msg) = @_;
  if (($channel->ismode('n') && !$user->ison($channel)) ||
  ($channel->ismode('m') && !$channel->canspeakwithstatus($user)) ||
  ((::hostmatch($user->fullcloak,keys %{$channel->{'bans'}}) || 
  ::hostmatch($user->fullhost,keys %{$channel->{'bans'}}) ||
  ::hostmatch($user->fullcloak,keys %{$channel->{'mutes'}}) ||
  ::hostmatch($user->fullhost,keys %{$channel->{'mutes'}})) && 
  !$channel->canspeakwithstatus($user) && !::hostmatch($user->fullcloak,keys %{$channel->{'exempts'}}))) {
    if ($channel->ismode('z')) {
      $channel->opsend(':'.$user->fullcloak.' '.join(' ',$type,$channel->name,':'.$msg),$user);
      return 1;
    } else {
      $user->numeric(404,$channel->name);
      return;
    }
  }
  $channel->allsend(':%s %s %s :%s',$user,$user->fullcloak,$type,$channel->name,$msg);
}
sub handlemaskmode {
  my ($channel,$user,$state,$mode,$mask) = @_;
  $user->numeric(482,$channel->name,'half-operator'), return unless $channel->basicstatus($user);
   if ($mask =~ m/\@/) {
    if ($mask =~ m/\!/) {
      $mask = $mask;
    }  else {
      $mask = '*!'.$mask;
    }
  }  else {
    if ($mask =~ m/\!/) {
      $mask = $mask.'@*';
    } else {
      $mask = $mask.'!*@*';
    }
  }
  my $modename;
  given($mode) {
    when('b') {
      $modename = 'bans'
    } when('Z') {
      $modename = 'mutes'
    } when('I') {
      $modename = 'invexes'
    } when('e') {
      $modename = 'exempts'
    }
  }
  if ($state) {
    $channel->{$modename}->{$mask} = [$user->fullcloak,time];
  } else {
    delete $channel->{$modename}->{$mask} if exists $channel->{$modename}->{$mask};
  }
  return $mask;
}
sub sendmasklist {
  my ($channel,$user,$modes) = @_;
  MODES: foreach (split //,$modes) {
    next unless $_ =~ m/^(b|Z|e|I)$/;
    my @list;
    given($_) {
      when('b') {
        @list = (367,368,'bans',0);
      } when('Z') {
        @list = (728,729,'mutes',0);
      } when('e') {
        @list = (348,349,'exempts',1);
      } when('I') {
        @list = (346,347,'invexes',1);
      }
    }
    if($list[3] && !$channel->basicstatus($user)) {
      $user->numeric(482,$channel->name,'half-operator');
      next MODES;
    }
    foreach (keys %{$channel->{$list[2]}}) {
      $user->numeric($list[0],$channel->name,$_,$channel->{$list[2]}->{$_}->[0],$channel->{$list[2]}->{$_}->[1]);
    }
    $user->numeric($list[1],$channel->name);
  }
  return 1;
}
sub kick {
  my ($channel,$user,$target,$reason) = @_;
  return unless $channel->basicstatus($user);
  return if ($channel->has($target,'owner') && !$channel->has($user,'owner'));
  return if ($channel->has($target,'admin') && !$channel->has($user,'owner') && !$channel->has($user,'admin'));
  return if ($channel->has($target,'op') && !$channel->has($user,'owner') && !$channel->has($user,'admin') && !$channel->has($user,'op'));
  return if ($channel->has($target,'halfop') && !$channel->has($user,'owner') && !$channel->has($user,'admin') && !$channel->has($user,'op'));
  $channel->allsend(':%s KICK %s %s :%s',0,$user->fullcloak,$channel->name,$target->nick,$reason);
  $channel->remove($target);
  return 1;
}
sub list {
  my $channel = shift;
  my $user = shift;
  my @users = keys %{$channel->{'users'}};
  $user->numeric(322,$channel->name,$#users+1,$channel->{'topic'}?$channel->{'topic'}->{'topic'}:'');
}
1
