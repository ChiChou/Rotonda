import SwiftUI

/// Widths that keep text and cards comfortable to read on iPad. On iPhone the screen is
/// narrower than all of them, so these layouts change nothing there.
enum ReadableWidth {
    /// One column of cards or text.
    static let column: CGFloat = 680
    /// Two columns of cards side by side.
    static let wide: CGFloat = 1080
    /// Narrowest window that shows two columns of cards.
    static let twoColumns: CGFloat = 760
}

extension View {
    /// Caps the content at a readable width, centred in the space it is given.
    func readableWidth(_ maxWidth: CGFloat = ReadableWidth.column, alignment: Alignment = .top) -> some View {
        frame(maxWidth: maxWidth).frame(maxWidth: .infinity, alignment: alignment)
    }

    /// For lists: widens the side margins so rows keep a readable width. Unchanged when the
    /// list is already narrower than that, so iPhone keeps the system margins.
    func readableListMargins(_ maxWidth: CGFloat = ReadableWidth.column) -> some View {
        modifier(ReadableListMargins(maxWidth: maxWidth))
    }
}

private struct ReadableListMargins: ViewModifier {
    let maxWidth: CGFloat
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        if sizeClass == .compact {
            content
        } else {
            content
            .safeAreaPadding(.horizontal, max((width - maxWidth) / 2, 0))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }
    }
}

/// Tells its content whether the window is wide enough for two columns of cards, and keeps
/// the result at a readable width. Never wide in compact width, so iPhone is unaffected.
struct WideLayout<Content: View>: View {
    @ViewBuilder var content: (_ wide: Bool) -> Content
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var width: CGFloat = 0

    var body: some View {
        let wide = sizeClass == .regular && !dynamicTypeSize.isAccessibilitySize && width >= ReadableWidth.twoColumns
        content(wide)
            .readableWidth(wide ? ReadableWidth.wide : ReadableWidth.column)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// Cards in one column, or in two side by side when the window is wide enough.
struct AdaptiveColumns<Leading: View, Trailing: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        WideLayout { wide in
            if wide {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: spacing) { leading }
                    VStack(alignment: .leading, spacing: spacing) { trailing }
                }
            } else {
                VStack(alignment: .leading, spacing: spacing) {
                    leading
                    trailing
                }
            }
        }
    }
}

/// What a split-view column shows, chosen by links in the column to its left.
@Observable
final class SplitColumn {
    private(set) var view: AnyView?
    private(set) var selection: AnyHashable?
    /// Changes with every choice, so pages pushed from the previous choice close.
    private(set) var generation = 0
    /// Translation toggles showing in this column. While there is one, the columns to its left
    /// hide theirs, so the split view keeps one toggle, beside the page being read.
    var translationToggles: Set<UUID> = []

    init<V: View>(selection: AnyHashable? = nil, @ViewBuilder initial: () -> V) {
        self.selection = selection
        if selection != nil { view = AnyView(initial()) }
    }

    init() {}

    func show<V: View>(_ id: AnyHashable, _ content: V) {
        view = AnyView(content)
        selection = id
        generation += 1
    }
}

extension EnvironmentValues {
    /// Set in a split view's list columns: links open their page in the next column
    /// instead of pushing it.
    @Entry var splitTarget: SplitColumn? = nil
    /// The split-view column a view is in; nil in the leftmost column and on iPhone.
    @Entry var splitColumn: SplitColumn? = nil
}

/// A link to a page. iPhone: pushes it. In an iPad split view: opens it in the next column
/// and marks its row as selected.
struct SplitLink<Label: View, Destination: View>: View {
    let id: AnyHashable
    /// Rows inside a card mark their selection themselves; list rows use the row background.
    var inCard = false
    @ViewBuilder let destination: () -> Destination
    @ViewBuilder let label: Label
    @Environment(\.splitTarget) private var target

    init(id: AnyHashable, inCard: Bool = false, @ViewBuilder destination: @escaping () -> Destination, @ViewBuilder label: () -> Label) {
        self.id = id
        self.inCard = inCard
        self.destination = destination
        self.label = label()
    }

    var body: some View {
        if let target {
            let selected = target.selection == id
            Button { target.show(id, destination()) } label: {
                label.contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
            .background {
                if inCard && selected {
                    Color(UIColor.systemGray5)
                        .padding(.horizontal, -16)
                        .padding(.vertical, -12)
                }
            }
            .listRowBackground(selected ? Color(UIColor.systemGray4) : nil)
            .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            NavigationLink(destination: destination) { label }
        }
    }
}

/// A tab's navigation. iPhone: one stack, as before. iPad: the tab's root in a sidebar and
/// the page it opens beside it, with an optional middle column for lists.
struct AdaptiveNavigation<Root: View, Placeholder: View>: View {
    var threeColumns = false
    @State var content: SplitColumn
    @State private var detail = SplitColumn()
    @ViewBuilder var root: Root
    @ViewBuilder var placeholder: Placeholder
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Two columns: the root and its pages.
    init(@ViewBuilder root: () -> Root, @ViewBuilder placeholder: () -> Placeholder) {
        self.threeColumns = false
        _content = State(initialValue: SplitColumn())
        self.root = root()
        self.placeholder = placeholder()
    }

    /// Three columns: the root, the list it opens (starting with `initial`), and that list's pages.
    init<Initial: View>(initialList id: AnyHashable, @ViewBuilder initial: () -> Initial,
                        @ViewBuilder root: () -> Root, @ViewBuilder placeholder: () -> Placeholder) {
        self.threeColumns = true
        _content = State(initialValue: SplitColumn(selection: id, initial: initial))
        self.root = root()
        self.placeholder = placeholder()
    }

    var body: some View {
        if sizeClass == .compact {
            NavigationStack { root }
        } else if threeColumns {
            NavigationSplitView {
                root
                    .environment(\.splitTarget, content)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 400)
            } content: {
                (content.view ?? AnyView(placeholder))
                    .id(content.generation)
                    .environment(\.splitTarget, detail)
                    .environment(\.splitColumn, content)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
                    .onChange(of: content.generation) { detail = SplitColumn() }
            } detail: {
                detailStack
            }
        } else {
            NavigationSplitView {
                root
                    .environment(\.splitTarget, detail)
                    .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
            } detail: {
                detailStack
            }
        }
    }

    private var detailStack: some View {
        NavigationStack { detail.view ?? AnyView(placeholder) }
            .id(detail.generation)
            .environment(\.splitColumn, detail)
    }
}

/// The empty side of a split view before anything is chosen.
struct SplitPlaceholder: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .screenBackground()
    }
}
