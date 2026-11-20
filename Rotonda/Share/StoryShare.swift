import SwiftUI
import UIKit

// MARK: - What a story shows

/// A moment worth showing off, drawn as a 9:16 story-format picture to share anywhere.
enum StoryMoment: Hashable, Identifiable {
    /// Overall progress: share of the bank mastered, streak, words learned, mock exams passed.
    case progress(mastery: Double, streak: Int, words: Int, examsPassed: Int)
    /// A passed mock exam.
    case examPassed(errors: Int, seconds: Int)
    /// The study streak, with the last seven days, oldest first.
    case streak(days: Int, week: [StoryDay])
    /// The last seven days' answers, oldest first.
    case week(answers: Int, accuracy: Double?, streak: Int, week: [StoryDay])

    var id: Self { self }

    /// The picture's name in the style picker.
    var styleName: Text {
        switch self {
        case .progress: Text("Progress")
        case .examPassed: Text("Mock exam")
        case .streak: Text("Streak")
        case .week: Text("This week")
        }
    }

    @MainActor static func currentProgress(_ progress: ProgressStore) -> StoryMoment {
        .progress(mastery: progress.bankMastery, streak: progress.streakDays(),
                  words: progress.learnedCount(prefix: "w:"), examsPassed: progress.exams.filter(\.passed).count)
    }

    /// The pictures to pick from on This week: the streak, the week's answers and overall progress.
    @MainActor static func weekChoices(_ progress: ProgressStore) -> [StoryMoment] {
        let days = progress.activity.suffix(7).map { StoryDay(day: $0.day, answers: $0.questions + $0.cards) }
        let questions = progress.activity.reduce(0) { $0 + $1.questions }
        let correct = progress.activity.reduce(0) { $0 + $1.correctQuestions }
        let streak = progress.streakDays()
        return [.streak(days: streak, week: days),
                .week(answers: days.reduce(0) { $0 + $1.answers },
                      accuracy: questions == 0 ? nil : Double(correct) / Double(questions), streak: streak, week: days),
                currentProgress(progress)]
    }
}

/// A story picture's colors. Every theme is dark enough for white text.
enum StoryTheme: String, CaseIterable, Identifiable {
    case blue, green, sunset, violet, night

    var id: Self { self }

    var name: Text {
        switch self {
        case .blue: Text("Blue")
        case .green: Text("Green")
        case .sunset: Text("Sunset")
        case .violet: Text("Violet")
        case .night: Text("Night")
        }
    }

    /// The background, from top leading to bottom trailing.
    var gradient: [Color] {
        switch self {
        case .blue: [0x075DA8, 0x0B67C9, 0x3E55AE].map(Self.color)
        case .green: [0x0A5C43, 0x11795A, 0x1F8F6E].map(Self.color)
        case .sunset: [0xD9480F, 0xC92A54, 0x9C2C8C].map(Self.color)
        case .violet: [0x4C2BA8, 0x6741D9, 0x8E3AB0].map(Self.color)
        case .night: [0x1A1E36, 0x11142A, 0x07080F].map(Self.color)
        }
    }

    /// Ink on white marks, such as the streak's check marks.
    var ink: Color { gradient[1] }

    /// The streak flame, warm against every background.
    var flame: Color { Self.color(self == .sunset ? 0xFFE066 : 0xFFB13D) }

    private static func color(_ hex: UInt32) -> Color { Color(light: hex, dark: hex) }
}

/// One day in a story picture.
struct StoryDay: Hashable {
    let day: Date
    let answers: Int
}

// MARK: - The picture

/// Laid out at 360 × 640 points and rendered at 3× for a 1080 × 1920 story-format picture. Fixed sizes keep
/// the picture the same whatever the reader's text size.
struct StoryCard: View {
    let moment: StoryMoment
    var theme: StoryTheme = .blue
    static let size = CGSize(width: 360, height: 640)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text("Studying for my Italian driving licence")
                .font(.system(size: 15, weight: .semibold)).opacity(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)
            content
            Spacer(minLength: 0)
            brand
        }
        .padding(.horizontal, 30)
        .padding(.top, 64)
        .padding(.bottom, 72)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(colors: theme.gradient,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // A large, faint roundabout as a backdrop.
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 420, weight: .bold))
                    .foregroundStyle(.white.opacity(0.07))
                    .offset(x: 150, y: 200)
            }
        }
        .clipped()
        .foregroundStyle(.white)
        .environment(\.colorScheme, .light)
    }

    /// Just the app's mark and name, small: no links or calls to action in a personal story.
    private var brand: some View {
        HStack(spacing: 6) {
            Image("BrandMark").resizable().frame(width: 24, height: 24).clipShape(Circle()).frame(width: 22, height: 22)
            Text(verbatim: AppBrand.name).font(.system(size: 13, weight: .bold, design: .rounded))
        }
        .opacity(0.9)
    }

    @ViewBuilder private var content: some View {
        switch moment {
        case .progress(let mastery, let streak, let words, let examsPassed):
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(mastery, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 104, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text("of the theory questions mastered")
                        .font(.system(size: 20, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                bar(mastery)
                HStack(alignment: .top, spacing: 12) {
                    figure(streak, Text("day streak"))
                    figure(words, Text("words learned"))
                    figure(examsPassed, Text("mock exams passed"))
                }
            }
        case .streak(let days, let week):
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(theme.flame)
                VStack(alignment: .leading, spacing: 4) {
                    Text(days, format: .number)
                        .font(.system(size: 120, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text("day streak")
                        .font(.system(size: 26, weight: .bold))
                }
                HStack(spacing: 0) {
                    ForEach(week, id: \.day) { day in
                        VStack(spacing: 8) {
                            Circle()
                                .fill(day.answers > 0 ? Color.white : Color.white.opacity(0.22))
                                .overlay {
                                    if day.answers > 0 {
                                        Image(systemName: "checkmark").font(.system(size: 15, weight: .heavy))
                                            .foregroundStyle(theme.ink)
                                    }
                                }
                                .frame(width: 34, height: 34)
                            Text(day.day, format: .dateTime.weekday(.narrow))
                                .font(.system(size: 13, weight: .semibold)).opacity(0.85)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        case .week(let answers, let accuracy, let streak, let week):
            VStack(alignment: .leading, spacing: 22) {
                Text("This week").font(.system(size: 20, weight: .bold)).opacity(0.9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(answers, format: .number)
                        .font(.system(size: 92, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text("answers").font(.system(size: 20, weight: .bold))
                }
                weekBars(week).frame(height: 120)
                HStack(alignment: .top, spacing: 12) {
                    figure(streak, Text("day streak"))
                    if let accuracy {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(accuracy, format: .percent.precision(.fractionLength(0)))
                                .font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit()
                            Text("correct").font(.system(size: 12, weight: .semibold)).opacity(0.85)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    figure(week.filter { $0.answers > 0 }.count, Text("days studied"))
                }
            }
        case .examPassed(let errors, let seconds):
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 76))
                    .foregroundStyle(.white, Color(light: 0x1B8A4B, dark: 0x1B8A4B))
                Text("Mock exam passed")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 12) {
                    figure(errors, Text("errors out of \(ContentStore.shared.examRules.questionCount)"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Duration.seconds(seconds), format: .time(pattern: .minuteSecond))
                            .font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit()
                        Text("minutes taken").font(.system(size: 12, weight: .semibold)).opacity(0.85)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// A bar per day, scaled to the busiest one.
    private func weekBars(_ week: [StoryDay]) -> some View {
        let top = max(week.map(\.answers).max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(week, id: \.day) { day in
                VStack(spacing: 6) {
                    GeometryReader { geometry in
                        VStack {
                            Spacer(minLength: 0)
                            Capsule()
                                .fill(day.answers > 0 ? Color.white : Color.white.opacity(0.22))
                                .frame(height: max(8, geometry.size.height * Double(day.answers) / Double(top)))
                        }
                    }
                    Text(day.day, format: .dateTime.weekday(.narrow))
                        .font(.system(size: 13, weight: .semibold)).opacity(0.85)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func bar(_ value: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(.white).frame(width: max(10, geometry.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 10)
    }

    private func figure(_ value: Int, _ label: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number).font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit()
            label.font(.system(size: 12, weight: .semibold)).opacity(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Sharing

enum StoryShare {
    /// The story picture as a 1080 × 1920 image.
    @MainActor static func image(_ moment: StoryMoment, theme: StoryTheme, locale: Locale) -> UIImage? {
        let renderer = ImageRenderer(content: StoryCard(moment: moment, theme: theme).environment(\.locale, locale))
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(StoryCard.size)
        return renderer.uiImage
    }
}

/// Preview of the picture with the system share sheet; the person picks where it goes. Several
/// pictures page sideways; the swatches below pick the colors, remembered for next time.
struct StoryShareSheet: View {
    let moments: [StoryMoment]
    @Environment(\.locale) private var locale
    @AppStorage("storyTheme") private var theme: StoryTheme = .blue
    @State private var selected: StoryMoment
    @State private var image: UIImage?

    init(moments: [StoryMoment]) {
        self.moments = moments
        _selected = State(initialValue: moments[0])
    }

    init(moment: StoryMoment) {
        self.init(moments: [moment])
    }

    var body: some View {
        VStack(spacing: 20) {
            TabView(selection: $selected) {
                ForEach(moments) { moment in
                    preview(moment)
                        .padding(.bottom, moments.count > 1 ? 36 : 0)
                        .tag(moment)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("Story picture"))
                        .accessibilityValue(moment.styleName)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: moments.count > 1 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .frame(maxHeight: .infinity)
            swatches
            ShareLink(item: Image(uiImage: image ?? UIImage()),
                      preview: SharePreview(Text(verbatim: AppBrand.name), image: Image(uiImage: image ?? UIImage()))) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(image == nil)
        }
        .padding(20)
        .screenBackground()
        .navigationTitle("Share")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(selected.hashValue)-\(theme.rawValue)") {
            image = StoryShare.image(selected, theme: theme, locale: locale)
        }
    }

    /// The picture itself, scaled to fit.
    private func preview(_ moment: StoryMoment) -> some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / StoryCard.size.width, geometry.size.height / StoryCard.size.height)
            StoryCard(moment: moment, theme: theme)
                .scaleEffect(scale)
                .frame(width: StoryCard.size.width * scale, height: StoryCard.size.height * scale)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var swatches: some View {
        HStack(spacing: 14) {
            ForEach(StoryTheme.allCases) { option in
                Button { withAnimation(.snappy) { theme = option } } label: {
                    Circle()
                        .fill(LinearGradient(colors: option.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 32, height: 32)
                        .padding(4)
                        .overlay(Circle().stroke(option == theme ? Color.primary : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.name)
                .accessibilityAddTraits(option == theme ? .isSelected : [])
            }
        }
    }
}
