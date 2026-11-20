import SwiftUI
import WidgetKit

@main
struct RotondaWidgets: WidgetBundle {
    var body: some Widget {
        ReviewWidget()
        ReadinessWidget()
        QuizWidget()
        WordWidget()
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// Shown until the app has written its first snapshot.
struct OpenAppPrompt: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "graduationcap.fill")
                .font(.title2)
                .foregroundStyle(Color.signBlue)
            Spacer(minLength: 0)
            Text("Open Rotonda to start")
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// A time today, or weekday and time for a later day.
func reviewTime(_ date: Date) -> Text {
    Text(date, format: Calendar.current.isDateInToday(date)
         ? .dateTime.hour().minute()
         : .dateTime.weekday(.abbreviated).hour().minute())
}

struct WidgetHeader: View {
    let title: LocalizedStringKey
    let icon: String
    var tint: Color = .signBlue

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .widgetAccentable()
    }
}

/// Last mock exams, newest on the right, each labelled with its error count.
struct ExamPips: View {
    let exams: [WidgetSnapshot.Exam]
    var height: CGFloat = 18
    var onTint = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(exams.reversed().enumerated()), id: \.offset) { _, exam in
                Text("\(exam.errors)")
                    .font(.system(size: height * 0.6, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                    .background(exam.passed ? Color.vero : Color.falso, in: Capsule())
                    .overlay { if onTint { Capsule().stroke(.white.opacity(0.6), lineWidth: 1) } }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Mock exams passed: \(exams.filter(\.passed).count)/\(exams.count)"))
    }
}

struct MasteryRing: View {
    let value: Double
    var lineWidth: CGFloat = 6
    var tint: Color = .signBlue
    var showsValue = true

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0.001, min(value, 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            if showsValue {
                Text(value.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .padding(lineWidth)
            }
        }
    }
}
