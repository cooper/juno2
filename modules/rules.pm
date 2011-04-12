#!/usr/bin/perl
# Copyright (c) 2011, Ethan Best
# Special thanks to Mitchell for helping me out.

# Displays server rules
package module::Rules;
use strict;
use warnings;
use utils 'conf';

use API::Module 'register_module';
use API::Command 'register_command';
register_module('Rules', 0.1, 'View network rules', \&init, sub { return 1 });

sub init {
	register_command('rules', 'View network rules', sub {
        my ($user, $data) = @_;
	my $open = open (my $filehandle, '<', conf('rules', 'file'));
	if (!$open) { 
	$user->sendnum(232, ":Rules file is missing.");
	return } 
	my $server = conf qw/server name/;
	$user->sendnum(232, ":$server rules");
	while (my $rules = <$filehandle>) {
		chop $rules;
        	$user->sendnum(232, ":- $rules");
	}
	$user->sendnum(309, ":End of rules.");
	close $filehandle;
        return 1
    }) or return;
    return 1
}

1
