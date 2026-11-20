import SwiftUI
import UIKit

extension View {
    func screenBackground() -> some View { background(Color.screen.ignoresSafeArea()) }

    /// `fillsHeight` stretches the card to the tallest card in its row.
    func cardStyle(padding: CGFloat = 16, fillsHeight: Bool = false) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil,
                   alignment: fillsHeight ? .topLeading : .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    var fillsHeight = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .cardStyle(padding: padding, fillsHeight: fillsHeight)
            // Row highlights extend into the padding; keep them inside the rounded card.
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// A round blue sign with a white ring, echoing the app icon. Used for chapter numbers.
struct SignBadge: View {
    let text: String
    var size: CGFloat = 40
    var tint: AnyShapeStyle = AnyShapeStyle(.signGradient)

    var body: some View {
        Text(text)
            .font(.system(size: size * 0.4, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(tint))
            .overlay(Circle().inset(by: size * 0.06).stroke(.white.opacity(0.9), lineWidth: max(1.5, size * 0.04)))
            .accessibilityHidden(true)
    }
}

struct ThinProgressBar: View {
    let value: Double
    var tint: Color = .signBlue
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.15))
                Capsule().fill(tint).frame(width: max(height, geometry.size.width * min(max(value, 0), 1)))
                    .opacity(value > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
    }
}

struct RingProgress: View {
    let value: Double
    var tint: Color = .signBlue
    var lineWidth: CGFloat = 6
    var label: String? = nil

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle().trim(from: 0, to: min(max(value, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let label {
                Text(label).font(.system(.caption, design: .rounded).weight(.bold)).monospacedDigit()
            }
        }
    }
}

struct VerdictLabel: View {
    let answer: Bool
    var compact = false

    var body: some View {
        // An HStack rather than a Label: in a List a Label's icon takes a wide list-icon column.
        HStack(spacing: compact ? 4 : 6) {
            Image(systemName: answer ? "checkmark.circle.fill" : "xmark.circle.fill")
            Text(verbatim: answer ? "VERO" : "FALSO")
        }
            .font(compact ? .caption.weight(.heavy) : .subheadline.weight(.heavy))
            .foregroundStyle(answer ? Color.vero : Color.falso)
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, compact ? 4 : 7)
            .background((answer ? Color.vero : Color.falso).opacity(0.12), in: Capsule())
            .fixedSize()
            .accessibilityElement(children: .combine)
    }
}

struct Pill: View {
    let text: Text
    var tint: Color = .secondary

    init(_ text: Text, tint: Color = .secondary) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        text.font(.caption.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct SectionTitle: View {
    let title: LocalizedStringKey
    var detail: Text? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Spacer()
            detail.font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}

/// A full-width filled capsule. Liquid Glass tinted with the colour on iOS 26 and later.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = .signBlue
    var labelColor: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.headline)
            .foregroundStyle(labelColor)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
        if #available(iOS 26, *) {
            label
                .contentShape(Capsule())
                .glassEffect(.regular.tint(tint).interactive(), in: Capsule())
        } else {
            label
                .background(tint.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

/// A full-width capsule in the tint colour on a light background, or clear Liquid Glass.
struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = .signBlue

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.headline)
            .foregroundStyle(tint)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 14)
        if #available(iOS 26, *) {
            label
                .contentShape(Capsule())
                .glassEffect(.regular.tint(tint.opacity(0.12)).interactive(), in: Capsule())
        } else {
            label.background(tint.opacity(configuration.isPressed ? 0.2 : 0.12), in: Capsule())
        }
    }
}

extension View {
    /// Liquid Glass buttons on iOS 26 and later; bordered buttons before.
    @ViewBuilder func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}

/// The one main action of a card: a filled capsule with the label alone.
struct FilledButtonStyle: ButtonStyle {
    var tint: Color = .signBlue

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .background(tint, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

/// A navigation-style row inside a card: icon, title, optional detail and trailing accessory.
struct FeatureRow<Trailing: View>: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    var subtitle: Text? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                // Decorative: symbols such as checkmark.circle.fill would otherwise read as "Selected".
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Color.primary)
                subtitle.font(.caption).foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 8)
            trailing
        }
        .contentShape(Rectangle())
    }
}

extension FeatureRow where Trailing == AnyView {
    init(icon: String, tint: Color, title: LocalizedStringKey, subtitle: Text? = nil) {
        self.init(icon: icon, tint: tint, title: title, subtitle: subtitle) {
            AnyView(Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color(UIColor.tertiaryLabel)))
        }
    }
}

struct QuizImage: View {
    let name: String
    var maxHeight: CGFloat = 200
    /// Off: the white backing hugs the picture instead of spanning the width, for small previews.
    var fillsWidth = true

    var body: some View {
        if let image = Self.load(name) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: fillsWidth ? .infinity : maxHeight * image.size.width / max(image.size.height, 1),
                       maxHeight: maxHeight)
                .padding(8)
                .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text("Road sign or traffic diagram"))
        }
    }

    private static let cache = NSCache<NSString, UIImage>()

    static func load(_ name: String) -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        let file = (name as NSString).lastPathComponent as NSString
        let url = Bundle.main.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension)
            ?? Bundle.main.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension, subdirectory: "StudyImages")
        guard let url, let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}

/// A whole card that acts as one button: shades and shrinks slightly while pressed.
struct CardButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.08 : 0))
                    .allowsHitTesting(false)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A row inside a card: highlighted edge to edge while pressed, like a list cell. The
/// highlight reaches into the card's padding and row spacing; `Card` clips it to its corners.
struct RowButtonStyle: ButtonStyle {
    /// How far the highlight reaches above and below the row: half the gap to its neighbours.
    var vertical: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Color(UIColor.systemGray4)
                    .opacity(configuration.isPressed ? 1 : 0)
                    .padding(.horizontal, -16)
                    .padding(.vertical, -vertical)
            }
    }
}

/// The start marker on a card that is itself a button. On a tinted card it turns white.
struct PlayBadge: View {
    let tint: Color
    var onTintedCard = false

    var body: some View {
        Image(systemName: "play.fill")
            .font(.body.weight(.semibold))
            .foregroundStyle(onTintedCard ? tint : .white)
            .frame(width: 44, height: 44)
            .background(onTintedCard ? Color.white : tint, in: Circle())
            .accessibilityHidden(true)
    }
}
