//
//  MenuBarLabel.swift
//  Icona minimalista nella menu bar.
//

import SwiftUI

struct MenuBarLabel: View {

    @EnvironmentObject var speech: SpeechManager

    var body: some View {
        Image(systemName: speech.isListening ? "waveform" : "music.note")
    }
}