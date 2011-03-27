#!/usr/bin/perl -w
package utils;
use warnings;
use strict;
use less 'mem';
use base 'Exporter';
use Exporter;
our @EXPORT_OK = qw/col validnick validcloak hostmatch snotice fatal conf oper/;
our %GV;
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
    exit
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
