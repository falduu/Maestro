//
//  TextNormalizer.swift
//  Normalizzazione condivisa (voce + ricerca musica): lowercase, no accenti,
//  no punteggiatura, correzioni fonetiche dall'IntentLexicon.
//

import Foundation

enum TextNormalizer {

    private static let allowed = CharacterSet.alphanumerics.union(.whitespaces)

    /// Stringa normalizzata (single space, senza punteggiatura/accenti).
    static func normalize(_ text: String) -> String {
        var working = text.lowercased()

        // Correzioni multi-token del lessico (es. «ma estro» → «maestro»).
        for (wrong, right) in IntentLexicon.phraseCorrections where wrong.contains(" ") {
            working = working.replacingOccurrences(of: " \(wrong) ", with: " \(right) ")
        }

        let folded = working.folding(
            options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive],
            locale: Locale(identifier: "it")
        )

        let tokens = folded
            .components(separatedBy: allowed.inverted)
            .joined(separator: " ")
            .split(separator: " ")
            .map(String.init)
            .compactMap { IntentLexicon.phoneticCorrections[$0] ?? $0 }

        return tokens.joined(separator: " ")
    }

    /// Token normalizzati pronti per il matching.
    static func tokenize(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map(String.init)
    }
}
