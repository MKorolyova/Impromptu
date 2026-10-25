//
//  MyStatusCard.swift
//  Impromptu-app
//

import SwiftUI

/// Top of the home screen: who you are, your status in the widget's design, and the composer.
struct MyStatusCard: View {
    @Bindable var viewModel: HomeViewModel
    /// Opens every activity, searchable, to pick one outside your saved list.
    let onBrowseActivities: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            StatusCard(status: viewModel.activeMyStatus.map { StatusSnapshot($0) }, timezone: viewModel.user.timezone)
                .frame(height: 112)
            Divider()
            StatusComposer(viewModel: viewModel, onBrowseActivities: onBrowseActivities)
        }
        .padding(16)
        .cardBackground()
    }

    private var header: some View {
        HStack(spacing: 14) {
            AvatarView(id: viewModel.user.id, firstName: viewModel.user.firstName, lastName: viewModel.user.lastName,
                       size: 64, isActive: viewModel.activeMyStatus != nil, usesBrandColors: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.user.displayName)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Group {
                    if let status = viewModel.activeMyStatus {
                        Text("Sharing since \(status.startedAt, style: .time)")
                    } else {
                        Text("Not sharing a status")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Note first, then the activity drop-down, then Update Status.
private struct StatusComposer: View {
    @Bindable var viewModel: HomeViewModel
    let onBrowseActivities: () -> Void

    private var isNoteTooLong: Bool {
        viewModel.draft.note.count > StatusDraft.maxNoteLength
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Update your status")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .trailing, spacing: 4) {
                TextField("Add a note (optional)", text: $viewModel.draft.note, axis: .vertical)
                    .lineLimit(1...4)
                    .brandField()
                if viewModel.draft.note.count > StatusDraft.maxNoteLength - 40 {
                    Text("\(viewModel.draft.note.count)/\(StatusDraft.maxNoteLength)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(isNoteTooLong ? Color.red : Color.secondary)
                }
            }

            activityMenu

            Button {
                Task { await viewModel.publishDraft() }
            } label: {
                if viewModel.isUpdatingStatus {
                    ProgressView()
                        .tint(Color.onBrandAccent)
                } else {
                    Text("Update Status")
                }
            }
            .buttonStyle(.brand)
            .disabled(!viewModel.canPublishDraft)

            footer
        }
    }

    private var activityMenu: some View {
        Menu {
            Picker("Activity", selection: $viewModel.draft.activity) {
                ForEach(viewModel.myActivities) { activity in
                    Label(activity.name, systemImage: ActivitySymbol.name(for: activity.name))
                        .tag(Optional(activity))
                }
            }
            Divider()
            Button("More Activities…", systemImage: "magnifyingglass", action: onBrowseActivities)
        } label: {
            HStack(spacing: 12) {
                if let activity = viewModel.draft.activity {
                    ActivityIcon(activityName: activity.name, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity.name)
                            .font(.body.weight(.semibold))
                        Text("Until about \(Date.now.addingTimeInterval(activity.defaultDuration), style: .time)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "square.grid.2x2")
                        .frame(width: 34, height: 34)
                        .foregroundStyle(.secondary)
                    Text("Choose an activity")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .insetBackground()
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Activity")
        .accessibilityValue(viewModel.draft.activity?.name ?? "None")
    }

    @ViewBuilder
    private var footer: some View {
        if viewModel.showsUpdateConfirmation {
            Label("Status updated. Friends can see it now.", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.brandAccent)
                .frame(maxWidth: .infinity)
                .transition(.opacity)
                .task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { viewModel.dismissUpdateConfirmation() }
                }
        } else if viewModel.activeMyStatus != nil {
            Button("Clear Status", role: .destructive) {
                Task { await viewModel.clearStatus() }
            }
            .font(.footnote.weight(.semibold))
            .frame(maxWidth: .infinity)
            .disabled(viewModel.isUpdatingStatus)
        }
    }
}

#Preview {
    @Previewable @State var viewModel = HomeViewModel(user: SampleData.user, services: .mock())
    ScrollView {
        MyStatusCard(viewModel: viewModel, onBrowseActivities: {})
            .padding()
    }
    .background(Color.appBackground)
    .task { await viewModel.load() }
}
