//
//  StatusSourceRow.swift
//  Impromptu-app
//

import SwiftUI

extension StatusSource {
    var title: String {
        switch self {
        case .manual: "Manual"
        case .calendar: "Calendar"
        case .location: "Location"
        case .automated: "Automatic"
        }
    }

    var symbol: String {
        switch self {
        case .manual: "hand.tap.fill"
        case .calendar: "calendar"
        case .location: "location.fill"
        case .automated: "sparkles"
        }
    }

    /// How it works, in a sentence or two.
    var hint: String {
        switch self {
        case .manual:
            "You pick your activity and add a note yourself. It stays until it ends or you change it."
        case .calendar:
            "Reads events from your calendar, sorts each one into a standard activity and shows it as your status, so friends always stay up to date with your plans."
        case .location:
            "Updates your activity when you arrive somewhere you go often, like “At the gym” when you get to the gym."
        case .automated:
            "Suggests a status from how you use your phone, like “Sleeping” after a quiet night. You can always change it."
        }
    }
}

/// A checkbox with the source's name and a short hint on how it works.
struct StatusSourceRow: View {
    let source: StatusSource
    @Binding var isOn: Bool
    /// Extra line, e.g. what's still needed for this source to work.
    var note: String?

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundStyle(isOn ? Color.brandAccent : Color.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Label(source.title, systemImage: source.symbol)
                        .font(.headline)
                    Text(source.hint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note {
                        Text(note)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.brandAccent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .insetBackground()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var sources: Set<StatusSource> = [.manual]
    VStack {
        ForEach(StatusSource.allCases) { source in
            StatusSourceRow(source: source, isOn: Binding(
                get: { sources.contains(source) },
                set: { if $0 { sources.insert(source) } else { sources.remove(source) } }
            ))
        }
    }
    .padding()
    .background(Color.surface)
}
