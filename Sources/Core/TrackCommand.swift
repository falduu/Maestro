//
//  TrackCommand.swift
//  Modello condiviso tra voce e musica.
//

import Foundation

enum MusicSearchScope: String {
    case allLibrary
    case favorites
}

struct TrackCommand: Equatable {
    let title: String
    let scope: MusicSearchScope
}