//
//  LoginViewModel.swift
//  Impromptu-app
//

import Foundation
import Observation

@Observable
final class LoginViewModel {
    var email = ""
    var password = ""
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSubmit: Bool {
        !isSubmitting && trimmedEmail.contains("@") && !password.isEmpty
    }

    func submit(to session: SessionViewModel) async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await session.logIn(email: trimmedEmail, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
