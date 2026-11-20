import SwiftUI

/// One licence: its Italian name, and what it lets you drive in the helper language.
struct LicenceLabel: View {
    let licence: Licence

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: licence.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.signBlue)
                .frame(width: 36, height: 36)
                .background(Color.signBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: licence.name).font(.body.weight(.medium))
                Text(licence.vehicles).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Licences in the bundled database: first licences, then revision exams.
@MainActor private func offered(_ licences: [Licence]) -> [Licence] {
    licences.filter(ContentStore.shared.availableLicences.contains)
}

/// The licence choice in the first-launch guide, as tappable rows in cards.
struct GuideLicencePicker: View {
    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Which licence?").font(.title.bold())
            group(offered(Licence.firstLicences))
            Text("Revision exam").font(.headline).padding(.top, 4)
            group(offered(Licence.revisions))
            Text("Change it any time in Progress and settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func group(_ licences: [Licence]) -> some View {
        ChoiceCard(licences, selection: preferences.licence) { preferences.licence = $0 } label: { LicenceLabel(licence: $0) }
    }
}

/// One choice among a few, as tappable rows in a card with a checkmark on the selected one.
/// The guide's language and licence pages share it.
struct ChoiceCard<Item: Identifiable & Equatable, Label: View>: View where Item.ID == String {
    let items: [Item]
    let selection: Item
    let select: (Item) -> Void
    @ViewBuilder let label: (Item) -> Label

    init(_ items: [Item], selection: Item, select: @escaping (Item) -> Void, @ViewBuilder label: @escaping (Item) -> Label) {
        self.items = items
        self.selection = selection
        self.select = select
        self.label = label
    }

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(items) { item in
                    if item != items.first { Divider().padding(.leading, 66) }
                    Button { select(item) } label: {
                        HStack {
                            label(item)
                            Spacer(minLength: 8)
                            if item == selection {
                                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Color.signBlue)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(item == selection ? .isSelected : [])
                    .accessibilityIdentifier("choice-\(item.id)")
                }
            }
        }
    }
}

/// The licence choice in settings. Choosing one goes back to settings.
struct LicencePickerView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            section(offered(Licence.firstLicences))
            section(offered(Licence.revisions), header: Text("Revision exam"))
        }
        .navigationTitle("Licence")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ licences: [Licence], header: Text? = nil) -> some View {
        Section {
            ForEach(licences) { licence in
                Button {
                    preferences.licence = licence
                    dismiss()
                } label: {
                    HStack {
                        LicenceLabel(licence: licence)
                        Spacer(minLength: 8)
                        if licence == preferences.licence {
                            Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Color.signBlue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(licence == preferences.licence ? .isSelected : [])
                .accessibilityIdentifier("licence-\(licence.rawValue)")
            }
        } header: {
            header
        }
    }
}
