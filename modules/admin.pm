#!/usr/bin/perl
# Copyright (c) 2011, Ethan Best

# Displays server administrator info
package module::Admin;
use strict;
use warnings;
use utils 'conf';

use API::Module 'register_module';
use API::Command 'register_command';
register_module('Admin', 0.1, 'Displays server administrator info', \&init, sub { return 1 });

sub init {
	register_command('admin', 'View server admin info', sub {
	    my $user = shift;
	    my $server = conf qw/server name/;
	    $user->sendnum(256, ":Administrative info about $server");
	    my $line1 = conf qw/admin line1/;
	    $user->sendnum(257, ":$line1");
	    my $line2 = conf qw/admin line2/;
	    $user->sendnum(258, ":$line2");
	    my $line3 = conf qw/admin line3/;
	    $user->sendnum(259, ":$line3");
	    return 1
	}) or return;
	return 1
}

1
