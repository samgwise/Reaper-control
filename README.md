[![Build Status](https://travis-ci.org/samgwise/Reaper-control.svg?branch=master)](https://travis-ci.org/samgwise/Reaper-control)

NAME
====

Reaper::Control - An OSC controller interface for Reaper

SYNOPSIS
========

    use Reaper::Control;

    # Start listening for UDP messages from sent from Reaper.
    my $listener = reaper-listener(:host<127.0.0.1>, :port(9000));

    # Respond to events from Reaper:
    react whenever $listener.reaper-events {
      when Reaper::Control::Event::Play {
          put 'Playing'
      }
      when Reaper::Control::Event::Stop {
          put 'stopped'
      }
      when Reaper::Control::Event::PlayTime {
          put "seconds: { .seconds }\nsamples: { .samples }\nbeats: { .beats }"
      }
    }

DESCRIPTION
===========

Reaper::Control is an [OSC controller interface](https://www.reaper.fm/sdk/osc/osc.php) for [Reaper](https://www.reaper.fm), a digital audio workstation. Current features are limited and relate to play/stop and playback position but there is a lot more which can be added in the future.

AUTHOR
======

Sam Gillespie <samgwise@gmail.com>

COPYRIGHT AND LICENSE
=====================

Copyright 2018 Sam Gillespie

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

### sub reaper-listener

```
sub reaper-listener(
    Str :$host, 
    Int :$port, 
    Str :$protocol = "UDP"
) returns Reaper::Control::Listener
```

Create a Listener object which encapsulates message parsing and event parsing. The protocol argument currently only accepts UDP. Use the reaper-events method to obtain a Supply of events received, by the Listener, from Reaper.
