#!/usr/bin/perl
#
# Reports the system Now Playing session and forwards transport commands.
#
# macOS only answers MediaRemote clients it trusts, and /usr/bin/perl is one of
# them, so GlassWork runs this script as a child process. It needs nothing but
# what macOS ships: Perl, its Objective-C bridge and the MediaRemote framework.
#
# Output: one JSON object per line.
#   {"event":"state",...}    the session changed; nothing is printed otherwise
#   {"event":"artwork",...}  base64 image for the artworkID in the last state
#   {"event":"unavailable","reason":"..."} MediaRemote cannot be used; exits with 3
#
# Input: one command per line: play, pause, toggle, next, previous, seek <seconds>.
# End of input, which also happens when GlassWork quits or crashes, ends the script.

use strict;
use warnings;
use IO::Handle;
use IO::Select;
use JSON::PP;
use PerlObjCBridge;

my $framework = '/System/Library/PrivateFrameworks/MediaRemote.framework';
my $artwork_pixels = 360;
my $queue_length = 7;

# Quick at first so an opening panel fills in, then once a second: the framework
# keeps the response current by itself, so a pass only compares values in memory.
my $fast_ticks = 8;
my $fast_seconds = 0.25;
my $slow_seconds = 1;

my %command_codes = (play => 0, pause => 1, toggle => 2, next => 4, previous => 5, seek => 24);
my %capability_keys = (4 => 'canGoNext', 5 => 'canGoPrevious', 24 => 'canSeek');

my $json = JSON::PP->new->utf8->canonical;
STDOUT->autoflush(1);

# The bridge only forwards messages for classes declared as Perl packages. It
# also manages Objective-C memory itself: an autorelease pool made here aborts.
sub declare_classes {
    no strict 'refs';
    @{"$_\::ISA"} = ('PerlObjCBridge') for @_;
}

declare_classes(qw(
    NSBundle NSDictionary NSNumber NSObject NSString
    MRDestination MRNowPlayingController MRNowPlayingControllerConfiguration MRPlaybackQueueRequest
));

sub give_up {
    print $json->encode({event => 'unavailable', reason => $_[0]}), "\n";
    exit 3;
}

sub ns_string {
    return NSString->stringWithUTF8String_($_[0]);
}

sub present {
    my ($object) = @_;
    return ref($object) && $$object;
}

sub text {
    my ($object) = @_;
    return undef unless present($object);
    my $value = $object->UTF8String;
    return defined($value) && length($value) ? $value : undef;
}

sub number {
    my ($value) = @_;
    return defined($value) ? $value + 0 : undef;
}

sub connect_controller {
    my $bundle = NSBundle->bundleWithPath_(ns_string($framework));
    give_up('framework missing') unless present($bundle) && $bundle->load;
    my $request = MRPlaybackQueueRequest->defaultPlaybackQueueRequest;
    $request->setLength_($queue_length);
    $request->setArtworkWidth_($artwork_pixels);
    $request->setArtworkHeight_($artwork_pixels);
    $request->setIncludeLyrics_(1);
    my $configuration = MRNowPlayingControllerConfiguration->alloc->initWithDestination_(MRDestination->localDestination);
    $configuration->setPlaybackQueueRequest_($request);
    $configuration->setRequestPlaybackQueue_(1);
    $configuration->setRequestPlaybackState_(1);
    $configuration->setRequestSupportedCommands_(1);
    $configuration->setRequestClientProperties_(1);
    my $controller = MRNowPlayingController->alloc->initWithConfiguration_($configuration);
    $controller->beginLoadingUpdates;
    return $controller;
}

sub capabilities {
    my ($response) = @_;
    my %found = map { $_ => JSON::PP::false } values %capability_keys;
    my $commands = $response->supportedCommands;
    return %found unless present($commands);
    for my $index (0 .. $commands->count - 1) {
        my $info = $commands->objectAtIndex_($index);
        my $key = $capability_keys{$info->command} or next;
        $found{$key} = $info->isEnabled ? JSON::PP::true : JSON::PP::false;
    }
    return %found;
}

# Only some players send lyrics. A failure here must not lose the rest of the state.
sub lyrics_of {
    my ($item) = @_;
    return eval {
        my $message = $item->protobufWithEncoding_(0);
        present($message) && $message->hasLyrics ? text($message->lyrics->lyrics) : undef;
    };
}

sub track {
    my ($item) = @_;
    my $metadata = $item->metadata;
    return {
        title => text($metadata->title),
        artist => text($metadata->trackArtistName),
        album => text($metadata->albumName),
        duration => number($metadata->duration),
    };
}

sub read_state {
    my ($controller) = @_;
    my $response = $controller->response;
    return ({event => 'state', isActive => JSON::PP::false}, undef) unless present($response);

    my $client = $response->playerPath->client;
    my %state = (
        event => 'state',
        isActive => JSON::PP::true,
        isPlaying => $response->playbackState == 1 ? JSON::PP::true : JSON::PP::false,
        bundleID => present($client) ? text($client->bundleIdentifier) : undef,
        parentBundleID => present($client) ? text($client->parentApplicationBundleIdentifier) : undef,
        appName => present($client) ? text($client->displayName) : undef,
        capabilities($response),
    );

    my $queue = $response->playbackQueue;
    return (\%state, undef) unless present($queue) && $queue->contentItems->count > 0;

    my $items = $queue->contentItems;
    my $current = $items->objectAtIndex_(0);
    my $metadata = $current->metadata;
    %state = (%state, %{track($current)});
    $state{elapsed} = number($metadata->elapsedTime);
    $state{elapsedAt} = number($metadata->elapsedTimeTimestamp);
    $state{artworkID} = text($metadata->artworkIdentifier);
    $state{lyrics} = lyrics_of($current);
    $state{queue} = [map { track($items->objectAtIndex_($_)) } 1 .. $items->count - 1];

    my $artwork = $current->artwork;
    return (\%state, present($artwork) ? $artwork->imageData : undef);
}

sub perform {
    my ($controller, $line) = @_;
    my ($name, $argument) = split ' ', $line;
    return unless defined $name && exists $command_codes{$name};
    my $options;
    if ($name eq 'seek') {
        return unless defined $argument && $argument =~ /^\d+(\.\d+)?$/;
        $options = NSDictionary->dictionaryWithObject_forKey_(
            NSNumber->numberWithDouble_($argument),
            ns_string('kMRMediaRemoteOptionPlaybackPosition')
        );
    }
    $controller->sendCommand_options_completion_($command_codes{$name}, $options, undef);
}

my $controller = eval { connect_controller() };
give_up("$@") unless $controller;

my $input = IO::Select->new(\*STDIN);
my $buffer = '';
my $last_state = '';
my $last_artwork = '';
my $ticks = 0;

while (1) {
    if ($input->can_read($ticks < $fast_ticks ? $fast_seconds : $slow_seconds)) {
        my $count = sysread(STDIN, $buffer, 4096, length $buffer);
        last unless $count;
        while ($buffer =~ s/^(.*)\n//) {
            my $line = $1;
            eval { perform($controller, $line) };
            # The player answers within moments, and the button should show it.
            $ticks = $fast_ticks - 4;
        }
    }
    $ticks++;

    my ($state, $image) = eval { read_state($controller) };
    next unless $state;
    # The framework needs a moment to load, so an early empty answer means nothing yet.
    next if $ticks < $fast_ticks && !$state->{isActive};

    my $encoded = $json->encode($state);
    if ($encoded ne $last_state) {
        $last_state = $encoded;
        print $encoded, "\n";
    }
    my $id = $state->{artworkID};
    if (present($image) && defined $id && $id ne $last_artwork) {
        $last_artwork = $id;
        print $json->encode({event => 'artwork', id => $id, data => $image->base64EncodedStringWithOptions_(0)->UTF8String}), "\n";
    }
}

$controller->endLoadingUpdates;
exit 0;
