#!/usr/bin/perl -w
$0 = 'juno';
our $TIME = time;
use warnings;
use strict;
use less;
use POSIX;
#use Socket;
#use Net::DNS;
#use Net::IP;
use IO::Select;
use IO::Socket;
use user;
use handle;
use channel;
$SIG{'INT'} = \&sigexit;
&POSIX::setsid;
our (%config,%oper,%outbuffer,%inbuffer,%timer);
confparse('ircd.conf');
require IO::Socket::INET6 if conf('listen6','addr');
our $id = conf('server','id');
my ($socket4,$socket6);
if (conf('listen6','addr')) {
  $socket6 = IO::Socket::INET6->new(
    Proto => 'tcp',
    Listen => 1,
    ReuseAddr => 1,
    LocalPort => conf('listen6','port'),
    LocalAddr => conf('listen6','addr')
  );
} else { $socket6 = 0; }
if (conf('listen4','addr')) {
  $socket4 = IO::Socket::INET->new(
    Proto => 'tcp',
    Listen => 1,
    ReuseAddr => 1,
    LocalPort => conf('listen4','port'),
    LocalAddr => conf('listen4','addr')
  );
} else { $socket4 = 0; }
my @sel = ();
push(@sel,$socket6) if conf('listen6','addr');
push(@sel,$socket4) if conf('listen4','addr');
die 'not listening' if !$socket4 and !$socket6;
our $select = new IO::Select(@sel);
for(;;) {
  my $time;
  foreach my $peer ($select->can_read(conf('main','timeout'))) {
    $timer{$peer} = 0 unless $timer{$peer};
    if ($peer == $socket4) {
      user::new($socket4->accept);
    } elsif ($peer == $socket6) {
      user::new($socket6->accept);
    } else {
      my $data;
      $time = time;
      $timer{$peer} = $time if $timer{$peer} < $time;
      my $got = $peer->sysread($data,POSIX::BUFSIZ);
      if ($got) {
        #handle::new($peer,$data);
        $inbuffer{$peer} .= $data;
      } else {
        user::lookup($peer)->quit('Read error',1);
      }
    } my ($theline,$therest);
    next unless defined $inbuffer{$peer};
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
  return undef;
}
sub confparse {
  my $file = shift;
  open(CONF,'<',$file) or die 'can not open configuration file '.$file;
  my ($section,$opersection);
  while (<CONF>) {
    my $line = $_;
    $line =~ s/\t//g;
    $line =~ s/^\s+//;
    $line =~ s/\s+$//;
    next if $line eq '';
    next if $line =~ m/^#/;
    my @s = split(' ',$line,2);
    if ($s[0] eq 'sec') {
      $section = $s[1];
      next;
    } elsif ($s[0] eq 'inc') {
      confparse($s[1]);
    } elsif ($s[0] eq 'oper') {
      $section = 0;
      $opersection = $s[1];
    } elsif ($s[0] eq 'die') {
      die $s[1];
    } else {
      if ($section) {
        $config{$section}{$s[0]} = $s[1];
      } elsif ($opersection) {
        $oper{$opersection}{$s[0]} = $s[1];
      } else { die 'no section set in configuration'; }
    }
  }
  close CONF;
}
sub validnick {
  my ($str,$limit,$i) = @_;
  return undef if(length($str)<1 || length($str)>$limit);
  return undef if($str=~m/^\d/ && !$i);
  return undef if $str=~m/[^A-Za-z-0-9-\[\]\\\`\^\|\{\}\_]/;
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
  return 0;
}
