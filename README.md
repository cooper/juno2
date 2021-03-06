# juno-ircd documentation

Make sure you check out the [wiki](https://github.com/cooper879/juno/wiki). It is full of useful information.

# read this.

This is the second version of juno-ircd.
It was written from scratch rather than based on pIRCd as the [first one](https://github.com/cooper879/juno-ircd) was.
It's much cleaner, has more features, and is more modern than pIRCd.
However, it has a major disadvantage. It doesn't support server linking.
It doesn't even have a linking protocol or the ability to create sockets from server to server.
It was originally planned to wait until the core component were finished to create a linking protocol,
and that would have worked; but now that much of juno has been based on the single-serverness of it,
creating a linking protocol would require so much editing that it may as well be rewritten from scratch again.
I decided that rather than rewriting the majority of user.pm and channel.pm, I'm going to start over.
I will, however, follow many of the design concepts that I have already used in this version of juno.
I will also use the same API structure.

## about

In July 2010, I found pIRCd, the perl internet relay chat daemon. while
learning Perl, I added a few more features to it; however, I caused several
disadvantages, bugs, and memory failures. I decided to start over from scratch
because if I wrote it myself I would understand more how to modify it and work
around the issues that I had when I was working on the perl IRC daemon that Jay
Kominek wrote 13 years ago. It is written mostly from scratch; however, I will
not take credit for the many concepts from pIRCd that I have used in my writing.

## license

juno-ircd is Copyright (c) 2011, Mitchell Cooper
All rights reserved. 

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met: 

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
* Neither the name of Juno-IRCd Development Group nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## setting up/installation

one thing I have tried to do is to make it as simple as possible to setup and
install, so there is no install script and there are no files that the IRCd
requires to be built before it is started. for this reason, there is an 'enable'
block in the configuration to enable certain features that were originally to
be enabled in installation; but as long as the etc directory is readable and
writable, you should be ready to enjoy juno, that is, of course, after you edit
etc/ircd.conf.example and read the comments. the configuration is setup very
simply. the first word of a line is the value you're setting, and everything
beyond it is the value you are setting it to (except for in oper, listen, etc.
blocks.) when you finish configuring, just run:

`./juno start` to start

`./juno rehash` to rehash

`./juno stop` to terminate

the juno script provides several other functions that are listed in `./juno help`.

## support

you can probably find me on:
[NoTrollPlzNet](https://notroll.net/) irc.notroll.net:6667

## requirements

you must have the following perl modules to run juno:

* IO::Select (core)
* IO::Socket::INET (core)
* Socket (core)
* POSIX (core)

all dependencies are core modules as of now.

## IPv6

to enable IPv6 listening, you must set the configuration option `enabled:ipv6` to
a true value. This requires the `IO::Socket::INET6` perl module. If
you wish to listen with SSL on IPv6, you must also have SSL enabled. 

## SSL

to enable SSL listening, you must must set the configuration option `enabled:ssl`
to a true value. This requires the `IO::Socket::SSL` perl module. If you wish to
listen with SSL on IPv6, you must also have IPv6 enabled.

## cloaking

cloaking requires use of the `Digest::SHA` module, which is a core perl module. It can be enabled by the `enabled:ssl` configuration option.

module API
-----------------------
juno's module API can be enabled by the `enabled:api` option in the configuration.
the module API requires a significant amount of memory to function, and it also
requires the `Class::Unload Perl` module to properly unload the modules. as of
juno-dev-1.0.4, juno modules are no longer included in juno's git, in promotion
of juno's new module manager. the module manager is an easy-to-use interface to
juno's module respository. it can be started with `./juno mod`. The core API
module provides the MODLOAD and MODUNLOAD commands, usable by users with the
`modules` oper flag.

## TODO

* CAP
* show modes alphabetical, capitals first.
* USERHOST command
* VERSION command
* WHO user
* make the modules be (un)loaded on rehash
* fix weird bug where it sometimes adds mode a to finished_string in mode handler even if it doesn't work

## API TODO

* Module: some way to force mode changes

## user commands

### PONG

The PONG command is the response to the PING command.

* Parameters: (none required)

### LUSERS*

LUSERS lists the number of local and global users.
It also displays the record of local and global user counts.

* Parameters: (none, currently)

### MOTD*
The MOTD command displays the message of the day.

* Parameters: (none, currently)

### NICK
Use the NICK command when you wish to change your nick.
It will reply with a numeric error or change your nick.

* Parameters: `new nickname`

### PING
The PING command is used by many clients to check for lag between the server and your client.
Traditionally, only parameter was a server name; however, the server will respond to anything.

* Parameters: `server`

### WHOIS*

A WHOIS query replies with several numerics with information on a user. 
The current WHOIS replies are as follows:

* Nick, username, visible host, and real name
* Channels the user is in
* Name of the server that the user is connecting to the network with
* Whether or not the user is using SSL
* If the user is away, the away reason
* Whether or not the user is an IRC operator
* Applied user modes
* Actual host of the user (IRC operators only unless cloaking is unset)
* Idle time

Parameters: `nickname` (currently)

### MODE

The MODE command is a multi-purpose command.
It is used for both channel and user modes.
The modes are listed in juno-ircd's documentation.
If the mode is valid and you have proper permissions to set it, there will be no reply other than the MODE response.
If there was indeed an error, a numeric will display it.
Some user modes such as Z (SSL) will be ignored entirely.

* Parameters: `target` `modes` [`parameter`,`parameter`,...]

### PRIVMSG
The PRIVMSG command is a multi-purpose command.
It sends a message to a channel or a user.

* Parameters: `target` `message`

### NOTICE

The NOTICE command is similar to the PRIVMSG command, but instead sends a NOTICE.
See PRIVMSG.

### AWAY

The AWAY command sets you as away with the provided reason.
The reason will be displayed in the WHOIS command.
In WHO, you will be marked away if you use this command.
If you are already away, AWAY is your way of returning.

* Parameters: `comment`

### OPER

The OPER command is used to grant IRC operator privileges to a user.
The response of this command is various numerics, depending on whether it succeeded or failed.
If successful, will reply with a numeric message displaying that you are now an IRC operator.
If failed, will reply with a numeric stating the error.

* Parameters: `name` `password`

### KILL

The KILL command is used to forcibly remove a user from the server.
You must have the kill oper flag to use the KILL command or an error numeric will be displayed.
If the nickname exists, there will be no reply. Otherwise, a numeric error will be displayed.

* Parameters: `nickname` `comment`

### JOIN

The JOIN command is used to join a channel.
The server will reply with a numeric if the requested channel is invalid.
If the channel is nonexistent, it will be created.
The second parameter is a list of channel keys.
It is an optional parameter but is required when the channel(s) have a key set.
The keys and channels must be in order.
For example, `JOIN #channel,#channel2,#channel3 key,,key2` says to join #channel with the 'key' key,
join #channel2 without a key, and join #channel3 with the 'key2' key.

* Parameters: `channel`\[,`channel`,...] [`key`,`key`,...]

### WHO*

A WHO query is used to list information that matches a specified mask.

* Parameters: `channel` (currently)

### NAMES

The NAMES command is used to view the users of a channel.
If the channel is invalid or nonexistent, no error will be displayed.
The NAMES command always responds with a numeric.
Some users will not be shown if they are invisible (+i) and the user requesting is not in the requested channel.

* Parameters: `channel`[,`channel`,...]

### QUIT

The QUIT command is used to disconnect a client from the network.
The server acknowledges this by sending an ERROR message to the client.
Parameters: `quit message`

### PART

The PART command is used to leave a channel.
The server will reply with a numeric error if the channel is invalid.
Parameters: `channel`[,`channel`,...] [`part message`]

### REHASH*

The REHASH command is used to rehash the server's configuration file.
Only IRC operators may use the REHASH command.
If you are not an IRC operator, a numeric error will be displayed.
Currently, nothing is replied if the rehash was successful.

* Parameters: (none)

### LOCOPS

The LOCOPS command is used to send a message to all IRC operators on the IRC server.
The message will be sent to all users on the common server with +S (server notices) enabled.
If unsuccessful, LOCOPS will return a numeric error.

* Parameters: `message`

### GLOBOPS*

The GLOBOPS command is used to send a message to all IRC operators on the network.
Because juno-ircd currently supports only 1 server, it simply an alias for LOCOPS at this time.

* Parameters: `message`

### TOPIC*

The TOPIC command is used to view or change a channel's topic.
Only channel operators may use the TOPIC command to change a channel topic if channel mode t is enabled.
All users may use the TOPIC command to view a channel's topic, assuming the channel is visible.
If unsuccessful, TOPIC will return a numeric error.
If you are viewing the topic of a channel, a numeric containing the topic, who it was set by, and when it was set will be displayed.

* Parameters: `channel` [`topic`]

### KICK

The KICK command is used to forcibly remove a user from a channel.
The requesting user must have channel operator status to use the KICK command.
If the user attempts to kick a user of higher status, a numeric error will be displayed.
A numeric error will also be displayed if the nick or channel is invalid.
If successful, nothing other than the KICK command will be replied.

* Parameters: `channel` `user` [`comment`]

### LIST

A LIST query is used to list or view the number of users and topic of one or more channels.
If no parameters are given, every channel is displayed unless they have modes enabled to keep them hidden.

* Parameters: [`channel`,`channel`,...]

### ISON

An ISON query is used to check if one or more users are on the network.
A numeric will be displayed containing those users' nicks.
If there are no users that match, there will be no error, but only an empty numeric.

* Parameters: `nickname` [`nickname` ...]

### CHGHOST

The CHGHOST command is used by IRC operators to change a user's visible host.
It requires the chghost oper flag; without it, a server notice error will be sent to the requesting user.
If the host is invalid or if the target nickname does not exist, the server will notice an error.
When successful, juno will send a numeric to the user whose cloak was changed.

* Parameters: `nickname` `new host`

## user modes

### i

The i user mode marks a user as invisible.
An invisible user is not displayed in many queries unless the requesting user is in a common channel with this user.

### o

The o user mode marks a user as an IRC operator.
This mode cannot be set; it is set upon successful use of the OPER command.
It can, however, be unset.

### x

The x user mode is used to enable or disable hostname cloaking.

### S

The S user mode enables server notices for IRC operators.
It may only be set my IRC operators.
It is set upon successful use of the OPER command if the oper block is configured to do so.

### Z

The Z user mode is used to represent an SSL connection.
It may not be set or unset by any user.

## channel modes

All channel modes require half-operator status if not greater.

### t

The t channel mode is used to restrict changing of the topic to users with halfop or greater status.

* Parameters: (none)

### q

The q channel mode is used to grant or remove a user's channel owner status.
Only channel owners may set this mode.

* Parameters: `nickname`

### a

The a channel mode is used to grant or remove a user's channel protected status.
Only channel owners and other protected users may set this mode.

* Parameters: `nickname`

### o

The o channel mode is used to grant or remove a user's channel operator status.
Only channel operators, protected users, and owners may set this mode.

* Parameters: `target`

### h

The h channel mode is used to grant or remove a user's channel half-operator status.
Only channel operators, protected users, and owners may set this mode.

* Parameters: `target`

### v

The v channel mode is used to grant or remove a user's channel voiced status.
Only channel half-operators, operators, protected users, and owners may set this mode.

* Parameters: `target`

### m

The m channel mode is used to restrict speaking to users with voiced status or greater.

* Parameters: (none)

### b

The b channel mode is used to ban a mask from a channel.
Users matching this mask may not join or speak in the channel.

* Parameters: `mask`

### Z

The Z channel mode is used exactly as the b channel mode.
It is the same as a channel ban except users may join the channel when the ban matches their mask.

* Parameters: `mask`

### I

The I channel mode is used exactly as the b channel mode.
If a user's mask matches, they my join a +i (invite only) channel.

* Parameters: `mask`

### e

The e channel mode is used exactly as the b channel mode.
If a user's mask matches, they completely override a channel ban (+b) or a channel mute (+Z).

* Parameters: `mask`

### i

The i channel mode prohibits users from joining the channel unless they were invited.
This mode may be overseen by an invite exception, channel mode I.

* Parameters: (none)

### z

The z channel mode allows operators to see what a user is saying if the user is incapable of NOTICEing or PRIVMSGing a channel.
If set, it appears to the user as if they were actually capable of messaging the channel, and no error is displayed.
This mode does not allow users to override channel mode n; users must be in the channel to be affected by this mode.
In actuality, only owners, protected users, and operators are capable of seeing these messages.

* Parameters: (none)

### l

The l channel mode prevents users from joining a channel if the limit is reached.
All users with half-operator status or above may set this mode.

* Parameters: `limit` (only when setting, not unsetting)

### A

The A channel mode allows a channel access list to be managed without IRC services.
The format is `mode`:`mask`.
Upon joining, any users matching the mask(s) will receive the status that applies to them.
For example, `+A q:*!*@*` grants owner status to all users.
A user who does not have the status being set will receive an error, and the mode query will be ignored.

* Parameters: `mode`:`mask`

### k

The k channel mode allows channel operators to restrict users to those who know the channel key.
The key must be supplied in both set and unset.
It may not contain commas.

* Parameters: `key`

## oper flags

In juno-ircd, oper flags are usually specific to each command. The following are available:

* kill
* rehash
* locops
* globops
* chghost
* modules (MODLOAD and MODUNLOAD) for module API

There are several more provided by different API modules.

\* unfinished  
\** this is just a joke; don't be alarmed
