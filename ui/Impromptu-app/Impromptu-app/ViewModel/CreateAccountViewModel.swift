//
//  CreateAccountViewModel.swift
//  Impromptu-app
//

import Foundation
import Observation

@Observable
final class CreateAccountViewModel {
    static let minimumPasswordLength = 8

    var firstName = ""
    var lastName = ""
    var nickname = ""
    var email = ""
    var password = ""
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    var canSubmit: Bool {
        !isSubmitting
            && !trimmed(firstName).isEmpty && !trimmed(lastName).isEmpty
            && trimmed(email).contains("@")
            && password.count >= Self.minimumPasswordLength
    }

    func submit(to session: SessionViewModel) async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let nickname = trimmed(nickname)
        do {
            try await session.createAccount(CreateUserRequest(
                email: trimmed(email),
                password: password,
                firstName: trimmed(firstName),
                lastName: trimmed(lastName),
                nickname: nickname.isEmpty ? nil : nickname
            ))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
