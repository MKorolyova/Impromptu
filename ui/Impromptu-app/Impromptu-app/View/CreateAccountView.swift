//
//  CreateAccountView.swift
//  Impromptu-app
//

import SwiftUI

struct CreateAccountView: View {
    @Environment(SessionViewModel.self) private var session
    @State private var viewModel = CreateAccountViewModel()

    var body: some View {
        Form {
            Section {
                TextField("First name", text: $viewModel.firstName)
                    .textContentType(.givenName)
                TextField("Last name", text: $viewModel.lastName)
                    .textContentType(.familyName)
                TextField("Nickname (optional)", text: $viewModel.nickname)
                    .textContentType(.nickname)
            }

            Section {
                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $viewModel.password)
                    .textContentType(.newPassword)
            } footer: {
                Text("At least \(CreateAccountViewModel.minimumPasswordLength) characters.")
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await viewModel.submit(to: session) }
                } label: {
                    if viewModel.isSubmitting {
                        ProgressView()
                    } else {
                        Text("Create Account")
                    }
                }
                .frame(maxWidth: .infinity)
                .disabled(!viewModel.canSubmit)
            }
        }
        .navigationTitle("Create Account")
    }
}

#Preview {
    NavigationStack {
        CreateAccountView()
    }
    .environment(SessionViewModel(services: .mock(signedIn: false)))
}
