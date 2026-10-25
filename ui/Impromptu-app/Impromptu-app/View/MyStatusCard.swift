//
//  MyStatusCard.swift
//  Impromptu-app
//

import SwiftUI

/// Your account at the top of the feed. Tapping it drops down a composer for your status.
struct MyStatusCard: View {
    @Bindable var viewModel: HomeViewModel
    let onBrowseActivities: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            if viewModel.isComposerOpen {
                Divider().padding(.horizontal)
                StatusComposer(viewModel: viewModel, onBrowseActivities: onBrowseActivities)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardBackground()
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var header: some View {
        Button {
            withAnimation(.snappy) { viewModel.toggleComposer() }
        } label: {
            HStack(spacing: 12) {
                AvatarView(id: viewModel.user.id, firstName: viewModel.user.firstName, lastName: viewModel.user.lastName,
                           size: 52, isActive: viewModel.activeMyStatus != nil)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(viewModel.user.firstName) \(viewModel.user.lastName)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let status = viewModel.activeMyStatus {
                        StatusLine(status: status)
                        Group {
                            if let note = status.note {
                                Text("\(note) · until \(status.expiresAt, style: .time)")
                            } else {
                                Text("until \(status.expiresAt, style: .time)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    } else {
                        Text("What are you up to?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(viewModel.isComposerOpen ? 180 : 0))
            }
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(viewModel.isComposerOpen ? "Closes the status editor" : "Opens the status editor")
    }
}

/// The drop-down: activity chips, note, duration, and update/clear.
private struct StatusComposer: View {
    @Bindable var viewModel: HomeViewModel
    let onBrowseActivities: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Activity")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.suggestedActivities) { activity in
                            ActivityChip(activity: activity, isSelected: viewModel.draft.activity == activity) {
                                viewModel.draft.activity = activity
                            }
                        }
                        Button("More", systemImage: "ellipsis", action: onBrowseActivities)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }

            TextField("Add a note (optional)", text: $viewModel.draft.note, axis: .vertical)
                .lineLimit(1...3)
                .padding(12)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                Text("For")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Duration", selection: $viewModel.draft.durationMinutes) {
                    ForEach(StatusDraft.durationOptions, id: \.self) { minutes in
                        Text(durationLabel(minutes)).tag(minutes)
                    }
                }
                .pickerStyle(.menu)
            }
            .font(.subheadline)

            HStack(spacing: 12) {
                if viewModel.activeMyStatus != nil {
                    Button("Clear", role: .destructive) {
                        Task { await viewModel.clearStatus() }
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    Task { await viewModel.publishDraft() }
                } label: {
                    Group {
                        if viewModel.isUpdatingStatus {
                            ProgressView()
                        } else {
                            Text(viewModel.activeMyStatus == nil ? "Post Status" : "Update Status")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canPublishDraft)
            }
            .controlSize(.large)
        }
        .padding()
    }

    private func durationLabel(_ minutes: Int?) -> String {
        guard let minutes else {
            guard let activity = viewModel.draft.activity else { return "Default" }
            return "Default (\(formatted(activity.defaultDurationMinutes)))"
        }
        return formatted(minutes)
    }

    private func formatted(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

private struct ActivityChip: View {
    let activity: Activity
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(activity.name, systemImage: ActivitySymbol.name(for: activity.name))
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var viewModel = HomeViewModel(user: SampleData.user, services: .mock())
    ScrollView {
        MyStatusCard(viewModel: viewModel, onBrowseActivities: {})
            .padding()
    }
    .background(Color.feedBackground)
    .task { await viewModel.load() }
}
