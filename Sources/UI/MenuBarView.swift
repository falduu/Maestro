//
//  MenuBarView.swift
//  Pannello di controllo (si apre cliccando l'icona).
//

import SwiftUI
import AppKit

struct MenuBarView: View {

    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var speech: SpeechManager
    @EnvironmentObject var music: MusicManager

    @State private var testTitle = "Imagine"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            permissionsSection
            Divider()
            speechSection
            musicSection
            Divider()
            testSection
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 430)
        .onAppear { coordinator.startIfNeeded() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text(AppConfig.appName).font(.headline)
                Text(speech.isListening ? "In ascolto" : "Non in ascolto")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: toggleListening) {
                Image(systemName: speech.isListening ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .help(speech.isListening ? "Ferma l'ascolto" : "Avvia l'ascolto")
        }
    }

    private func toggleListening() {
        if speech.isListening {
            speech.stopListening()
        } else {
            Task { await speech.requestPermissionsAndStart() }
        }
    }

    // MARK: - Permessi

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permessi").font(.subheadline.bold())

            HStack {
                statusDot(speech.permissionState == .granted)
                Text("Microfono + Voce")
                Spacer()
                if speech.permissionState == .denied {
                    Button("Microfono") { openPrivacy("Microphone") }.controlSize(.small)
                    Button("Voce") { openPrivacy("SpeechRecognition") }.controlSize(.small)
                }
            }

            HStack {
                statusDot(music.authorizationStatus == .authorized)
                Text("Apple Music")
                Spacer()
                musicPermissionButton
            }

            if let errorMessage = speech.errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var musicPermissionButton: some View {
        switch music.authorizationStatus {
        case .authorized:
            EmptyView()
        case .notDetermined:
            Button("Richiedi") { Task { await music.requestAuthorizationIfNeeded() } }
                .controlSize(.small)
        case .denied:
            Button("Apri Impostazioni") { openPrivacy("MediaLibrary") }.controlSize(.small)
        case .restricted:
            Text("Limitato").font(.caption).foregroundStyle(.orange)
        @unknown default:
            EmptyView()
        }
    }

    // MARK: - Stato voce

    private var speechSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Voce").font(.subheadline.bold())
            Text("Stato: \(speech.statusText)").font(.caption)
                if !speech.parseDebug.isEmpty {
                Text("Debug: \(speech.parseDebug)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if !speech.lastTranscript.isEmpty {
                Text("Trascrizione: \(speech.lastTranscript)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let command = speech.lastCommand {
                Text("Comando: \(command)").font(.caption).foregroundStyle(.green)
            }
        }
    }

    // MARK: - Stato musica

    private var musicSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Musica").font(.subheadline.bold())

            switch music.state {
            case .idle:
                Text("In attesa").font(.caption).foregroundStyle(.secondary)
            case .searching:
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Ricerca...").font(.caption)
                }
            case .success(let message):
                Text(message).font(.caption).foregroundStyle(.green)
            case .failure(let message):
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Test

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Test rapido").font(.subheadline.bold())
            TextField("Titolo brano", text: $testTitle).textFieldStyle(.roundedBorder)
            Button("Cerca e riproduci") { Task { await music.play(query: testTitle) } }
                .controlSize(.small)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Esci") { NSApplication.shared.terminate(nil) }.controlSize(.small)
            Spacer()
            Text("Wake word: \(AppConfig.wakeWord)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helper

    private func statusDot(_ ok: Bool) -> some View {
        Circle()
            .fill(ok ? Color.green : Color.orange)
            .frame(width: 9, height: 9)
    }

    private func openPrivacy(_ anchor: String) {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_\(anchor)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}