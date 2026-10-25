//
//  RegistrationView.swift
//  Impromptu-app
//

import AuthenticationServices
import SwiftUI

/// Sign-up as a bottom sheet, one step at a time: email and password, name, activities,
/// Google Calendar (optional), and how the status should update.
struct RegistrationView: View {
    /// Switches to the sign-in sheet.
    let onSignIn: () -> Void

    @Environment(SessionViewModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: RegistrationViewModel

    init(services: Services, onSignIn: @escaping () -> Void) {
        _viewModel = State(initialValue: RegistrationViewModel(services: services))
        self.onSignIn = onSignIn
    }

    private typealias Step = RegistrationViewModel.Step

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SheetHeader(title: viewModel.step.title, subtitle: viewModel.step.subtitle)
                    stepContent
                }
                .padding(24)
                .id(viewModel.step)
                .transition(.push(from: viewModel.isMovingBack ? .leading : .trailing))
            }
            .scrollDismissesKeyboard(.interactively)
            .animation(.snappy, value: viewModel.step)
            footer
        }
        .presentationDetents([.large])
        .brandSheet()
        // Once the account exists, finish setting it up here rather than half-signed-in.
        .interactiveDismissDisabled(viewModel.user != nil)
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            CircleIconButton(systemImage: "chevron.left", label: "Back") {
                viewModel.goBack()
            }
            .opacity(viewModel.canGoBack ? 1 : 0)
            .disabled(!viewModel.canGoBack)

            Spacer()
            StepProgress(current: viewModel.step.rawValue, total: Step.allCases.count)
            Spacer()

            CircleIconButton(systemImage: "xmark", label: "Close") { dismiss() }
                .opacity(viewModel.user == nil ? 1 : 0)
                .disabled(viewModel.user != nil)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if let errorMessage = viewModel.errorMessage {
                InlineError(message: errorMessage)
            }
            Button {
                Task { await viewModel.advance(session: session) }
            } label: {
                if viewModel.isWorking {
                    ProgressView()
                        .tint(isSkipping ? Color.brandAccent : Color.onBrandAccent)
                } else {
                    Text(primaryTitle)
                }
            }
            .buttonStyle(.brand(isSkipping ? .secondary : .primary))
            .disabled(!viewModel.canContinue)

            if viewModel.step == .credentials {
                HStack(spacing: 4) {
                    Text("Already have an account?")
                        .foregroundStyle(.secondary)
                    Button("Sign In", action: onSignIn)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.brandAccent)
                }
                .font(.subheadline)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    /// Calendar is optional: without a connection the button just moves on.
    private var isSkipping: Bool {
        viewModel.step == .calendar && viewModel.calendarState != .connected
    }

    private var primaryTitle: String {
        switch viewModel.step {
        case .credentials: "Continue"
        case .profile: "Create Account"
        case .activities:
            viewModel.remainingActivityCount > 0 ? "Pick \(viewModel.remainingActivityCount) more" : "Continue"
        case .calendar: isSkipping ? "Skip for Now" : "Continue"
        case .statusSources: "Finish"
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .credentials: CredentialsStep(viewModel: viewModel)
        case .profile: ProfileStep(viewModel: viewModel)
        case .activities: ActivitiesStep(viewModel: viewModel)
        case .calendar: CalendarStep(viewModel: viewModel)
        case .statusSources: StatusSourcesStep(viewModel: viewModel)
        }
    }
}

private extension RegistrationViewModel.Step {
    var title: String {
        switch self {
        case .credentials: "Create your account"
        case .profile: "What should friends call you?"
        case .activities: "What do you do all the time?"
        case .calendar: "Connect Google Calendar"
        case .statusSources: "How should your status update?"
        }
    }

    var subtitle: String {
        switch self {
        case .credentials: "Start with the email and password you'll sign in with."
        case .profile: "Your name shows next to your status. A nickname is optional."
        case .activities:
            "Pick at least \(RegistrationViewModel.requiredActivityCount). You'll choose from these whenever you set your status."
        case .calendar: "Optional. Let your calendar keep your status up to date."
        case .statusSources: "Choose any that fit. You can change this in Settings anytime."
        }
    }
}

// MARK: - Steps

private struct CredentialsStep: View {
    private enum Field { case email, password }

    @Bindable var viewModel: RegistrationViewModel
    @FocusState private var focusedField: Field?

    private var passwordIsLongEnough: Bool {
        viewModel.password.count >= RegistrationViewModel.minimumPasswordLength
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Email", text: $viewModel.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focusedField, equals: .email)
                .onSubmit { focusedField = .password }
                .brandField()
            SecureField("Password", text: $viewModel.password)
                .textContentType(.newPassword)
                .submitLabel(.done)
                .focused($focusedField, equals: .password)
                .brandField()
            Label("At least \(RegistrationViewModel.minimumPasswordLength) characters",
                  systemImage: passwordIsLongEnough ? "checkmark.circle.fill" : "circle")
                .font(.footnote.weight(.medium))
                .foregroundStyle(passwordIsLongEnough ? Color.brandAccent : Color.secondary)
                .animation(.snappy, value: passwordIsLongEnough)
        }
        .onAppear { focusedField = .email }
    }
}

private struct ProfileStep: View {
    private enum Field { case first, last, nickname }

    @Bindable var viewModel: RegistrationViewModel
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("First name", text: $viewModel.firstName)
                .textContentType(.givenName)
                .submitLabel(.next)
                .focused($focusedField, equals: .first)
                .onSubmit { focusedField = .last }
                .brandField()
            TextField("Last name", text: $viewModel.lastName)
                .textContentType(.familyName)
                .submitLabel(.next)
                .focused($focusedField, equals: .last)
                .onSubmit { focusedField = .nickname }
                .brandField()
            TextField("Nickname (optional)", text: $viewModel.nickname)
                .textContentType(.nickname)
                .submitLabel(.done)
                .focused($focusedField, equals: .nickname)
                .brandField()

            if !viewModel.firstName.isEmpty || !viewModel.lastName.isEmpty {
                HStack(spacing: 12) {
                    AvatarView(id: UUID(), firstName: viewModel.firstName, lastName: viewModel.lastName,
                               size: 44, usesBrandColors: true)
                    Text("Friends will see you as **\(viewModel.previewName)**")
                        .font(.subheadline)
                }
                .padding(.top, 8)
                .transition(.opacity)
            }
        }
        .animation(.snappy, value: viewModel.firstName.isEmpty && viewModel.lastName.isEmpty)
        .onAppear { focusedField = .first }
    }
}

private struct ActivitiesStep: View {
    @Bindable var viewModel: RegistrationViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            searchBar
            picked
            results
        }
    }

    /// Search on the left; the button on the right turns into "Add" when nothing matches.
    private var searchBar: some View {
        HStack(spacing: 8) {
            TextField("Search activities", text: $viewModel.query)
                .textInputAutocapitalization(.sentences)
                .submitLabel(viewModel.canAddSearchedActivity ? .done : .search)
                .focused($isSearchFocused)
                .onSubmit(addIfPossible)
            if viewModel.isAddingActivity {
                ProgressView()
                    .frame(width: 38, height: 38)
            } else if viewModel.canAddSearchedActivity {
                Button("Add", systemImage: "plus", action: addIfPossible)
                    .buttonStyle(.brand(.primary, compact: true))
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button {
                    isSearchFocused = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.semibold))
                        .frame(width: 38, height: 38)
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel("Search")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .insetBackground()
        .animation(.snappy, value: viewModel.canAddSearchedActivity)
    }

    private var picked: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your activities")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.selectedIds.count) of \(RegistrationViewModel.requiredActivityCount) picked")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(viewModel.remainingActivityCount == 0 ? Color.brandAccent : Color.secondary)
            }
            FlowLayout {
                ForEach(RegistrationViewModel.defaultActivityNames, id: \.self) { name in
                    ActivityTag(name: name, isLocked: true)
                }
                ForEach(viewModel.selectedActivities) { activity in
                    ActivityTag(name: activity.name) { viewModel.toggle(activity) }
                }
            }
            .animation(.snappy, value: viewModel.selectedIds)
            Text("“Do not disturb” and “Free” are always included.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var results: some View {
        if let error = viewModel.activitiesLoadError {
            VStack(alignment: .leading, spacing: 8) {
                InlineError(message: error)
                Button("Try Again") { Task { await viewModel.loadActivities() } }
                    .buttonStyle(.brand(.secondary, compact: true))
            }
        } else if !viewModel.hasLoadedActivities {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        } else if viewModel.searchResults.isEmpty, viewModel.trimmedQuery.isEmpty {
            noActivities
        } else if viewModel.searchResults.isEmpty {
            emptySearch
        } else {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.searchResults) { activity in
                    ActivityResultRow(activity: activity, isSelected: viewModel.isSelected(activity)) {
                        viewModel.toggle(activity)
                    }
                    if activity.id != viewModel.searchResults.last?.id {
                        Divider().padding(.leading, 58)
                    }
                }
            }
            .insetBackground()
        }
    }

    /// Nothing to pick from: the server has no standard activities (database not seeded).
    private var noActivities: some View {
        VStack(spacing: 6) {
            Text("No activities to pick from yet")
                .font(.subheadline.weight(.semibold))
            Text("Type one above and tap Add to make your own.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(20)
        .insetBackground()
    }

    private var emptySearch: some View {
        VStack(spacing: 6) {
            if viewModel.queryIsDefaultActivity {
                Text("“\(viewModel.trimmedQuery)” is already in your activities.")
                    .font(.subheadline.weight(.semibold))
            } else {
                Text("No “\(viewModel.trimmedQuery)” yet")
                    .font(.subheadline.weight(.semibold))
                Text("Tap Add to make it your own activity. Only you will have it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(20)
        .insetBackground()
    }

    private func addIfPossible() {
        guard viewModel.canAddSearchedActivity else { return }
        Task { await viewModel.addSearchedActivity() }
    }
}

private struct ActivityResultRow: View {
    let activity: ActivityChoice
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                ActivityIcon(activityName: activity.name, size: 34)
                Text(activity.name)
                    .font(.body.weight(.medium))
                if activity.isCustom {
                    Text("Yours")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.brandAccent : Color.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct CalendarStep: View {
    @Bindable var viewModel: RegistrationViewModel
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Benefit(systemImage: "calendar.badge.clock",
                        text: "When an event starts, it becomes your status, like “In a meeting”.")
                Benefit(systemImage: "eye.slash",
                        text: "Event titles stay private. Friends only see the activity.")
                Benefit(systemImage: "sun.max",
                        text: "All-day events and events marked Free are skipped.")
            }
            .padding(16)
            .insetBackground()

            connection
        }
    }

    @ViewBuilder
    private var connection: some View {
        switch viewModel.calendarState {
        case .notConnected:
            connectButton(title: "Connect Google Calendar")
        case .connecting:
            HStack(spacing: 10) {
                ProgressView()
                Text("Waiting for Google…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
        case .connected:
            Label("Google Calendar connected", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(Color.brandAccent)
                .frame(maxWidth: .infinity, minHeight: 54)
        case .failed(let message):
            VStack(spacing: 12) {
                InlineError(message: message)
                connectButton(title: "Try Again")
            }
        }
    }

    private func connectButton(title: String) -> some View {
        Button(action: connect) {
            Label(title, systemImage: "calendar")
        }
        .buttonStyle(.brand)
    }

    private func connect() {
        Task {
            guard let connection = await viewModel.startCalendarConnection() else { return }
            do {
                let callbackURL = try await webAuthenticationSession.authenticate(
                    using: connection.authURL, callbackURLScheme: connection.callbackScheme)
                viewModel.finishCalendarConnection(callbackURL: callbackURL)
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                viewModel.cancelCalendarConnection()
            } catch {
                viewModel.calendarConnectionFailed(error)
            }
        }
    }
}

private struct Benefit: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.brandAccent)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct StatusSourcesStep: View {
    @Bindable var viewModel: RegistrationViewModel

    var body: some View {
        VStack(spacing: 10) {
            ForEach(StatusSource.allCases) { source in
                StatusSourceRow(
                    source: source,
                    isOn: Binding(
                        get: { viewModel.statusSources.contains(source) },
                        set: { viewModel.setStatusSource(source, isOn: $0) }
                    ),
                    note: source == .calendar && viewModel.calendarState != .connected
                        ? "Needs Google Calendar. Go back a step to connect it."
                        : nil
                )
            }
        }
    }
}

// MARK: - Pieces

private struct StepProgress: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Color.brandAccent : Color.surfaceInset)
                    .frame(width: index == current ? 28 : 18, height: 6)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(total)")
    }
}

private struct CircleIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(Color.surfaceInset, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

#Preview {
    Color.appBackground
        .sheet(isPresented: .constant(true)) {
            RegistrationView(services: .mock(signedIn: false), onSignIn: {})
        }
        .environment(SessionViewModel(services: .mock(signedIn: false)))
}
