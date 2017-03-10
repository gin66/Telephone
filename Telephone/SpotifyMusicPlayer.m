//
//  SpotifyMusicPlayer.m
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2017 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

#import "SpotifyMusicPlayer.h"

#import "Spotify.h"

NS_ASSUME_NONNULL_BEGIN

@interface SpotifyMusicPlayer ()

@property(nonatomic, readonly) SpotifyApplication *application;
@property(nonatomic) BOOL didPause;

@end

NS_ASSUME_NONNULL_END

@implementation SpotifyMusicPlayer

- (instancetype)initWithApplication:(SpotifyApplication *)application {
    if ((self = [super init])) {
        _application = application;
    }
    return self;
}

#pragma mark - MusicPlayer

- (void)pause {
    if (!self.application.isRunning || self.application.playerState != SpotifyEPlSPlaying) {
        return;
    }
    [self.application pause];
    self.didPause = YES;
}

- (void)resume {
    if (!self.application.isRunning || !self.didPause) {
        return;
    }
    if (self.application.playerState == SpotifyEPlSPaused) {
        [self.application play];
    }
    self.didPause = NO;
}

@end
