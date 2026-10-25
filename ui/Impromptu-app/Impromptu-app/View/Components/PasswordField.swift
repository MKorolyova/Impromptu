//
//  PasswordField.swift
//  Impromptu-app
//

import SwiftUI
import UIKit

/// A `SecureField` whose dots stay readable after AutoFill. When iOS fills in a password it turns the
/// text black for its yellow highlight, and in dark mode it doesn't always turn it back, leaving black
/// dots on a dark field. Re-applying the text color doesn't reliably undo that, so once AutoFill is
/// done with the field (it no longer has focus) it's replaced by a fresh one, which draws normally.
struct PasswordField<Field: Hashable>: View {
    let title: String
    @Binding var text: String
    /// `.password` to sign in, `.newPassword` to be offered a strong password.
    var contentType: UITextContentType = .password
    let focus: FocusState<Field?>.Binding
    /// This field's value in `focus`.
    let field: Field

    /// The whole password arrived at once, as AutoFill does it.
    @State private var wasFilled = false
    /// Changing it replaces the text field with a fresh one.
    @State private var generation = 0

    private var isFocused: Bool {
        focus.wrappedValue == field
    }

    var body: some View {
        SecureField(title, text: $text)
            .textContentType(contentType)
            .focused(focus, equals: field)
            .id(generation)
            .onChange(of: text) { old, new in
                if new.count - old.count > 1 { wasFilled = true }
            }
            // AutoFill can fill this field while another one has focus, or while this one does; either
            // way, wait until it isn't in use so the swap never interrupts typing or a suggestion.
            .task(id: wasFilled && !isFocused) {
                guard wasFilled, !isFocused else { return }
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                wasFilled = false
                generation += 1
            }
    }
}
