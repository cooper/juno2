#!/usr/bin/perl -w
package API::helloworld;
# all modules must be API::module_name_here
use warnings;
use strict;
use feature 'say';
use API;
# all modules must use API

API::register_module('helloworld','0.1','Hello world module',\&register,\&unload);
# this registers the module to juno with the following parameters:
# 1. name of the module
# 2. version
# 3. description
# 4. subroutine referred to upon loading
# 5. subroutine referred to upon unloading

sub register {
  # this subroutine will be handled when the module is loaded.

  API::register_command('hello',\&command_hello);
  # this registers a user command to juno.
  # the parameters for a command register are as follows:
  # 1. the name of the command (no spaces)
  # 2. the subroutine to be referred to when a user uses the command

  # note: these will be ignored if a command with this name already exists.

  API::register_alias('sayhitotom','PRIVMSG','tom :hi');
  # this is a virtual command that lies to the user command handler
  # and pretends like the user sent the following data by these arguments:
  # 1. the command to register
  # 2. the command to imitate
  # 3 (optional). the arguments of the command

  # note: aliases are registered as normal commands.
  # for this reason, there is no such thing as delete_alias; you simply
  # use the delete_command function instead.

  say 'Hello world module loaded successfully!';

}
sub unload {
  # this subroutine is handled when the module is unloaded.

  API::delete_command('hello');
  # this removes the hello command that we added in the register subroutine.
  # the only parameter is the name of the command.
  # if this command does not exist, the request will be ignored.

  say 'Unloaded hello world module.';

}
sub command_hello {
  # this subroutine is handled when a user uses the hello command,
  # as defined in the register subroutine.
  # the @_ array contains two variables: the user object and the data they sent to juno.

  my ($user,$data) = @_;
  # this defines those two variables  

  say $user->nick.' sent HELLO command. The data is as follows: '.$data;
  
  $user->sendserv('NOTICE %s :Hello World!',$user->nick);
  # this sends a server notice to the user who used the command: Hello World!

}

1
# all modules must return a true value.
