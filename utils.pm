#!/usr/bin/perl -w
# Copyright (c) 2011, Mitchell Cooper
package utils;

use warnings;
use strict;
use feature 'say';
use base 'Exporter';

use Exporter;

our @EXPORT_OK = qw/col validnick validcloak hostmatch snotice fatal conf oper/;
our %GV;

# numeric hash
# I don't really have anywhere else to put this, so I'll just throw it in here!
# these are used by user::numeric()
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
    319 => '%s :%s',
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

sub col {
    my $str = shift;
    return unless defined $str;
    $str =~ s/^://;
    return $str
}

sub validnick {
    my ($str,$limit,$i) = @_;
    return if length $str < 1 || length $str > $limit;
    return if $str =~ m/^\d/ && !$i;
    return if $str =~ m/[^A-Za-z-0-9-\[\]\\\`\^\|\{\}\_]/;
    return 1
}

sub hostmatch {
    my ($mask,@list) = @_;
    my @aregexps;
    foreach my $regexp (@list) {
        $regexp =~ s/\./\\\./g;
        $regexp =~ s/\?/\./g;
        $regexp =~ s/\*/\.\*/g;
        $regexp = '^'.$regexp.'$';
        push(@aregexps,lc $regexp)
    }
    return 1 if (grep {lc $mask =~ /$_/} @aregexps);
    return
}

sub snotice {
    my $msg = shift;
    foreach (values %user::connection) {
        $_->sendserv('NOTICE '.$_->nick.' :*** Server notice: '.$msg) if ($_->ismode('o') && $_->ismode('S'))
    }
}

sub fatal {
    say 'FATAL: '.shift;
    exit (shift() ? 1 : 0)
}

sub conf {
    my ($key,$val) = @_;
    return $::config{$key}{$val} if exists $::config{$key}{$val};
    return
}

sub oper {
    my ($key,$val) = @_;
    return $::oper{$key}{$val} if exists $::oper{$key}{$val};
    return
}

sub validcloak {
    return if $_[0] =~ m/[^A-Za-z-0-9-\.\/\-]/;
    return 1
}

1
