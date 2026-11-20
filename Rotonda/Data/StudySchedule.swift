import Foundation

/// Automatic study explores unseen material before reviewing it at spaced intervals.
enum StudySchedule {
    static let intervals: [TimeInterval] = [10 * 60, 86_400, 3 * 86_400, 7 * 86_400, 16 * 86_400, 35 * 86_400, 90 * 86_400]

    /// A missing date means unseen. Future reviews never fill an automatic session.
    static func select<Item>(_ pool: [Item], count: Int, now: Date = .now,
                             dueDate: (Item) -> Date?) -> [Item] {
        guard count > 0 else { return [] }
        var fresh: [Item] = []
        var due: [(item: Item, date: Date, position: Int)] = []
        for (position, item) in pool.enumerated() {
            if let date = dueDate(item) {
                if date <= now { due.append((item, date, position)) }
            } else {
                fresh.append(item)
            }
        }
        due.sort { $0.date == $1.date ? $0.position < $1.position : $0.date < $1.date }
        return Array((fresh + due.map(\.item)).prefix(count))
    }

    /// Times longer than this mean the learner was interrupted, not unsure, so they are ignored.
    static let interruptedAfter: TimeInterval = 90

    /// A correct answer that took far longer than reading it was probably a guess or a doubt:
    /// it still counts as correct but does not lengthen the review interval. `characters` is
    /// how much text there was to read before answering.
    static func isHesitant(seconds: TimeInterval?, characters: Int) -> Bool {
        guard let seconds, seconds < interruptedAfter else { return false }
        return seconds > 8 + Double(characters) * 0.08
    }
}

struct QuestionStat: Hashable {
    var chapterID: Int
    var attempts = 0
    var correct = 0
    var wrong = 0
    /// Consecutive correct answers. A question leaves the mistakes list after two in a row.
    var streak = 0
    var lastCorrect = false
    var lastAt = Date.distantPast

    var isMistake: Bool { wrong > 0 && streak < 2 }
    /// Reconstructed from persisted results.
    var reviewDue: Date {
        let box = lastCorrect ? min(max(streak, 1), StudySchedule.intervals.count - 1) : 0
        return lastAt.addingTimeInterval(StudySchedule.intervals[box])
    }
}

/// Leitner repetition: success lengthens the interval; a lapse restarts at ten minutes.
struct CardState: Hashable {
    static let intervals = StudySchedule.intervals
    static let learnedBox = 2

    var box = 0
    var due = Date()
    var reps = 0
    var lapses = 0

    var isLearned: Bool { box >= Self.learnedBox }
    func isDue(at date: Date = .now) -> Bool { due <= date }
}
