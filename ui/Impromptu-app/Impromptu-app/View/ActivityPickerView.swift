//
//  ActivityPickerView.swift
//  Impromptu-app
//

import SwiftUI

/// Your activities (the list picked at sign-up, which the drop-down uses) and, separately, every other
/// activity, which you can add to your list. Picking one of yours fills the status drop-down; nothing is
/// posted until you tap Update.
struct ActivityPickerView: View {
    @Bindable var viewModel: HomeViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var isAddingActivity = false
    /// The one being added after a tap.
    @State private var addingID: ActivityChoice.ID?

    private func matches(_ name: String) -> Bool {
        query.isEmpty || name.localizedCaseInsensitiveContains(query)
    }

    private var myList: [Activity] {
        viewModel.myList.filter { matches($0.name) }
    }

    private var addable: [ActivityChoice] {
        viewModel.addableChoices.filter { matches($0.name) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("New Custom Activity", systemImage: "plus") { isAddingActivity = true }
                }

                Section {
                    if viewModel.myList.isEmpty {
                        Text("Add activities from the list below.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(myList) { activity in
                        Button {
                            viewModel.draft.activity = activity
                            dismiss()
                        } label: {
                            ActivityRow(name: activity.name, minutes: activity.defaultDurationMinutes, isCustom: activity.isCustom) {
                                if activity == viewModel.draft.activity {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .tint(.primary)
                        .swipeActions(edge: .trailing) {
                            if activity.isCustom {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    Task { await viewModel.deleteActivity(activity) }
                                }
                            }
                            if viewModel.canRemoveFromMyList(activity) {
                                Button("Remove", systemImage: "minus.circle") {
                                    Task { await viewModel.removeFromMyList(activity) }
                                }
                                .tint(.orange)
                            }
                        }
                    }
                } header: {
                    Text("Your activities")
                } footer: {
                    Text("Tap one to use it for your status. Swipe to remove it from your list.")
                }

                Section {
                    ForEach(addable) { choice in
                        Button {
                            add(choice)
                        } label: {
                            ActivityRow(name: choice.name, minutes: choice.defaultDurationMinutes, isCustom: choice.isCustom) {
                                if addingID == choice.id {
                                    ProgressView()
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .tint(.primary)
                        .disabled(addingID != nil)
                        .accessibilityHint("Adds it to your activities")
                    }
                    if addable.isEmpty {
                        Text(query.isEmpty ? "Everything is already in your list." : "No other activities match.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("All activities")
                } footer: {
                    Text("Tap to add to your activities.")
                }
            }
            .animation(.snappy, value: viewModel.myList)
            .searchable(text: $query, prompt: "Search activities")
            .navigationTitle("Activities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isAddingActivity) {
                NewActivityView(initialName: query) { name, minutes in
                    await viewModel.createAndAddActivity(name: name, durationMinutes: minutes)
                    // Close either way; on failure the home screen's alert explains why.
                    dismiss()
                }
            }
        }
    }

    private func add(_ choice: ActivityChoice) {
        addingID = choice.id
        Task {
            await viewModel.addToMyList(choice)
            addingID = nil
        }
    }
}

/// Icon, name and default length, with a trailing accessory.
private struct ActivityRow<Accessory: View>: View {
    let name: String
    let minutes: Int
    let isCustom: Bool
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            ActivityIcon(activityName: name, size: 30)
            VStack(alignment: .leading) {
                Text(name)
                Text(Duration.seconds(minutes * 60), format: .units(allowed: [.hours, .minutes], width: .abbreviated))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isCustom {
                Text("Custom")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            accessory
        }
        .contentShape(Rectangle())
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
    @Previewable @State var viewModel = HomeViewModel(user: SampleData.user, services: .mock())
    ActivityPickerView(viewModel: viewModel)
        .task { await viewModel.load() }
}
