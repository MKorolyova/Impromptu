//
//  ActivityPickerView.swift
//  Impromptu-app
//

import SwiftUI

/// Every activity, searchable, with custom ones you can add or delete.
/// Picking one fills the status drop-down; nothing is posted until you tap Update.
struct ActivityPickerView: View {
    let activities: [Activity]
    let selected: Activity?
    let onSelect: (Activity) -> Void
    /// Creates a custom activity; returns nil on failure.
    let onCreate: (String, Int) async -> Activity?
    let onDelete: (Activity) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var isAddingActivity = false

    private var filtered: [Activity] {
        query.isEmpty ? activities : activities.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("New Custom Activity", systemImage: "plus") { isAddingActivity = true }
                }
                Section {
                    ForEach(filtered) { activity in
                        Button {
                            onSelect(activity)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                ActivityIcon(activityName: activity.name, size: 30)
                                VStack(alignment: .leading) {
                                    Text(activity.name)
                                    Text(Duration.seconds(activity.defaultDuration), format: .units(allowed: [.hours, .minutes], width: .abbreviated))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if activity.isCustom {
                                    Text("Custom")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                if activity == selected {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .tint(.primary)
                        .deleteDisabled(!activity.isCustom)
                    }
                    .onDelete { offsets in
                        offsets.map { filtered[$0] }.forEach(onDelete)
                    }
                } footer: {
                    Text("Swipe a custom activity to delete it.")
                }
            }
            .searchable(text: $query, prompt: "Search activities")
            .navigationTitle("Activities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $isAddingActivity) {
                NewActivityView(initialName: query) { name, minutes in
                    if let activity = await onCreate(name, minutes) {
                        onSelect(activity)
                    }
                    // Close either way; on failure the home screen's alert explains why.
                    dismiss()
                }
            }
        }
    }
}

/// Form for `POST /users/{userId}/activities`.
private struct NewActivityView: View {
    let onSave: (String, Int) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var minutes = 60
    @State private var isSaving = false

    init(initialName: String, onSave: @escaping (String, Int) async -> Void) {
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Stepper(value: $minutes, in: 5...(24 * 60), step: 5) {
                    LabeledContent("Default length", value: Duration.seconds(minutes * 60), format: .units(allowed: [.hours, .minutes], width: .abbreviated))
                }
            }
            .navigationTitle("New Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            isSaving = true
                            await onSave(trimmedName, minutes)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(trimmedName.isEmpty || trimmedName.count > 50 || isSaving)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    ActivityPickerView(activities: SampleData.activities, selected: SampleData.activities[1],
                       onSelect: { _ in }, onCreate: { _, _ in nil }, onDelete: { _ in })
}
