import Foundation

/// How far the learner's vocabulary reaches into the exam. Every question is linked to its key
/// words, so a word is worth the questions it helps read, and the next words to learn are the
/// ones that bring the most questions closest to fully readable.
@MainActor
enum WordReach {
    struct Summary {
        /// Share of all key-word uses in the question bank that are learned words.
        var wordShare: Double
        /// Questions whose key words are all learned.
        var readable: Int
        var total: Int
    }

    /// Key words of every question in the current licence, loaded once per licence.
    private static var cache: (licence: Licence, words: [Int: [Int]])?

    private static var questionWords: [Int: [Int]] {
        let licence = ContentStore.shared.licence
        if let cache, cache.licence == licence { return cache.words }
        var map: [Int: [Int]] = [:]
        for (question, word) in ContentStore.shared.questionWordPairs() { map[question, default: []].append(word) }
        cache = (licence, map)
        return map
    }

    private static func isKnown(_ word: Int) -> Bool {
        ProgressStore.shared.cards["w:\(word)"]?.isLearned == true
    }

    static func summary() -> Summary {
        var uses = 0, known = 0, readable = 0
        for words in questionWords.values {
            let count = words.count { isKnown($0) }
            uses += words.count
            known += count
            if count == words.count { readable += 1 }
        }
        return Summary(wordShare: uses == 0 ? 0 : Double(known) / Double(uses),
                       readable: readable, total: questionWords.count)
    }

    /// Unlearned words, most useful first. A question with fewer unknown words left gives
    /// each of them more weight, so finishing nearly readable questions comes first.
    static func nextWordIDs(limit: Int? = nil) -> [Int] {
        var score: [Int: Double] = [:]
        for words in questionWords.values {
            let unknown = words.filter { !isKnown($0) }
            guard !unknown.isEmpty else { continue }
            let weight = 1 / Double(unknown.count * unknown.count)
            for word in unknown { score[word, default: 0] += weight }
        }
        let ranked = score.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
        return limit.map { Array(ranked.prefix($0)) } ?? ranked
    }

    /// Questions that become fully readable once `words` are learned too.
    static func questionsOpened(by words: [Int]) -> Int {
        let adding = Set(words)
        return questionWords.values.count { words in
            let unknown = words.filter { !isKnown($0) }
            return !unknown.isEmpty && unknown.allSatisfy(adding.contains)
        }
    }

    /// Unlearned words in questions answered wrong, the most frequent first.
    static func mistakeWordIDs(limit: Int? = nil) -> [Int] {
        var count: [Int: Int] = [:]
        for question in ProgressStore.shared.mistakeIDs {
            for word in questionWords[question] ?? [] where !isKnown(word) { count[word, default: 0] += 1 }
        }
        let ranked = count.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
        return limit.map { Array(ranked.prefix($0)) } ?? ranked
    }
}
