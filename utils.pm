#!/usr/bin/perl -w
# Copyright (c) 2011, Mitchell Cooper
package utils;

use warnings;
use strict;
use feature 'say';
use base 'Exporter';

use Exporter;

our @EXPORT_OK = qw/col validnick validcloak hostmatch snotice fatal conf oper cut_to_limit add_commas
  time2seconds/;
our %GV;

# numeric hash
# I don't really have anywhere else to put this, so I'll just throw it in here!
# these are used by user::numeric()

our %numerics = (
    251 => ':There are %s users and %s invisible on %s servers',
    252 => '%d :IRC operators online',
    254 => '%d :channels formed',
    255 => 'I have %d clients and %d servers',
    265 => '%d %d :Current local users %s, max %s',
    267 => '%d %d :Current global users %s, max %s',
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
    402 => '%s :No such server',
    403 => '%s :Invalid channel name',
    403.1 => '%s :No such channel',
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
    461.1 => 'USER :Your username is not valid',
    462 => ':You may not reregister',
    471 => '%s :Cannot join channel (channel limit reached)',
    472 => '%s :No such mode',
    473 => '%s :Cannot join channel (channel is invite only)',
    474 => '%s :Cannot join channel (you\'re banned)',
    475 => '%s :Cannot join channel (Incorrect channel key)',
    481 => ':Permission denied',
    482 => '%s :You\'re not a channel %s',
    482.1 => '%s :You do not have the proper privileges to kick this user',
    491 => ':Invalid oper credentials',
    501 => '%s :No such mode',
    641 => '%s :is using a secure connection',
    728 => '%s %s %s %s',
    729 => '%s :End of channel mute list',
);

# remove a prefixing colon

sub col {
    my $str = shift;
    return unless defined $str;

    # remove the colon from the front if there is one
    $str =~ s/^://;

    return $str
}

# check if a nickname is valid
sub validnick {
    my ($str, $limit, $i) = @_;

    # valid characters
    return if (
        length $str < 1 || length $str > $limit ||
        ($str =~ m/^\d/ && !$i) ||
        $str =~ m/[^A-Za-z-0-9-\[\]\\\`\^\|\{\}\_]/
    );

    # success
    return 1

}

# match a host to a list
sub hostmatch {
    my ($mask, @list) = @_;
    $mask = lc $mask;
    my @aregexps;

    foreach my $regexp (@list) {

        # replace wildcards with regex
        $regexp =~ s/\./\\\./g;
        $regexp =~ s/\?/\./g;
        $regexp =~ s/\*/\.\*/g;
        $regexp = '^'.$regexp.'$';
        push @aregexps, lc $regexp

    }

    # success
    return 1 if grep { $mask =~ m/$_/ } @aregexps;

    # no matches
    return

}

# send a server notice to users with S enabled
sub snotice {
    my $msg = shift;
    $msg =~ s/\s+$//;

    # send to all users with +S enabled
    foreach my $user (values %user::connection) {
        $user->snt('Server notice', $msg) if $user->ismode('S')
    }

    return 1

}

# force exit
sub fatal {
    say 'FATAL: '.shift;
    exit (shift() ? 1 : 0)
}

# fetch a configuration value
sub conf {
    my ($key, $val) = @_;
    return $main::config{$key}{$val} if exists $main::config{$key}{$val};

    # no such key (or block, even)
    return

}

# fetch info from a configuration oper block
sub oper {
    my ($key, $val) = @_;
    return $main::oper{$key}{$val} if exists $main::oper{$key}{$val};

    # no such key (or block, even)
    return

}

# check if cloak is valid
sub validcloak {
    return if shift() =~ m/[^A-Za-z-0-9-\.\/\-]/;
    return 1
}

# cut a string to its limit defined by the 'limit' section
sub cut_to_limit {
    my ($limit, $string) = (conf('limit', shift), shift);

    # if no limit is set, return the supplied string
    return $string unless $limit;

    my $overflow = (length $string) - $limit;

    # chop to limit
    $string = substr $string, 0, -$overflow if length $string > $limit;

    return $string
}

# add commas to a number where necessary
sub add_commas {

    my $number = reverse shift;
    my $in_group = 0;
    my $finished = q..;

    # find groups of three
    foreach ($number =~ m/.../g) {
        $in_group += 3;
        $finished = reverse.",$finished"
    }

    my $result = $finished;

    # if the number is not a multiple of 3
    if (length($number) % 3) {
        my $overflow = length($number) - $in_group;
        $result = reverse(substr $number, -$overflow).",$finished";
    }

    # throw what's left in front of it.
    $result = substr $result, 0, -1 if $result =~ m/,$/;

    return $result
}

sub time2seconds {
    my $rtime = shift;
    my $time = 0;
    # must be even
    return if (length $rtime) % 2;

    # split into groups of two
    foreach my $sec ($rtime =~ m/../g) {
        my ($num, $type) = split //, $sec;

        #has to start with a digit and end with a non-digit
        return unless $sec =~ m/^\d.*\D/;

        given ($type) {

            # years 
            when ('y') {
                $time += 31556926 * $num
            }
 
            # weeks
            when ('w') {
                $time += 604800 * $num
            }

            # days
            when ('d') {
                $time += 86400 * $num
            }

            # hours
            when ('h') {
                $time += 3600 * $num
            }

            # minutes
            when ('m') {
                $time += 60 * $num
            }

            # seconds
            when ('s') {
                $time += $num
            }

        }

    }

    return $time
}

1
