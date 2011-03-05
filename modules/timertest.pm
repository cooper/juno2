#!/usr/bin/perl -w
package API::timertest;

# all modules must be API::module_name_here

use warnings;
use strict;
use feature 'say';

use API;

# all modules must use API

API::register_module('timertest','0.1','timer test module',\&register,\&unload);

# this registers the module to juno with the following parameters:
# 1. name of the module
# 2. version
# 3. description
# 4. subroutine referred to upon loading
# 5. subroutine referred to upon unloading

sub register {

  # this subroutine will be handled when the module is loaded.

  API::register_command('timertest',\&command_timertest);

  # this registers a user command to juno.
  # the parameters for a command register are as follows:
  # 1. the name of the command (no spaces)
  # 2. the subroutine to be referred to when a user uses the command

  # note: these will be ignored if a command with this name already exists.

  say 'Timer test module loaded successfully!';

  return 1

  # all load subroutines must return true for load success.
  # if the module requires something that is not available on this system
  # or etc, returning false will tell the API module that the module failed
  # to load properly.

}
sub unload {

  # this subroutine is handled when the module is unloaded.

  API::delete_command('timertest');

  # this removes commands that we added in the register subroutine.
  # the only parameter is the name of the command.
  # if this command does not exist, the request will be ignored.

  # note: this is also used for deleting aliases.

  say 'Unloaded timer test module.';

  return 1

  # all unload subroutines must return true for unload success.
  # if a module is not to be unloaded (permanent), return a false value.

}
sub command_timertest {

  # this subroutine is handled when a user uses the hello command,
  # as defined in the register subroutine.
  # the @_ array contains two variables: the user object and the data they sent to juno.

  my ($user,$data) = @_;

  # this defines those two variables  

  say $user->nick.' sent TIMERTEST command. The data is as follows: '.$data;
  
  API::register_timer('timertest'.$user->nick.rand(time),5,sub{

    # this subroutine will be referred to when timer is complete.

    $user->sendserv('NOTICE %s :it has been 5 seconds.',$user->nick);

  });

  # the parameters for register_timer are as follows:
  # 1. the name of the timer
  # 2. the number of seconds to wait
  # 3. the subroutine to referred to when the timer is finished
  # note: the timer name in this example contains the user's nick
  # and a random number.

  # using a name that is likely to change is a good idea otherwise
  # the timer will be reset each time it is referred to.

  return 1

}

1
# all modules must return a true value.
