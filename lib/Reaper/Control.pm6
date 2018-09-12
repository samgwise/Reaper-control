use v6.c;
unit module Reaper::Control:ver<0.0.1>;


=begin pod

=head1 NAME

Reaper::Control - An OSC controller interface for Reaper

=head1 SYNOPSIS

  use Reaper::Control;

=head1 DESCRIPTION

Reaper::Control is an OSC controller interface for Reaper, a digital audio workstation.
Current features are limmited and realte to play/stop and playback postion but there is a lot more which can be added in the future.

=head1 AUTHOR

Sam Gillespie <samgwise@gmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2018 Sam Gillespie

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

our class Event { }

our class Event::PlayState is Event {
    method is-playing( --> Bool) { … };

    method is-stopped( --> Bool) { … };
}

our class Event::Play is Event::PlayState {
    method is-playing( --> Bool) { True };

    method is-stopped( --> Bool) { False };
}

our class Event::Stop is Event::PlayState {
    method is-playing( --> Bool) { False };

    method is-stopped( --> Bool) { True };
}

our class Event::PlayTime is Event {
    has Numeric $.seconds;
    has Numeric $.samples;
    has Str $.beats;
}

#! A listener which wraps up the parsing logic to handle events from Reaper
our class Listener {
    has Supplier            $!bundles = Supplier.new;
    has Supplier            $!reaper = Supplier.new;
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

    #! initialise an OSC bundler parser on the current pipeline
    method init-unbundle( --> Tap) {
        $!unbundler.close if defined $!unbundler;
        $!unbundler = $!listener.Supply(:bin).grep( *.elems > 0 ).tap: -> $buf {
            try {
                CATCH { warn "Error unpacking OSC bundle:\n{ .gist }" }
                $!bundles.emit: Net::OSC::Bundle.unpackage($buf)
            }
        }
    }

    #! initialise an OSC Message mapper on the current pipline
    method init-message-mapper( --> Tap) {
        $!message-mapper.close if defined $!message-mapper;

        # Instatiate imutable objects
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
    given $protocol {
        when 'UDP' {
            Listener.new.listen-udp(:$host, :$port)
        }
        default {
            die "Unhandled protocol: '$protocol'"
        }
    }
}
