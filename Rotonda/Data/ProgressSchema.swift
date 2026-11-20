import Foundation
import SwiftData

/// The learner's progress as SwiftData models. Each release that changes these models adds a
/// new `VersionedSchema` and a stage to `ProgressMigrationPlan`, so existing progress carries
/// over on update. Content (questions, words, facts) lives in the bundled read-only database.
nonisolated enum ProgressSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [StoredQuestionStat.self, StoredCard.self, StoredExam.self, StoredExamAnswer.self, StoredBookmark.self,
         StoredSavedWord.self, StoredReadingPosition.self, StoredGloss.self, StoredActivity.self]
    }

    /// Answers so far to one statement.
    @Model final class StoredQuestionStat {
        @Attribute(.unique) var questionID: Int
        var chapterID: Int
        var attempts: Int
        var correct: Int
        var wrong: Int
        var streak: Int
        var lastCorrect: Bool
        var lastAt: Date

        init(questionID: Int, chapterID: Int, attempts: Int = 0, correct: Int = 0, wrong: Int = 0,
             streak: Int = 0, lastCorrect: Bool = false, lastAt: Date = .now) {
            self.questionID = questionID
            self.chapterID = chapterID
            self.attempts = attempts
            self.correct = correct
            self.wrong = wrong
            self.streak = streak
            self.lastCorrect = lastCorrect
            self.lastAt = lastAt
        }
    }

    /// A word or fact memory card in spaced repetition.
    @Model final class StoredCard {
        @Attribute(.unique) var cardID: String
        var box: Int
        var due: Date
        var reps: Int
        var lapses: Int
        var lastAt: Date

        init(cardID: String, box: Int, due: Date, reps: Int, lapses: Int, lastAt: Date = .now) {
            self.cardID = cardID
            self.box = box
            self.due = due
            self.reps = reps
            self.lapses = lapses
            self.lastAt = lastAt
        }
    }

    /// A finished mock exam.
    @Model final class StoredExam {
        @Attribute(.unique) var examID: Int
        var at: Date
        var correct: Int
        var errors: Int
        var duration: Int
        @Relationship(deleteRule: .cascade, inverse: \StoredExamAnswer.exam)
        var answers: [StoredExamAnswer] = []

        init(examID: Int, at: Date, correct: Int, errors: Int, duration: Int) {
            self.examID = examID
            self.at = at
            self.correct = correct
            self.errors = errors
            self.duration = duration
        }
    }

    /// One statement of a mock exam, in exam order; an unanswered one has no answer.
    @Model final class StoredExamAnswer {
        var position: Int
        var questionID: Int
        var answer: Bool?
        var exam: StoredExam?

        init(position: Int, questionID: Int, answer: Bool?) {
            self.position = position
            self.questionID = questionID
            self.answer = answer
        }
    }

    @Model final class StoredBookmark {
        @Attribute(.unique) var questionID: Int
        var at: Date

        init(questionID: Int, at: Date = .now) {
            self.questionID = questionID
            self.at = at
        }
    }

    @Model final class StoredSavedWord {
        @Attribute(.unique) var wordID: Int
        var at: Date

        init(wordID: Int, at: Date = .now) {
            self.wordID = wordID
            self.at = at
        }
    }

    /// Where reading stopped in a chapter or list.
    @Model final class StoredReadingPosition {
        @Attribute(.unique) var key: String
        var position: Int
        var at: Date

        init(key: String, position: Int, at: Date = .now) {
            self.key = key
            self.position = position
            self.at = at
        }
    }

    /// A word meaning translated on device, by word and language ("12|zh-Hans").
    @Model final class StoredGloss {
        @Attribute(.unique) var key: String
        var text: String

        init(key: String, text: String) {
            self.key = key
            self.text = text
        }
    }

    /// Every answer given, for streaks and the week's activity.
    @Model final class StoredActivity {
        #Index<StoredActivity>([\.at])
        var kind: String
        var item: String
        var correct: Bool
        var at: Date

        init(kind: String, item: String, correct: Bool, at: Date = .now) {
            self.kind = kind
            self.item = item
            self.correct = correct
            self.at = at
        }
    }
}

/// Version 2: each mock exam remembers the licence it was taken for. Exams from version 1
/// were all A/B. The other models are unchanged.
nonisolated enum ProgressSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [ProgressSchemaV1.StoredQuestionStat.self, ProgressSchemaV1.StoredCard.self, StoredExam.self, StoredExamAnswer.self,
         ProgressSchemaV1.StoredBookmark.self, ProgressSchemaV1.StoredSavedWord.self, ProgressSchemaV1.StoredReadingPosition.self,
         ProgressSchemaV1.StoredGloss.self, ProgressSchemaV1.StoredActivity.self]
    }

    @Model final class StoredExam {
        @Attribute(.unique) var examID: Int
        var at: Date
        var correct: Int
        var errors: Int
        var duration: Int
        var licence: String = "ab"
        @Relationship(deleteRule: .cascade, inverse: \StoredExamAnswer.exam)
        var answers: [StoredExamAnswer] = []

        init(examID: Int, at: Date, correct: Int, errors: Int, duration: Int, licence: String) {
            self.examID = examID
            self.at = at
            self.correct = correct
            self.errors = errors
            self.duration = duration
            self.licence = licence
        }
    }

    @Model final class StoredExamAnswer {
        var position: Int
        var questionID: Int
        var answer: Bool?
        var exam: StoredExam?

        init(position: Int, questionID: Int, answer: Bool?) {
            self.position = position
            self.questionID = questionID
            self.answer = answer
        }
    }
}

typealias StoredQuestionStat = ProgressSchemaV1.StoredQuestionStat
typealias StoredCard = ProgressSchemaV1.StoredCard
typealias StoredExam = ProgressSchemaV2.StoredExam
typealias StoredExamAnswer = ProgressSchemaV2.StoredExamAnswer
typealias StoredBookmark = ProgressSchemaV1.StoredBookmark
typealias StoredSavedWord = ProgressSchemaV1.StoredSavedWord
typealias StoredReadingPosition = ProgressSchemaV1.StoredReadingPosition
typealias StoredGloss = ProgressSchemaV1.StoredGloss
typealias StoredActivity = ProgressSchemaV1.StoredActivity

/// Add each new schema version here, with a lightweight or custom stage from the one before.
nonisolated enum ProgressMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ProgressSchemaV1.self, ProgressSchemaV2.self] }
    static var stages: [MigrationStage] { [.lightweight(fromVersion: ProgressSchemaV1.self, toVersion: ProgressSchemaV2.self)] }
}
