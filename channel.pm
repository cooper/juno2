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
    'mode' => {}, # (time => time, params => something or undef), qaohv don't count
    'creator' => $user->nick,
    'users' => {},
    'owners' => {$user->{'id'}=>time},
    'admins' => {},
    'ops' => {$user->{'id'}=>time},
    'halfops' => {},
    'voices' => {},
  };
  bless $this;
  $channels{lc($name)} = $this;
  $this->dojoin($user);
  ::snotice('channel '.$name.' created by '.$user->fullhost);
  return $this;
}
sub dojoin {
  my ($channel,$user) = @_;
  $channel->{'users'}->{$user->{'id'}} = time;
  $channel->allsend(':'.$user->fullcloak.' JOIN :'.$channel->name,undef);
  $channel->showtopic($user,1);
  $channel->names($user);
}
sub allsend {
  my ($channel,$data,$nou) = @_; my $halt;
  foreach (keys %{$channel->{'users'}}) {
    $halt = 0;
    my $u = user::lookupbyid($_);
    $halt = 1 if defined $nou && $nou == $u;
    $u->send($data) unless $halt;
  }
}
sub remove {
  my $channel = shift;
  my $id = shift->{'id'};
  delete $channel->{$_}->{$id} foreach ('users','owners','admins','ops','halfops','voices');
}
sub who {
  my $channel = shift;
  my $user = shift;
  foreach (keys %{$channel->{'users'}}) {
    my $u = user::lookupbyid($_);
    my $flags = (defined $u->{'away'}?'S':'H').
    (defined $u->{'oper'}?'*':'').
    (defined $channel->{'owners'}->{$_}?'~':'').
    (defined $channel->{'admins'}->{$_}?'&':'').
    (defined $channel->{'ops'}->{$_}?'@':'').
    (defined $channel->{'halfops'}->{$_}?'%':'').
    (defined $channel->{'voices'}->{$_}?'+':'');
    $user->sendserv(join(' ',352,$user->nick,$channel->name,$u->{'ident'},$u->{'cloak'},::conf('server','name'),$u->nick,$flags,':0',$u->{'gecos'}));
  }
}
sub check {
  my $channel = shift;
  my @c = keys %{$channel->{'users'}};
  delete $channels{lc($channel->name)} if $#c < 0;
  ::snotice('dead channel: '.$channel->name) if $#c < 0;
}
sub has {
  my ($channel,$user,$status) = @_;
  return $channel->{$status.'s'}->{$user->{'id'}};
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
    (defined $channel->{'halfops'}->{$_}?'%':
    (defined $channel->{'voices'}->{$_}?'+':''))))).
    $u->nick.' ';
  }
  $user->sendserv('353 '.$user->nick.' = '.$channel->name.' :'.$names) if $names ne '';
  $user->sendserv('366 '.$user->nick.' '.$channel->name.' :End of /NAMES list.');
}
sub chanexists {
  my $name = lc shift;
  return $channels{$name} if exists $channels{$name};
  return undef;
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
  foreach (split(//,shift)) {
    delete $channel->{'mode'}->{$_};
  }
}
sub name { return shift->{'name'}; }
sub handlemode {
  my ($channel,$user,$str) = @_;
  if (!$str || $str eq '') {
    my ($all,$params) = ('','');
    foreach (keys %{$channel->{'mode'}}) {
      $all .= $_;
      $params .= $channel->{'mode'}->{$_}->{'params'}.' ' if defined $channel->{'mode'}->{$_}->{'params'};
    }
    $user->sendserv(join(' ',324,$user->nick,$channel->name,'+'.$all,$params));
    $user->sendserv(join(' ',329,$user->nick,$channel->name,$channel->{'first'}));
  } else {
    if (!$channel->has($user,'owner') && !$channel->has($user,'admin') && !$channel->has($user,'op') && !$channel->has($user,'halfop')) {
      $user->sendserv('482 '.$user->nick.' '.$channel->name.' :You\'re not a channel operator');
      return;
    }
    my ($state,$cstate,$i) = (1,1,1);
    my (@args,@par,@final);
    my @s = (split(' ',$str,2));
    @args = split(' ',$s[1]) if defined $s[1];
    foreach (split(//,$s[0])) {
      last if $i > ::conf('limit','chanmodes');
      $i++ if $_ !~ m/(\+|-)/; 
      if ($_ eq '+') { $state = 1; }
      elsif ($_ eq '-') { $state = 0; }
      elsif ($_ =~ m/(n|t|m)/) {
        $channel->setmode($_) if $state;
        $channel->unsetmode($_) unless $state;
        if ($cstate == $state) {
          push(@final,$_);
        } else {
          push(@final,($state?'+':'-').$_);
        }
        $cstate = $state;
      } elsif ($_ =~ m/(q|a|o|h|v)/) {
        my $target = shift(@args);
        next unless defined $target;
        my $suc = $channel->handlestatus($user,$state,$_,$target);
        if ($suc) {
          if ($cstate == $state) {
            push(@final,$_);
          } else {
            push(@final,($state?'+':'-').$_);
          }
          $cstate = $state;
          push(@par,$target);
        }
      } else {
        $user->sendserv('472 '.$user->nick.' '.$_.' :no such mode');
      }
    }
    unshift(@final,'+');
    my $finished = join('',@final);
    $finished =~ s/\+-/-/g;
    $channel->allsend(':'.$user->fullcloak.' MODE '.$channel->name.' '.$finished.' '.join(' ',@par));
  }
}
sub handlestatus {
  my ($channel,$user,$state,$mode,$tuser) = @_;
  if ($mode eq 'q') {
    if ($channel->has($user,'owner')) {
      my $target = user::nickexists($tuser);
      if ($target) {
        if ($target->ison($channel)) {
          $channel->{'owners'}->{$target->{'id'}} = time if $state;
          delete $channel->{'owners'}->{$target->{'id'}} unless $state;
          return 1;
        } else {
          $user->send(join(' ',441,$target->nick,$channel->name,':is not on that channel'));
          return;
        }
      } else {
        $user->sendserv('401 '.$user->nick.' '.$tuser.' :No such nick/channel');
        return;
      }
    } else {
      $user->sendserv('482 '.$user->nick.' '.$channel->name.' :You\'re not a channel owner');
      return;
    }
  } elsif ($mode eq 'a') {
    if ($channel->has($user,'owner') || $channel->has($user,'admin')) {
      my $target = user::nickexists($tuser);
      if ($target) {
        if ($target->ison($channel)) {
          $channel->{'admins'}->{$target->{'id'}} = time if $state;
          delete $channel->{'admins'}->{$target->{'id'}} unless $state;
          return 1;
        } else {
          $user->send(join(' ',441,$target->nick,$channel->name,':is not on that channel'));
          return;
        }
      } else {
        $user->sendserv('401 '.$user->nick.' '.$tuser.' :No such nick/channel');
        return;
      }
    } else {
      $user->sendserv('482 '.$user->nick.' '.$channel->name.' :You\'re not a channel administrator');
      return;
    }
  } elsif ($mode eq 'o') {
    if ($channel->has($user,'owner') || $channel->has($user,'admin') || $channel->has($user,'op')) {
      my $target = user::nickexists($tuser);
      if ($target) {
        if ($target->ison($channel)) {
          $channel->{'ops'}->{$target->{'id'}} = time if $state;
          delete $channel->{'ops'}->{$target->{'id'}} unless $state;
          return 1;
        } else {
          $user->send(join(' ',441,$target->nick,$channel->name,':is not on that channel'));
          return;
        }
      } else {
        $user->sendserv('401 '.$user->nick.' '.$tuser.' :No such nick/channel');
        return;
      }
    } else {
      $user->sendserv('482 '.$user->nick.' '.$channel->name.' :You\'re not a channel operator');
      return;
    }
  } elsif ($mode eq 'h') {
    if ($channel->has($user,'owner') || $channel->has($user,'admin') || $channel->has($user,'op')) {
      my $target = user::nickexists($tuser);
      if ($target) {
        if ($target->ison($channel)) {
          $channel->{'halfops'}->{$target->{'id'}} = time if $state;
          delete $channel->{'halfops'}->{$target->{'id'}} unless $state;
          return 1;
        } else {
          $user->send(join(' ',441,$target->nick,$channel->name,':is not on that channel'));
          return;
        }
      } else {
        $user->sendserv('401 '.$user->nick.' '.$tuser.' :No such nick/channel');
        return;
      }
    } else {
      $user->sendserv('482 '.$user->nick.' '.$channel->name.' :You\'re not a channel operator');
      return;
    }
  } elsif ($mode eq 'v') {
    if ($channel->has($user,'owner') || $channel->has($user,'admin') || $channel->has($user,'op') || $channel->has($user,'halfop')) {
      my $target = user::nickexists($tuser);
      if ($target) {
        if ($target->ison($channel)) {
          $channel->{'voices'}->{$target->{'id'}} = time if $state;
          delete $channel->{'voices'}->{$target->{'id'}} unless $state;
          return 1;
        } else {
          $user->send(join(' ',441,$target->nick,$channel->name,':is not on that channel'));
          return;
        }
      } else {
        $user->sendserv('401 '.$user->nick.' '.$tuser.' :No such nick/channel');
        return;
      }
    } else {
      $user->sendserv('482 '.$user->nick.' '.$channel->name.' :You\'re not a channel operator');
      return;
    }
  }
}
sub showtopic {
  my ($channel,$user,$halt) = @_;
  if ($channel->{'topic'}) {
    $user->sendserv('332 '.$user->nick.' '.$channel->name.' :'.$channel->{'topic'}->{'topic'});
    $user->sendserv('333 '.$user->nick.' '.$channel->name.' '.$channel->{'topic'}->{'setby'}.' '.$channel->{'topic'}->{'time'});
  } else {
    $user->sendserv('331 '.$user->nick.' '.$channel->name.' :No topic is set.') unless $halt;
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
    $channel->allsend(':'.$user->fullcloak.' TOPIC '.$channel->name.' :'.$topic);
  } else { $user->sendserv('482 '.$user->nick.' '.$channel->name.' :You\'re not a channel operator'); }
}
sub privmsgnotice {
  my ($channel,$user,$type,$msg) = @_;
  if (($channel->ismode('n') && !$user->ison($channel)) ||
  ($channel->ismode('m') && !$channel->has($user,'owner') && !$channel->has($user,'admin') && !$channel->has($user,'op') && !$channel->has($user,'halfop') && !$channel->has($user,'voice'))
  ) {
    $user->sendserv(join(' ',404,$user->nick,$channel->name,':Cannot send to channel'));
    return;
  }
  $channel->allsend(':'.$user->fullcloak.' '.join(' ',$type,$channel->name,':'.$msg),$user);
}
1
