import SwiftUI

/// Browse study material with native horizontal paging. Vertical scrolling is reserved
/// for content that is taller than the screen, rather than advancing to another item.
struct StudyPager<Item: Identifiable, Page: View>: View {
    let items: [Item]
    @Binding var position: Int?
    @ViewBuilder let page: (Item) -> Page
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Room for the iPad edge buttons when a narrow column leaves no margin beside the page.
    private var edgeInset: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad && sizeClass == .regular ? 56 : 0
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(items.indices, id: \.self) { index in
                            ViewThatFits(in: .vertical) {
                                page(items[index])
                                    .padding(.trailing, 16)
                                    .padding(.vertical, 8)
                                    .readableWidth()
                                    .padding(.horizontal, edgeInset)
                                ScrollView(.vertical) {
                                    page(items[index])
                                        .padding(.trailing, 16)
                                        .padding(.vertical, 8)
                                        .readableWidth()
                                        .padding(.horizontal, edgeInset)
                                }
                                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                            }
                            // Top-aligned, so short and long pages start at the same place.
                            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                            .id(index)
                            .accessibilityHidden(index != (position ?? 0))
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $position, anchor: .center)
                // Restore the visible offset as well as the counter when a pager is recreated.
                .onAppear { proxy.scrollTo(position ?? 0, anchor: .center) }
            }
        }
        // Keep the existing left margin outside the scroller so edge swipes reach Back.
        .padding(.leading, 16)
        .onChange(of: position) { SpeechController.shared.stop() }
        .accessibilityAction(named: Text("Next")) {
            position = min((position ?? 0) + 1, max(items.count - 1, 0))
        }
        .accessibilityAction(named: Text("Previous")) {
            position = max((position ?? 0) - 1, 0)
        }
        .pagerEdgeButtons(canGoBack: (position ?? 0) > 0, canGoForward: (position ?? 0) < items.count - 1,
                          back: { withAnimation(.snappy) { position = max((position ?? 0) - 1, 0) } },
                          forward: { withAnimation(.snappy) { position = min((position ?? 0) + 1, items.count - 1) } })
    }
}

extension View {
    /// Previous and next buttons at the screen's side edges on iPad, where the thumbs rest and a
    /// swipe across the middle of a large screen is a reach. iPhone keeps the swipe alone.
    func pagerEdgeButtons(canGoBack: Bool, canGoForward: Bool,
                          back: @escaping () -> Void, forward: @escaping () -> Void) -> some View {
        modifier(PagerEdgeButtons(canGoBack: canGoBack, canGoForward: canGoForward, back: back, forward: forward))
    }
}

private struct PagerEdgeButtons: ViewModifier {
    let canGoBack: Bool
    let canGoForward: Bool
    let back: () -> Void
    let forward: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var active: Bool { UIDevice.current.userInterfaceIdiom == .pad && sizeClass == .regular }

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                HStack {
                    edgeButton("chevron.left", label: Text("Previous"), shown: canGoBack, action: back)
                    Spacer(minLength: 0)
                    edgeButton("chevron.right", label: Text("Next"), shown: canGoForward, action: forward)
                }
                .padding(.horizontal, 12)
            }
        }
    }

    @ViewBuilder
    private func edgeButton(_ icon: String, label: Text, shown: Bool, action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.signBlue)
        .accessibilityLabel(label)
        Group {
            if #available(iOS 26, *) {
                button.glassEffect(.regular.interactive(), in: Circle())
            } else {
                button.background(.regularMaterial, in: Circle())
            }
        }
        // Hidden, not greyed, at either end and before a session card is answered.
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(shown)
        .accessibilityHidden(!shown)
        .animation(.snappy, value: shown)
    }
}

/// A pager pushed from a list. It opens on the row that was tapped and hides the tab bar.
struct PushedPager<Item: Identifiable, Page: View, JumpRow: View>: View {
    let title: Text
    let items: [Item]
    @ViewBuilder let page: (Item) -> Page
    /// For a long pager: what a jump-list search matches, and how each page is listed.
    let jumpSearch: ((Item) -> String)?
    let jumpRow: ((Item) -> JumpRow)?

    @State private var position: Int?
    @State private var showsJumpList = false

    init(title: Text, items: [Item], start: Int, @ViewBuilder page: @escaping (Item) -> Page,
         jumpSearch: ((Item) -> String)? = nil, @ViewBuilder jumpRow: @escaping (Item) -> JumpRow) {
        self.title = title
        self.items = items
        self.page = page
        self.jumpSearch = jumpSearch
        self.jumpRow = jumpRow
        _position = State(initialValue: start)
    }

    var body: some View {
        let counter = Text(verbatim: "\(min((position ?? 0) + 1, items.count))/\(items.count)")
            .font(.subheadline.monospacedDigit())
        StudyPager(items: items, position: $position, page: page)
            .screenBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                TranslationToggleItem()
                ToolbarItem(placement: .topBarTrailing) {
                    if let jumpSearch, jumpRow != nil, items.count > 1 {
                        Button { showsJumpList = true } label: { counter.padding(.horizontal, 6) }
                            .accessibilityLabel(Text("Go to"))
                            .accessibilityValue(counter)
                            .sheet(isPresented: $showsJumpList) {
                                CloseSheet(detents: [.large]) {
                                    PageJumpList(items: items, current: position ?? 0, searchText: jumpSearch,
                                                 select: { position = $0 }) { jumpRow?($0) }
                                }
                            }
                    } else {
                        counter.foregroundStyle(.secondary).padding(.horizontal, 6)
                    }
                }
            }
            .modifier(HidesTabBarOnPhone())
            .onDisappear { SpeechController.shared.stop() }
    }
}

extension PushedPager where JumpRow == EmptyView {
    init(title: Text, items: [Item], start: Int, @ViewBuilder page: @escaping (Item) -> Page) {
        self.title = title
        self.items = items
        self.page = page
        self.jumpSearch = nil
        self.jumpRow = nil
        _position = State(initialValue: start)
    }
}

/// A sheet with its own navigation and a close button, for details opened from a page.
struct CloseSheet<Content: View>: View {
    var detents: Set<PresentationDetent> = [.medium, .large]
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content.closeToolbar { dismiss() }
        }
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
    }
}

/// The close button of a sheet that only shows things: a glass X on the leading side, apart
/// from the screen's own buttons on the trailing side (translation, counter, share).
struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        if #available(iOS 26, *) {
            Button(role: .close, action: action)
        } else {
            Button(action: action) { Label("Close", systemImage: "xmark") }
        }
    }
}

extension View {
    func closeToolbar(_ close: @escaping () -> Void) -> some View {
        toolbar { ToolbarItem(placement: .cancellationAction) { CloseButton(action: close) } }
    }
}

/// Pages hide the bottom tab bar on iPhone. On iPad the tab bar sits above the split view
/// and stays, like the list beside the page.
private struct HidesTabBarOnPhone: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content.toolbar(sizeClass == .compact ? .hidden : .automatic, for: .tabBar)
    }
}

/// Every page of a long pager as a searchable list, opened from its counter: jump straight
/// to any page instead of swiping through hundreds. The current page is highlighted and in view.
/// Pages are grouped in numbered blocks, with a section index on the side on iOS 26 and later.
struct PageJumpList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    let current: Int
    /// The text a search matches, besides the page number.
    let searchText: (Item) -> String
    let select: (Int) -> Void
    @ViewBuilder let row: (Item) -> Row

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    /// Shorter lists stay one plain list, without block headers or a side index.
    private static var indexThreshold: Int { 60 }
    private var showsIndex: Bool { items.count >= Self.indexThreshold }

    /// Blocks of 10, 20 or 30, whichever keeps the index to at most 30 marks; longer lists,
    /// like all 3,000 words, use bigger round blocks.
    private var blockSize: Int {
        [10, 20, 30, 50, 100, 200, 500].first { (items.count + $0 - 1) / $0 <= 30 } ?? 1000
    }

    private func sections(_ indices: [Int]) -> [(title: String, indices: [Int])] {
        var result: [(title: String, indices: [Int])] = []
        for index in indices {
            let title = showsIndex ? String(index / blockSize * blockSize + 1) : ""
            if result.last?.title == title { result[result.count - 1].indices.append(index) }
            else { result.append((title, [index])) }
        }
        return result
    }

    var body: some View {
        let term = ContentStore.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        let indices = items.indices.filter {
            term.isEmpty || String($0 + 1) == term || ContentStore.fold(searchText(items[$0])).contains(term)
        }
        ScrollViewReader { proxy in
            List {
                if indices.isEmpty { ContentUnavailableView.search(text: query) }
                ForEach(sections(indices), id: \.title) { section in
                    Section {
                        ForEach(section.indices, id: \.self) { index in
                            Button {
                                select(index)
                                dismiss()
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(index + 1, format: .number)
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(index == current ? Color.signBlue : Color.secondary)
                                        .frame(minWidth: 34, alignment: .trailing)
                                    row(items[index])
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(index == current ? Color.signBlue.opacity(0.12) : nil)
                            .accessibilityAddTraits(index == current ? .isSelected : [])
                            .id(index)
                        }
                    } header: {
                        if showsIndex { Text(verbatim: section.title) }
                    }
                    .modifier(SectionIndexLabel(title: section.title, isShown: showsIndex))
                }
            }
            .modifier(VisibleSectionIndex(isShown: showsIndex))
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .onAppear { proxy.scrollTo(current, anchor: .center) }
        }
        .navigationTitle("Go to")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The section's mark in the side index; the index is iOS 26 and later.
private struct SectionIndexLabel: ViewModifier {
    let title: String
    let isShown: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26, *), isShown {
            content.sectionIndexLabel(Text(verbatim: title))
        } else {
            content
        }
    }
}

private struct VisibleSectionIndex: ViewModifier {
    let isShown: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26, *), isShown {
            content.listSectionIndexVisibility(.visible)
        } else {
            content
        }
    }
}

/// A statement in a jump list: its picture, if any, and the Italian text.
struct QuestionJumpRow: View {
    let question: Question

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let image = question.image, let uiImage = QuizImage.load(image) {
                Image(uiImage: uiImage).resizable().scaledToFit()
                    .frame(width: 36, height: 36)
                    .background(.white, in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityHidden(true)
            }
            Text(question.textIT).font(.subheadline).foregroundStyle(Color.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
    }
}
