//
//  RingtoneFactoryImpl.swift
//  Telephone
//
//  Copyright (c) 2008-2016 Alexey Kuznetsov
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

import UseCases

public class RingtoneFactoryImpl {
    public let soundConfigurationLoadinteractor: UserDefaultsRingtoneSoundConfigurationLoadInteractorInput
    public let soundFactory: SoundFactory
    public let timerFactory: TimerFactory

    public init(soundConfigurationLoadinteractor: UserDefaultsRingtoneSoundConfigurationLoadInteractorInput, soundFactory: SoundFactory, timerFactory: TimerFactory) {
        self.soundConfigurationLoadinteractor = soundConfigurationLoadinteractor
        self.soundFactory = soundFactory
        self.timerFactory = timerFactory
    }
}

extension RingtoneFactoryImpl: RingtoneFactory {
    public func createRingtoneWithTimeInterval(timeInterval: Double) throws -> Ringtone {
        return RepeatingSound(
            sound: try soundFactory.createSound(try soundConfigurationLoadinteractor.execute()),
            timeInterval: timeInterval,
            timerFactory: timerFactory
        )
    }
}
