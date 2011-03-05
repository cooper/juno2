#!/usr/bin/perl -w
package API;
use warnings;
use strict;
use less 'mem';
use feature qw(say switch);
use Class::Unload;
our %modules; # name (version,desc,loadref,unloadref)
sub load_modules {
  my $modules = ::conf('main','modules') or return;
  foreach (split ',', $modules) {
    require 'modules/'.$_.'.pm' or die 'could not load module '.$_;
  }
}
sub do_module {
  my $name = shift;
  do 'modules/'.$name'.pm' or return;
}
sub register_module {
  # $module,$version,$desc,$loadref,$unloadref
  my $name = shift;
  if ($_[2]()) {
    say 'Module registered: '.$name;
    $modules{$name} = @_;
    return 1
  } else {
    say 'Module '.$name.' refused to load.';
    return
  }
}
sub register_command {
  my $command = uc shift;
  if (defined $user::commands{$command}) {
    say 'API error: '.$command.' is already a registered command; ignoring register.';
    return
  }
  $user::commands{$command} = shift;
  return 1
}
sub register_alias {
  my($name,$command) = (uc shift, uc shift);
  my @args = @_;
  if (!defined $user::commands{$command}) {
    say 'API error: '.$command.' is not a registered command; ignoring alias register.';
    return
  }
  say 'Registering alias '.$name.' to '.$command;
  register_command($name,sub {
    shift->handle($command,$command.' '.join(' ',@args));
  });
}
sub delete_module {
  my $name = uc shift;
  if ($modules{$name}[3]()) {
    say 'Unloading module '.$name;
    delete $modules{$name};
    Class::Unload->unload('API::'.$name); 
  } else {
    say 'Module '.$name.' refused to unload.'
  }
}
sub delete_command {
  my $command = uc shift;
  if (!defined $user::commands{$command}) {
    say 'API error: '.$command.' is not a registered command; ignoring delete.';
    return
  }
  delete $user::commands{$command};
  return 1
}
1;
package API::loadunload;
use warnings;
use strict;
use less 'mem';
use feature 'say';
API::register_module('loadunload','0.1','Commands MODLOAD and MODUNLOAD',
  sub{
    API::register_command('modload',\&handle_modload);
    API::register_command('modunload',\&handle_modunload);
    return 1
  },
  sub{
    say 'Warning: attempted to unload core MODLOAD and MODUNLOAD modules.';
    return
  }
);
sub handle_modload {
  my $user = shift;
  my $name = (split(' ',shift))[1];
  $user->numeric(461,'MODLOAD'), return if !defined $name;
  if ($user->can('modload')) {
    ::snotice($user->nick.' is attempting to load API module '.$name);
    if (-e 'modules/'.$name) {
      if(API::do_module($name)) {
        ::snotice('do_module succeeded, attempting to register module '.$name);
        $user->sendserv('NOTICE %s :do_module succeeded, attempting to register module.',$user->nick);
      } else {
        ::snotice('do_module failed - probably a syntax error in '.$name);
        $user->sendserv('NOTICE %s :do_module failed - probably a syntax error.',$user->nick);
        return
      }
    } else {
      ::snotice($name.' failed to load: no such file or directory');
      $user->sendserv('NOTICE %s :No such file or directory',$user->nick);
      return
    }
  } else {
    $user->numeric(481);
  }
}
sub handle_modunload {
}
1
