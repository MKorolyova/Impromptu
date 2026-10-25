//
//  SignInView.swift
//  Impromptu-app
//

import SwiftUI

/// Bottom sheet for signing in with email and password.
struct SignInView: View {
    private enum Field { case email, password }

    /// Switches to the sign-up sheet.
    let onCreateAccount: () -> Void

    @Environment(SessionViewModel.self) private var session
    @State private var viewModel = LoginViewModel()
    @FocusState private var focusedField: Field?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SheetHeader(title: "Welcome back", subtitle: "Sign in to see what everyone's up to.")

                VStack(spacing: 12) {
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
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($focusedField, equals: .password)
                        .onSubmit(submit)
                        .brandField()
                }

                if let errorMessage = viewModel.errorMessage {
                    InlineError(message: errorMessage)
                }

                Button(action: submit) {
                    if viewModel.isSubmitting {
                        ProgressView()
                            .tint(Color.onBrandAccent)
                    } else {
                        Text("Sign In")
                    }
                }
                .buttonStyle(.brand)
                .disabled(!viewModel.canSubmit)

                HStack(spacing: 4) {
                    Text("New to \(Brand.appName)?")
                        .foregroundStyle(.secondary)
                    Button("Create an account", action: onCreateAccount)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.brandAccent)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium, .large])
        .brandSheet()
        .onAppear { focusedField = .email }
    }

    private func submit() {
        Task { await viewModel.submit(to: session) }
    }
}

#Preview {
    Color.appBackground
        .sheet(isPresented: .constant(true)) {
            SignInView(onCreateAccount: {})
        }
        .environment(SessionViewModel(services: .mock(signedIn: false)))
}
