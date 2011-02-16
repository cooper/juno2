#!/usr/bin/perl -w
use warnings;
use strict;
use less 'mem';
use feature qw(say switch);
use POSIX;
use IO::Select;
use IO::Socket;
use user;
use handle;
use channel;
local $0 = 'juno';
our $VERSION = 'dev-0.4.8';
our $TIME = time;
our $CONFIG = './etc/ircd.conf';
my $NOFORK = 0;
my $PID = 0;
$SIG{'INT'} = \&sigint;
$SIG{'HUP'} = \&sighup;
our (%config,%oper,%kline,%listen,%outbuffer,%inbuffer,%timer);
my (%listensockets,%SSL,@sel,$ipv6);
&handleargs;
confparse($CONFIG);
&loadrequirements;
&createsockets;
unless ($NOFORK) {
  say 'Becoming a daemon...';
  open STDIN,  '/dev/null' or die "Can't read /dev/null: $!";
  open STDOUT, '>/dev/null';
  open STDERR, '>/dev/null';
  open my $pidfile,'>','./etc/juno.pid' or die 'could not write etc/juno.pid';
  $PID = fork;
  say 'Started as '.$PID;
  say $pidfile $PID;
  close $pidfile;
}
exit if ($PID != 0);
&POSIX::setsid;
our $id = conf('server','id');
die 'not listening' if $#sel < 0;
our $select = new IO::Select(@sel);
for(;;) {
  my $time;
  foreach my $peer ($select->can_read(conf('main','timeout'))) {
    $timer{$peer} = 0 unless $timer{$peer};
    if ($listensockets{$peer}) {
      user::new(($SSL{$peer}?1:0),$peer->accept);
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
      unless (user::lookup($peer)) { delete $inbuffer{$peer}; next }
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
    my $last = time-$client->{'last'};
    if ($last > conf('ping','timeout')) {
      my $ping = conf('ping','msg');
      $ping =~ s/\%s/$last/g;
      $client->quit($ping,undef);
    }
  }
}
sub sendpeer {
  my $peer = shift;
  foreach (@_) {
    $outbuffer{$peer} .= $_."\r\n";
  }
}
sub sigint {
  say 'exiting by signal';
  sleep 1;
  die;
}
sub sighup {
  snotice('Receieved SIGHUP, rehashing server configuration file.');
  confparse($CONFIG);
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
  my @sections;
  while (my $line = <$CONF>) {
    $line =~ s/\t//g;
    $line =~ s/^\s+//;
    $line =~ s/\s+$//;
    next if $line eq '';
    next if $line =~ m/^#/;
    my @s = split(' ',$line,2);
    given($s[0]) {
      when('sec') {
        @sections = ($s[1],0,0,0);
      } when('inc') {
        @sections = (0,0,0,0);
        confparse($s[1]);
      } when('oper') {
        @sections = (0,$s[1],0,0);
      } when('kline') {
        @sections = (0,0,$s[1],0);
      } when('listen') {
        @sections = (0,0,0,$s[1]);
      } default {
        if ($sections[0]) {
          $config{$sections[0]}{$s[0]} = $s[1];
        } elsif ($sections[1]) {
          $oper{$sections[1]}{$s[0]} = $s[1];
        } elsif ($sections[2]) {
          $kline{$sections[2]}{$s[0]} = $s[1];
        } elsif ($sections[3]) {
          $listen{$sections[3]}{$s[0]} = $s[1];
        } else { die 'no section set in configuration'; }
      }
    }
    $_->checkkline foreach values %user::connection;
  }
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
  foreach my $regexp (@list) {
    $regexp =~ s/\./\\\./g;
    $regexp =~ s/\?/\./g;
    $regexp =~ s/\*/\.\*/g;
    $regexp = '^'.$regexp.'$';
    push(@aregexps,$regexp);
  }
  return 1 if (grep {$mask =~ /$_/} @aregexps);
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
      last if $port == 0;
      say "listening on $name:$port";
      if ($ipv6) {
        $socket = IO::Socket::INET6->new(
          Listen => 1,
          ReuseAddr => 1,
          LocalPort => $port,
          LocalAddr => $name
        ) or die 'could not listen: block '.$name.':'.$port.': '.$!;
      } else {
        $socket = IO::Socket::INET->new(
          Listen => 1,
          ReuseAddr => 1,
          LocalPort => $port,
          LocalAddr => $name
        ) or die 'could not listen: block '.$name.':'.$port.': '.$!;
      }
      push(@sel,$socket) if $socket;
      $listensockets{$socket} = $port if $socket;
    }
    foreach my $port (split(' ',$listen{$name}{'ssl'})) {
      last if $port == 0;
      say "listening on $name:$port";
      $socket = IO::Socket::SSL->new(
        Listen => 1,
        ReuseAddr => 1,
        LocalPort => $port,
        LocalAddr => $name,
        SSL_cert_file => conf('ssl','cert'),
        SSL_key_file => conf('ssl','key')
        ) or die 'could not listen (SSL): block '.$name.':'.$port.': '.$!;
      if ($socket) {
        push(@sel,$socket);
        $listensockets{$socket} = $port;
        $SSL{$socket} = 1;
      }
    }
  }
}
sub col {
  my $str = shift;
  return unless defined $str;
  return $str unless $str =~ m/^:/;
  $str =~ s/://;
  return $str;
}
sub loadrequirements {
  if (conf('enabled','ipv6')) {
    $ipv6 = 1;
    require IO::Socket::INET6;
  }
  if (conf('enabled','ssl')) {
    require IO::Socket::SSL;
    IO::Socket::SSL->import('inet6') if (conf('enabled','ipv6'));
  }
}
sub handleargs {
print <<EOF;
\t   _                     _              _
\t  (_)                   (_)            | |
\t   _ _   _ _ __   ___    _ _ __ ___  __| |
\t  | | | | | '_ \\ / _ \\  | | '__/ __|/ _` |
\t  | | |_| | | | | (_) |-| | | | (__| (_| |
\t  | |\\__,_|_| |_|\\___/  |_|_|  \\___|\\__,_|
\t _/ |
\t|__/   development version $VERSION

EOF
  foreach (@ARGV) {
    my @s = split('=',$_);
    given($s[0]) {
      when('--rehash') {
        open my $pidfile,'<','./etc/juno.pid' or die 'juno-ircd is not running!';
        my $pid = <$pidfile>; chomp $pid;
        close $pid;
        say 'Signaling '.$pid.' HUP';
        say 'Rehashed server configuration.';
        kill 'HUP',$pid;
        exit;
      } when ('--config') {
        $CONFIG = $s[1] if $s[0] eq '--config';
      } when('--nofork') {
        $NOFORK = 1 if $s[0] eq '--nofork';
      } default {
print <<EOF;
usage: perl juno.pl
\t[--config=/path/to/config]
\t[--rehash]
\t[--nofork]
EOF
exit;
      }
    }
  }
}
