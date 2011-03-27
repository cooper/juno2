#!/usr/bin/perl -w
package handle;
use warnings;
use strict;
use less 'mem';
use utils qw/col validnick conf/;
sub new {
    my $user = user::lookup(shift) or return;
    my $all = shift;
    foreach my $data (split "\n", $all) {
        $data =~ s/\s+$//;
        $data =~ s/^\s+//;
        return if $data eq '';
        ($user->{'ping'},$user->{'last'}) = (time,time);
        my @s = split / /, $data;
        $user->{'idle'} = time unless $s[0] =~ m/^(PONG|PING)$/i;
        if ($user->{'ready'}) {
            $user->handle($s[0],$data);
        } else {
            if (uc($s[0]) eq 'NICK') {
                if ($s[1]) {
                    if (validnick($s[1],conf('limit','nick'),undef)) {
                        unless(user::nickexists($s[1])) {
                            $user->{'nick'} = $s[1];
                            if (exists $user->{'ident'}) {
                                $user->{'ready'} = 1;
                                $user->start;
                            }
                        } else { $user->sendserv('433 '.$user->nick.' '.$s[1].' :Nickname is already in use.'); }
                    } else { $user->sendserv('432 '.$user->nick.' '.$s[1].' :Erroneous nickname'); }
                } else { $user->sendnum(431,':No nickname given'); }
            } elsif (uc($s[0]) eq 'USER') { 
                if (exists $s[4]) {
                    if (validnick($s[1],conf('limit','ident'),1)) {
                        $user->{'gecos'} = col((split / /, $data, 5)[4]);
                        $user->{'ident'} = '~'.$s[1];
                        if (exists $user->{'nick'}) {
                            $user->{'ready'} = 1;
                            $user->start;
                        }
                    } else { $user->sendserv('461 '.$user->nick.' USER :Your username is not valid'); }
                } else { $user->sendserv('461 '.$user->nick.' USER :Not enough parameters'); }
            } else { $user->sendserv('421 '.$user->nick.' '.uc($s[0]).' :Unknown command') unless uc($s[0]) eq 'PONG' or uc($s[0]) eq 'CAP'; }
        }
    }
}
1
