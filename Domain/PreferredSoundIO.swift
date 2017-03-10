//
//  PreferredSoundIO.swift
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

public struct PreferredSoundIO {
    fileprivate let soundIO: SoundIO

    public init(devices: [SystemAudioDevice]) {
        soundIO = FallingBackSoundIO(
            origin: SimpleSoundIO(soundIO: FirstBuiltInSystemSoundIO(devices: devices)),
            fallback: SimpleSoundIO(soundIO: FirstSystemSoundIO(devices: devices))
        )
    }
}

extension PreferredSoundIO: SoundIO {
    public var input: SystemAudioDevice {
        return soundIO.input
    }

    public var output: SystemAudioDevice {
        return soundIO.output
    }

    public var ringtoneOutput: SystemAudioDevice {
        return soundIO.ringtoneOutput
    }
}
