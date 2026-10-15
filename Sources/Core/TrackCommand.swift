//
//  TrackCommand.swift
//  Modello condiviso tra voce e musica.
//

import Foundation

enum MusicSearchScope: String, Codable {
    case allLibrary
    case favorites
    case playlist        // v0.3: «nella playlist X»
}

struct TrackCommand: Equatable, Codable {
    let title: String
    let scope: MusicSearchScope
    /// Nome playlist quando scope == .playlist
    var playlistName: String? = nil
}