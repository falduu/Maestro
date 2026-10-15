//
//  MusicManager.swift
//  MusicKit per la ricerca (libreria / preferiti / catalogo)
//  + MusicAppController per la riproduzione dentro Musica.app.
//
//  Efficienza: candidati leggeri (title/artist) per il matching,
//  cache TTL sui preferiti, best-match con early-exit.
//

import Foundation
import MusicKit
import Combine

@MainActor
final class MusicManager: ObservableObject {

    enum State: Equatable {
        case idle
        case searching
        case success(String)
        case failure(String)
    }

    /// Candidato leggero: il matching non dipende dai tipi MusicKit.
    struct TrackCandidate: Equatable {
        let title: String
        let artistName: String
    }

    @Published private(set) var authorizationStatus: MusicAuthorization.Status = .notDetermined
    @Published private(set) var state: State = .idle
    @Published private(set) var lastPlayedTitle: String?

    private let controller = MusicAppController()
    private var favoritesCache: (playlists: [Playlist], timestamp: Date)?

    private static let allowedCharacters = CharacterSet.alphanumerics.union(.whitespaces)

    // MARK: - Autorizzazione (una sola volta)

    func requestAuthorizationIfNeeded() async {
        guard authorizationStatus == .notDetermined else { return }
        let current = MusicAuthorization.currentStatus
        authorizationStatus = (current == .notDetermined)
            ? await MusicAuthorization.request()
            : current
    }

    // MARK: - Riproduzione

    func play(query rawQuery: String) async {
        await play(command: TrackCommand(title: rawQuery, scope: .allLibrary))
    }

    func play(command: TrackCommand) async {
        let query = command.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            state = .failure("Query vuota.")
            return
        }

        await requestAuthorizationIfNeeded()

        guard authorizationStatus == .authorized else {
            state = .failure("Autorizzazione Apple Music non concessa.")
            return
        }

        state = .searching

        var playlistName: String? = nil

        do {
            var candidates: [TrackCandidate] = []

            switch command.scope {
            case .allLibrary:
                candidates = try await searchLibrary(for: query)
                if candidates.isEmpty && AppConfig.allowCatalogFallback {
                    candidates = try await searchCatalog(for: query)
                }

            case .favorites:
                candidates = try await searchFavorites(for: query)
                playlistName = favoritePlaylistName
                if candidates.isEmpty && AppConfig.fallbackToLibraryIfFavoritesEmpty {
                    candidates = try await searchLibrary(for: query)
                }
            }

            let best = chooseBest(from: candidates, matching: query)

            // Un solo round-trip: MusicKit suggerisce il titolo preferito,
            // lo script AppleScript ha fallback interni fino alla query parziale.
            let result = await controller.play(
                query: query,
                preferredTitle: best?.title,
                inPlaylist: playlistName
            )

            switch result {
            case .played(let name):
                lastPlayedTitle = name
                state = .success(
                    command.scope == .favorites
                        ? "Dai preferiti: \(name)"
                        : "In riproduzione: \(name)"
                )
            case .notFound:
                state = .failure("Nessun brano in libreria per \"\(query)\".")
            case .playFailed(let name):
                state = .failure("Musica non ha avviato \"\(name)\": file mancante o brano non scaricato?")
            case .error(let message):
                state = .failure(message)
            }

        } catch {
            // MusicKit KO: proviamo comunque la ricerca diretta dentro Musica.app.
            let result = await controller.play(query: query, preferredTitle: nil, inPlaylist: playlistName)

            switch result {
            case .played(let name):
                lastPlayedTitle = name
                state = .success("In riproduzione: \(name)")
            case .notFound:
                state = .failure("Nessun brano in libreria per \"\(query)\".")
            case .playFailed(let name):
                state = .failure("Musica non ha avviato \"\(name)\".")
            case .error(let message):
                state = .failure(message)
            }
        }
    }

    // MARK: - Ricerca

    private func searchLibrary(for query: String) async throws -> [TrackCandidate] {
        let request = MusicLibrarySearchRequest(term: query, types: [Song.self])
        return try await request.response().songs.map {
            TrackCandidate(title: $0.title, artistName: $0.artistName)
        }
    }

    private func searchCatalog(for query: String) async throws -> [TrackCandidate] {
        let request = MusicCatalogSearchRequest(term: query, types: [Song.self])
        return try await request.response().songs.map {
            TrackCandidate(title: $0.title, artistName: $0.artistName)
        }
    }

    private func searchFavorites(for query: String) async throws -> [TrackCandidate] {
        let playlists = try await favoritePlaylists()
        guard !playlists.isEmpty else { return [] }

        let q = Self.normalized(query)
        var matches: [TrackCandidate] = []

        for playlist in playlists.prefix(5) {
            guard let tracks = try? await playlist.with(.tracks).tracks else { continue }

            matches.append(
                contentsOf: tracks
                    .filter {
                        Self.normalized($0.title).contains(q) ||
                        Self.normalized("\($0.title) \($0.artistName)").contains(q)
                    }
                    .map { TrackCandidate(title: $0.title, artistName: $0.artistName) }
            )
        }

        return matches
    }

    private var favoritePlaylistName: String? {
        favoritesCache?.playlists.first?.name
    }

    private func favoritePlaylists() async throws -> [Playlist] {
        if let cache = favoritesCache,
           Date().timeIntervalSince(cache.timestamp) < AppConfig.favoritesCacheTTL {
            return cache.playlists
        }

        var found: [Playlist] = []
        for keyword in AppConfig.favoritesPlaylistKeywords {
            let request = MusicLibrarySearchRequest(term: keyword, types: [Playlist.self])
            found.append(contentsOf: try await request.response().playlists)
        }

        let filtered = found.filter { playlist in
            let name = Self.normalized(playlist.name)
            return AppConfig.favoritesPlaylistKeywords.contains { name.contains(Self.normalized($0)) }
        }

        var seen = Set<String>()
        let unique = filtered.filter { seen.insert($0.id.rawValue).inserted }

        favoritesCache = (unique, Date())
        return unique
    }

    // MARK: - Best match con early-exit

    private func chooseBest(from candidates: [TrackCandidate], matching query: String) -> TrackCandidate? {
        guard let first = candidates.first else { return nil }
        let q = Self.normalized(query)

        for candidate in candidates where Self.normalized(candidate.title) == q {
            return candidate
        }

        var best = first
        var bestScore = score(of: first, against: q)

        for candidate in candidates.dropFirst() {
            let s = score(of: candidate, against: q)
            if s < bestScore {
                best = candidate
                bestScore = s
            }
            if bestScore == 1 { break }
        }
        return best
    }

    private func score(of candidate: TrackCandidate, against q: String) -> Int {
        let t = Self.normalized(candidate.title)
        if t == q { return 0 }
        if t.hasPrefix(q) { return 1 }
        if t.contains(q) { return 2 }
        return 100 + abs(t.count - q.count)
    }

    private static func normalized(_ text: String) -> String {
        let folded = text
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale.current)

        return folded
            .components(separatedBy: allowedCharacters.inverted)
            .joined(separator: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }

        // MARK: - Trasporto

    func transport(_ action: TransportAction) async {
        let result = await controller.transport(action)

        switch result {
        case .ok:
            switch action {
            case .pause: state = .success("In pausa.")
            case .resume: state = .success("Ripresa riproduzione.")
            case .next: state = .success("Brano successivo.")
            case .previous: state = .success("Brano precedente.")
            }
        case .error(let message):
            state = .failure(message)
        }
    }
}