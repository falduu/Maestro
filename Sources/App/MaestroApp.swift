//
//  MaestroApp.swift
//  Entry point menu bar + router degli intenti vocali.
//

import SwiftUI
import AppKit

@main
struct MaestroApp: App {

    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.speech)
                .environmentObject(coordinator.music)
        } label: {
            MenuBarLabel()
                .environmentObject(coordinator.speech)
                .onAppear { coordinator.startIfNeeded() }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppCoordinator: ObservableObject {

    let speech: SpeechManager
    let music: MusicManager

    @Published private(set) var hasStarted = false

    init() {
        let speech = SpeechManager()
        let music = MusicManager()
        self.speech = speech
        self.music = music

        speech.onIntent = { [weak self] intent in
            Task { @MainActor in
                await self?.route(intent)
            }
        }
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true

        Task {
            await music.requestAuthorizationIfNeeded()
            await speech.requestPermissionsAndStart()
        }
    }

    // MARK: - Router intenti

    private func route(_ intent: VoiceIntent) async {
        switch intent {
        case .play(let command):
            await music.play(command: command)
        case .pause:
            await music.transport(.pause)
        case .resume:
            await music.resumeOrReplay(lastCommand: speech.lastPlayCommand)
        case .next:
            await music.transport(.next)
        case .previous:
            await music.transport(.previous)
        case .quit:
            NSApplication.shared.terminate(nil)
        case .none:
            break
        }
    }
}