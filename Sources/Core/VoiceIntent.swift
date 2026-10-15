//
//  VoiceIntent.swift
//  Il vocabolario degli intenti vocali.
//

import Foundation

enum VoiceIntent: Equatable {
    case play(TrackCommand)
    case pause
    case resume
    case next
    case previous
    case quit
    case none
}

enum TransportAction: String {
    case pause
    case resume
    case next
    case previous
}