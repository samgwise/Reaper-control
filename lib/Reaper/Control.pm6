use v6.c;
unit module Reaper::Control:ver<0.0.1>;


=begin pod

=head1 NAME

Reaper::Control - An OSC controller interface for Reaper

=head1 SYNOPSIS

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
=head1 DESCRIPTION

Reaper::Control is an L<OSC controller interface|https://www.reaper.fm/sdk/osc/osc.php> for L<Reaper|https://www.reaper.fm>, a digital audio workstation.
Current features are limited and relate to play/stop and playback position but there is a lot more which can be added in the future.

=head1 AUTHOR

Sam Gillespie <samgwise@gmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2018 Sam Gillespie

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

our class Event {
    #= Base class for all reaper events.
    #= Otherwise a plain old empty class.
}

our role Event::PlayState is Event {
    #= A role defining the methods of Play and Stop Classes.
    #= Use this type if you need to accept either Play or Stop objects.

    method is-playing( --> Bool) { … };

    method is-stopped( --> Bool) { … };
}

our class Event::Play does Event::PlayState {
    #= The Play version of the PlayState role.
    #= This object is emitted when playback is started.

    method is-playing( --> Bool) {
        #= Returns True
        True
    };

    method is-stopped( --> Bool) {
        #= Returns False
        False
    };
}

our class Event::Stop does Event::PlayState {
    #= The Stop version of the PlayState role.
    #= This object is emitted when playback is stopped.

    method is-playing( --> Bool) {
        #= Returns False
        False
    };

    method is-stopped( --> Bool) {
        #= Returns True
        True
    };
}

our class Event::PlayTime is Event {
    #= This message bundles up elapsed seconds, elapsed samples and a string of the current beat position.
    has Numeric $.seconds;
    has Numeric $.samples;
    has Str $.beats;
}

#! A listener which wraps up the parsing logic to handle events from Reaper
our class Listener {
    #= This class bundles up a series of tapped supplies which define a listener workflow.
    #= To construct a new listener call the listener-udp method to initialise a UDP listener workflow.

    use Net::OSC::Bundle;

    has Supplier            $!bundles = Supplier.new;
    has Supplier            $!reaper  = Supplier.new;
    has IO::Socket::Async   $!listener;
    has Tap                 $!unbundler;
    has Tap                 $!message-mapper;

    #! Processed event stream
    method reaper-events( --> Supply) {
        $!reaper.Supply
    }

    #! Raw OSC bundle stream
    method reaper-raw( --> Supply) {
        $!bundles.Supply
    }

    #! Setup a pipeline decoding from a UDP socket
    method listen-udp(Str :$host, Int :$port) {
        $!listener.close if defined $!listener;
        $!listener .= bind-udp($host, $port);
        self.init-unbundle;
        self.init-message-mapper;

        self
    }

    #! Initialise an OSC bundler parser on the current pipeline
    method init-unbundle( --> Tap) {
        $!unbundler.close if defined $!unbundler;
        $!unbundler = $!listener.Supply(:bin).grep( *.elems > 0 ).tap: -> $buf {
            try {
                CATCH { warn "Error unpacking OSC bundle:\n{ .gist }" }
                $!bundles.emit: Net::OSC::Bundle.unpackage($buf)
            }
        }
    }

    #! Initialise an OSC Message mapper on the current pipline
    method init-message-mapper( --> Tap) {
        $!message-mapper.close if defined $!message-mapper;

        # Instantiate immutable objects
        my $play = Event::Play.new;
        my $stop = Event::Stop.new;

        $!message-mapper = $!bundles.Supply.tap: {
            my Bool $is-playing;
            my Numeric $seconds;
            my Numeric $samples;
            my Str      $beats;

            for .messages {
                when .path eq '/time' {
                    $seconds = .args.head
                }
                when .path eq '/samples' {
                    $samples = .args.head
                }
                when .path eq '/beat/str' {
                    $beats = .args.head
                }
                when .path eq '/play' {
                    $is-playing = (.args.head == 1) ?? True !! False
                }
                when .path eq '/stop' {
                    $is-playing = (.args.head == 0) ?? True !! False
                }
                when .path ~~ / '/str' $/ {
                    #ignore strings for now
                }
                default { warn "Unhandled message: { .gist }" }
            }

            $!reaper.emit: $is-playing ?? $play !! $stop if defined $is-playing;
            $!reaper.emit: Event::PlayTime.new(:$seconds :$samples :$beats) if $seconds and $samples and $beats;
        }
    }
}

#! Create a listener
our sub reaper-listener(Str :$host, Int :$port, Str :$protocol = 'UDP' --> Listener) is export {
    #= Create a Listener object which encapsulates message parsing and event parsing.
    #= The protocol argument currently only accepts UDP.
    #= Use the reaper-events method to obtain a Supply of events received, by the Listener, from Reaper.

    given $protocol {
        when 'UDP' {
            Listener.new.listen-udp(:$host, :$port)
        }
        default {
            die "Unhandled protocol: '$protocol'"
        }
    }
}
