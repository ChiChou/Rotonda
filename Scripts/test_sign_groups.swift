// Compile with Models.swift, SQLite.swift and ContentStore.swift; place patente.db beside the executable.
import Foundation

@main
struct SignGroupRegressionTests {
    @MainActor static func main() {
        let content = ContentStore.shared
        precondition(content.loadError == nil, content.loadError ?? "")
        let all = content.imageGroups(chapter: nil)
        precondition(!all.isEmpty)
        precondition(Set(all.map(\.image)).count == all.count, "Each image appears once")
        for group in all {
            let questions = content.questions(image: group.image, chapter: nil)
            precondition(questions.count == group.questionCount)
            precondition(Set(questions.map(\.id)).count == questions.count)
            let chapterQuestions = content.chapters.flatMap {
                content.questions(image: group.image, chapter: $0.id)
            }
            precondition(Set(chapterQuestions.map(\.id)) == Set(questions.map(\.id)),
                         "Global signs must retain questions from every chapter")
        }
        for chapter in content.chapters {
            let groups = content.imageGroups(chapter: chapter.id)
            precondition(groups.count == chapter.imageGroupCount)
            precondition(Set(groups.map(\.image)).count == groups.count)
            for group in groups {
                let questions = content.questions(image: group.image, chapter: chapter.id)
                precondition(questions.count == group.questionCount)
                precondition(questions.allSatisfy { $0.chapterID == chapter.id })
            }
        }
        let shared = content.questions(image: "38d290655bf8.jpeg", chapter: nil)
        precondition(Set(shared.map(\.chapterID)) == [5, 13], "Cross-chapter regression")
        print("PASS: \(all.count) unique pictures; complete question sets and chapter scopes.")
    }
}
