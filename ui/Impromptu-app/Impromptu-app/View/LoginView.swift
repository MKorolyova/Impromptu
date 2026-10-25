//
//  LoginView.swift
//  Impromptu-app
//

import SwiftUI

struct LoginView: View {
    private enum Field { case email, password }

    @Environment(SessionViewModel.self) private var session
    @State private var viewModel = LoginViewModel()
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $viewModel.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .email)
                        .onSubmit { focusedField = .password }
                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($focusedField, equals: .password)
                        .onSubmit(submit)
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(action: submit) {
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Log In")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(!viewModel.canSubmit)
                }

                Section {
                    NavigationLink("Create an Account") {
                        CreateAccountView()
                    }
                } footer: {
                    Text("New to Impromptu? Make an account to share what you're up to.")
                }
            }
            .navigationTitle("Impromptu")
        }
    }

    private func submit() {
        Task { await viewModel.submit(to: session) }
    }
}

#Preview {
    LoginView()
        .environment(SessionViewModel(services: .mock(signedIn: false)))
}
