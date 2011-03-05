#!/usr/bin/perl -w
package API;
use warnings;
use strict;
use less 'mem';
use feature qw(say switch);
use Class::Unload;
our %modules; # (version,desc,loadref,unloadref)
sub load_modules {
  my $modules = ::conf('main','modules') or return;
  foreach (split ',', $modules) {
    require 'modules/'.$_ or die 'could not load module '.$_;
  }
}
sub register_module {
  # $module,$version,$desc,$loadref,$unloadref
  my $name = shift;
  say 'Module registered: '.$name;
  $_[2]();
  $modules{$name} = @_;
  return 1
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
  my $name = shift;
  say 'Unloading module '.$name;
  Class::Unload->unload('API::'.$name);
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
1
