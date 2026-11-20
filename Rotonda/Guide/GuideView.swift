import SwiftUI

/// Shown over the app on first launch, and again from the profile sheet: what the app is,
/// where things are, and the settings worth choosing before the first session.
struct GuideView: View {
    @Environment(Preferences.self) private var preferences
    @State private var page: Int? = 0
    private let pageCount = 3

    private var current: Int { page ?? 0 }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        ScrollView(.vertical) {
                            // The page's height inside its vertical padding.
                            pageContent(index, height: geometry.size.height - 32)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 16)
                                .readableWidth(520, alignment: .center)
                                // Centred when the page is shorter than the screen.
                                .frame(minHeight: geometry.size.height)
                        }
                        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .id(index)
                        .accessibilityHidden(index != current)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .screenBackground()
    }

    @ViewBuilder
    private func pageContent(_ index: Int, height: CGFloat) -> some View {
        switch index {
        // The language tiles sit at the bottom of the page so they stay still when the text
        // above changes length with the language.
        case 0: BottomPinnedLayout(minHeight: height, spacing: 28) {
            welcome
            // Clear of the page dots, so the two small rows don't read as one group.
            GuideLanguageChoice().padding(.bottom, 32)
        }
        case 1: GuideLicencePicker()
        default: tour
        }
    }

    private var welcome: some View {
        VStack(spacing: 28) {
            VStack(spacing: 14) {
                Image("LaunchEmblem")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104, height: 104)
                    .accessibilityHidden(true)
                Text("Study for your Italian driving test")
                    .font(.largeTitle.bold())
                Text("Learn the rules and the Italian at the same time.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 14) {
                highlight("checklist", Text("Every official question, for every licence"))
                highlight("translate", Text("A translation under every sentence"))
                highlight("character.book.closed.fill", Text("The exam's vocabulary, word by word"))
                highlight("timer", Text("Mock exams just like the real one"))
            }
        }
    }

    private func highlight(_ icon: String, _ text: Text) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.signBlue)
                .frame(width: 28)
                .accessibilityHidden(true)
            text.font(.body.weight(.medium))
        }
    }

    private var tour: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Find your way around").font(.title.bold())
            Card {
                tourRow("sun.horizon.fill", .amberInk, "Today", Text("A few minutes of study each day"))
                tourRow("signpost.right.and.left.fill", .signBlue, "Learn", Text("The theory, chapter by chapter"))
                tourRow("checkmark.circle.fill", .vero, "Quiz", Text("Practice questions and the mock exam"))
                tourRow("rectangle.on.rectangle.angled", .signBlueDeep, "Memorize", Text("Words, signs and facts to drill"))
                tourRow("magnifyingglass", .secondary, "Search", Text("Look up any word or question"))
            }
        }
    }

    private func tourRow(_ icon: String, _ tint: Color, _ title: LocalizedStringKey, _ subtitle: Text) -> some View {
        FeatureRow(icon: icon, tint: tint, title: title, subtitle: subtitle) { EmptyView() }
            .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        let isLast = current == pageCount - 1
        return VStack(spacing: 16) {
            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Circle()
                        .fill(index == current ? Color.signBlue : Color.signBlue.opacity(0.2))
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityHidden(true)
            Button {
                if isLast {
                    withAnimation { preferences.hasSeenGuide = true }
                } else {
                    withAnimation(.snappy) { page = current + 1 }
                }
            } label: {
                Text(isLast ? "Start studying" : "Continue")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("guideAdvance")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .readableWidth(520)
    }
}

/// Stacks its subviews with the last one pinned to the bottom of at least `minHeight`, and the
/// others centred in the space above it. Taller than `minHeight` when they need to be.
private struct BottomPinnedLayout: Layout {
    var minHeight: CGFloat
    var spacing: CGFloat

    private func heights(_ subviews: Subviews, width: CGFloat?) -> [CGFloat] {
        subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
    }

    private func contentHeight(_ heights: [CGFloat]) -> CGFloat {
        heights.reduce(0, +) + spacing * CGFloat(max(heights.count - 1, 0))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        return CGSize(width: width, height: max(minHeight, contentHeight(heights(subviews, width: width))))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let last = subviews.last else { return }
        let heights = heights(subviews, width: bounds.width)
        let size = { (index: Int) in ProposedViewSize(width: bounds.width, height: heights[index]) }
        // Centred across, since a subview can be narrower than the page.
        last.place(at: CGPoint(x: bounds.midX, y: bounds.maxY - heights[heights.count - 1]),
                   anchor: .top, proposal: size(subviews.count - 1))
        // The rest, centred between the top and the pinned subview.
        let above = Array(heights.dropLast())
        let room = bounds.height - heights[heights.count - 1] - spacing
        var y = bounds.minY + max(0, (room - contentHeight(above)) / 2)
        for index in subviews.indices.dropLast() {
            subviews[index].place(at: CGPoint(x: bounds.midX, y: y), anchor: .top, proposal: size(index))
            y += heights[index] + spacing
        }
    }
}

/// The helper language in the first-launch guide: the app's text and the translations under
/// the Italian. The languages side by side in one track.
private struct GuideLanguageChoice: View {
    @Environment(Preferences.self) private var preferences

    var body: some View {
        // One quiet track, sized to its labels and narrower than Continue below, so the page
        // keeps one full-width filled control.
        HStack(spacing: 2) {
            ForEach(HelperLanguage.allCases) { language in
                let selected = language == preferences.helperLanguage
                Button { preferences.helperLanguage = language } label: {
                    Text(verbatim: language.nativeName)
                        .font(selected ? .subheadline.weight(.semibold) : .subheadline)
                        .lineLimit(1)
                        .foregroundStyle(selected ? Color.signBlue : Color.primary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 34)
                        .background(selected ? Color.signBlue.opacity(0.12) : Color.clear,
                                    in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("language-\(language.rawValue)")
            }
        }
        .padding(3)
        .background(Color.card, in: Capsule())
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Language"))
        .accessibilityIdentifier("guideLanguage")
    }
}
