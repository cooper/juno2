#!/usr/bin/perl -w
use warnings;
use strict;
use less 'mem';
use POSIX;
use IO::Select;
use IO::Socket;
use user;
use handle;
use channel;
$0 = 'juno';
our $TIME = time;
$SIG{'INT'} = \&sigexit;
&POSIX::setsid;
our (%config,%oper,%kline,%listen,%outbuffer,%inbuffer,%timer);
my (%listensockets,@sel,$ipv6);
confparse('ircd.conf');
&createsockets;
our $id = conf('server','id');
die 'not listening' if $#sel < 0;
our $select = new IO::Select(@sel);
for(;;) {
  my $time;
  foreach my $peer ($select->can_read(conf('main','timeout'))) {
    $timer{$peer} = 0 unless $timer{$peer};
    if ($listensockets{$peer}) {
      user::new($peer->accept);
    } else {
      my $data;
      $time = time;
      $timer{$peer} = $time if $timer{$peer} < $time;
      my $got = $peer->sysread($data,POSIX::BUFSIZ);
      if ($got) {
        $inbuffer{$peer} .= $data;
      } else {
        user::lookup($peer)->quit('Read error',1);
        next;
      }
    } my ($theline,$therest);
    if($inbuffer{$peer}) {
      while(($timer{$peer}-conf('flood','lines') <= $time) && (($theline,$therest) = $inbuffer{$peer} =~ m/([^\n]*)\n(.*)/s)) {
        $inbuffer{$peer} = $therest;
        $theline=~s/\r$//;
        handle::new($peer,$theline);
        $timer{$peer}++;
      }
      if(length $inbuffer{$peer} > conf('flood','bytes')) {
        user::lookup($peer)->quit(conf('flood','msg'));
      }
    }
  }
  foreach my $client ($select->can_write(0)) {
    next unless $outbuffer{$client};
    my $sent = $client->syswrite($outbuffer{$client},POSIX::BUFSIZ);
    if(!defined($sent)) { next; }
    if(($sent <= length($outbuffer{$client})) || ($! == POSIX::EWOULDBLOCK)) {
        substr($outbuffer{$client},0,$sent) = '';
      if(!length($outbuffer{$client})) {
      	delete($outbuffer{$client});
      }
    } else {
	    my $user = user::lookup($client);
	    $user->quit('Write error',1);
      next;
    }
  }
  foreach (values %user::connection) {
    my $client = $_;
    if ((time-$client->{'ping'}) > conf('ping','freq')) {
      $client->send('PING :'.conf('server','name'));
      $client->{'ping'} = time;
      $client->quit('Registration timeout') unless $client->{'ready'};
    }
    if ((time-$client->{'last'}) > conf('ping','timeout')) {
      $client->quit(conf('ping','msg'),undef);
    }
  }
}
sub sendpeer {
  my $peer = shift;
  foreach (@_) {
    $outbuffer{$peer} .= $_."\r\n";
  }
}
sub sigexit {
  # add a loop here later
  print "\nexiting by signal.\n";
  sleep 1;
  die;
}
sub conf {
  my ($key,$val) = @_;
  return $config{$key}{$val} if exists $config{$key}{$val};
  print 'configuration option missing: '.$key.':'.$val."\n";
}
sub oper {
  my ($key,$val) = @_;
  return $oper{$key}{$val} if exists $oper{$key}{$val};
  return;
}
sub confparse {
  my $file = shift;
  open(my $CONF,'<',$file) or die 'can not open configuration file '.$file;
  my ($section,$opersection,$klinesection,$listensection);
  while (<$CONF>) {
    my $line = $_;
    $line =~ s/\t//g;
    $line =~ s/^\s+//;
    $line =~ s/\s+$//;
    next if $line eq '';
    next if $line =~ m/^#/;
    my @s = split(' ',$line,2);
    if ($s[0] eq 'sec') {
      $section = $s[1];
      $opersection = 0;
      $klinesection = 0;
      $listensection = 0;
      next;
    } elsif ($s[0] eq 'inc') {
      $opersection = 0;
      $klinesection = 0;
      $section = 0;
      $listensection = 0;
      confparse($s[1]);
    } elsif ($s[0] eq 'oper') {
      $section = 0;
      $klinesection = 0;
      $opersection = $s[1];
      $listensection = 0;
    } elsif ($s[0] eq 'kline') {
      $section = 0;
      $opersection = 0;
      $klinesection = $s[1];
      $listensection = 0;
    } elsif ($s[0] eq 'listen') {
      $section = 0;
      $opersection = 0;
      $klinesection = 0;
      $listensection = $s[1];
    } elsif ($s[0] eq 'die') {
      die $s[1];
    } else {
      if ($section) {
        $config{$section}{$s[0]} = $s[1];
      } elsif ($listensection) {
        $listen{$listensection}{$s[0]} = $s[1];
      } elsif ($opersection) {
        $oper{$opersection}{$s[0]} = $s[1];
      } elsif ($klinesection) {
        $kline{$klinesection}{$s[0]} = $s[1];
      } else { die 'no section set in configuration'; }
    }
  }
  $_->checkkline foreach values %user::connection;
  close $CONF;
}
sub validnick {
  my ($str,$limit,$i) = @_;
  return if(length($str)<1 || length($str)>$limit);
  return if($str=~m/^\d/ && !$i);
  return if $str=~m/[^A-Za-z-0-9-\[\]\\\`\^\|\{\}\_]/;
  return 1;
}
sub hostmatch {
  my ($mask,@list) = @_;
  my @aregexps;
  foreach(@list) {
    my $regexp = $_;
    $regexp =~ s/\./\\\./g;
    $regexp =~ s/\?/\./g;
    $regexp =~ s/\*/\.\*/g;
    $regexp = '^'.$regexp.'$';
    push(@aregexps,$regexp);
  }
  if(grep {$mask =~ /$_/} @aregexps) {
    return 1;
  }
  return;
}
sub snotice {
  my $msg = shift;
  foreach (values %user::connection) {
    $_->sendserv('NOTICE '.$_->nick.' :*** Server notice: '.$msg) if ($_->ismode('o') && $_->ismode('S'));
  }
}
sub createsockets {
  foreach my $name (keys %listen) {
    my $socket;
    foreach my $port (split(' ',$listen{$name}{'port'})) {
      if ($listen{$name}{'ipv'} == 6) {
        $socket = IO::Socket::INET6->new(
          Listen => 1,
          ReuseAddr => 1,
          LocalPort => $port,
          LocalAddr => $name
        ) or die 'could not listen: block '.$name;
        unless ($ipv6) {
          require IO::Socket::INET;
          $ipv6 = 1;
        }
      } elsif ($listen{$name}{'ipv'} == 4) {
        $socket = IO::Socket::INET->new(
          Listen => 1,
          ReuseAddr => 1,
          LocalPort => $port,
          LocalAddr => $name
        ) or die 'could not listen: block '.$name;
      } else { die 'unknown IP version? block '.$name; }
      push(@sel,$socket) if $socket;
      $listensockets{$socket} = $listen{$name}{'port'};
    }
  }
}
