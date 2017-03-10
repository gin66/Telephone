//
//  SimpleSystemAudioDevice.swift
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

public struct SimpleSystemAudioDevice: SystemAudioDevice {
    public let identifier: Int
    public let uniqueIdentifier: String
    public let name: String
    public let inputs: Int
    public let outputs: Int
    public let isBuiltIn: Bool
    public let isNil: Bool = false

    public init(identifier: Int, uniqueIdentifier: String, name: String, inputs: Int, outputs: Int, isBuiltIn: Bool) {
        self.identifier = identifier
        self.uniqueIdentifier = uniqueIdentifier
        self.name = name
        self.inputs = inputs
        self.outputs = outputs
        self.isBuiltIn = isBuiltIn
    }
}
