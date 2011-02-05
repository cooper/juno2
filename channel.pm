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
  my $i = 0;
  $i++ foreach (keys %{$channel->{'users'}});
  delete $channels{lc($channel->name)} if $i == 0;
  ::snotice('dead channel: '.$channel->name) if $i == 0;
}
sub names {
  my ($channel,$user) = @_;
  my $names = '';
  foreach (keys %{$channel->{'users'}}) {
    my $u = user::lookupbyid($_);
    next if ($u->ismode('i') and !$user->ison($channel));
    $names .=
    (defined $channel->{'owners'}->{$_}?'~':'').
    (defined $channel->{'admins'}->{$_}?'&':'').
    (defined $channel->{'ops'}->{$_}?'@':'').
    (defined $channel->{'halfops'}->{$_}?'%':'').
    (defined $channel->{'voices'}->{$_}?'+':'').
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
sub name { return shift->{'name'}; }
sub handlemode {
  my ($channel,$user,@modestr) = @_;
  my $str = "@modestr";
  $str =~ s/\s+$//;
  if ($str eq '' || !$str) {
    my ($all,$params) = ('','');
    foreach (keys %{$channel->{'mode'}}) {
      $all .= $_;
      $params .= $channel->{'mode'}->{$_}->{'params'}.' ' if defined $channel->{'mode'}->{$_}->{'params'};
    }
    $user->sendserv(join(' ',324,$user->nick,$channel->name,'+'.$all,$params));
    $user->sendserv(join(' ',329,$user->nick,$channel->name,$channel->{'first'}));
  } else {
    
  }
}
1
