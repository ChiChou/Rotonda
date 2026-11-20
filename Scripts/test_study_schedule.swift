// Run: swiftc Rotonda/Data/StudySchedule.swift Scripts/test_study_schedule.swift -o /tmp/test-study-schedule && /tmp/test-study-schedule
import Foundation

@main
struct StudyScheduleTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let dates = [1: now.addingTimeInterval(-100), 3: now.addingTimeInterval(100),
                     4: now.addingTimeInterval(-200), 5: now]
        let selection = StudySchedule.select([1, 2, 3, 4, 5, 6], count: 5, now: now) { dates[$0] }
        precondition(selection == [2, 6, 4, 1, 5], "Discover unseen material before reviews, oldest due first")
        precondition(StudySchedule.select([1, 2, 3], count: 1, now: now) { dates[$0] } == [2],
                     "An overdue review must not displace new knowledge")
        precondition(StudySchedule.select([3], count: 10, now: now) { dates[$0] }.isEmpty,
                     "Recently learned material must not repeat just to fill a session")
        precondition(StudySchedule.select([1, 2], count: 0, now: now) { dates[$0] }.isEmpty)
        let tied = StudySchedule.select([7, 8], count: 2, now: now) { _ in now }
        precondition(tied == [7, 8], "Equal due dates retain source order")
        let tomorrow = now.addingTimeInterval(86_400)
        precondition(StudySchedule.select([3], count: 10, now: tomorrow) { dates[$0] } == [3],
                     "The same learned item becomes eligible once its interval expires")

        var question = QuestionStat(chapterID: 1, attempts: 1, wrong: 1, lastAt: now)
        precondition(question.reviewDue == now.addingTimeInterval(600), "Mistakes return after ten minutes")
        question.lastCorrect = true
        question.streak = 1
        precondition(question.reviewDue == now.addingTimeInterval(86_400), "First success returns after one day")
        question.streak = 2
        precondition(question.reviewDue == now.addingTimeInterval(3 * 86_400), "Success lengthens the interval")
        question.streak = 100
        precondition(question.reviewDue == now.addingTimeInterval(90 * 86_400), "The longest interval is bounded")
        question.lastCorrect = false
        question.streak = 0
        precondition(question.reviewDue == now.addingTimeInterval(600), "A lapse resets the interval")
        precondition(!StudySchedule.isHesitant(seconds: 5, characters: 100), "A quick answer is confident")
        precondition(StudySchedule.isHesitant(seconds: 30, characters: 100), "A slow answer counts as unsure")
        precondition(!StudySchedule.isHesitant(seconds: 15, characters: 200), "Longer statements allow more reading time")
        precondition(!StudySchedule.isHesitant(seconds: 600, characters: 100), "An interruption is not hesitation")
        precondition(!StudySchedule.isHesitant(seconds: nil, characters: 100), "Discarded timings are ignored")
        print("PASS: discovery priority, due ordering, no early repeats, interval expiry, question scheduling and hesitation.")
    }
}
