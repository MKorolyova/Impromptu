//
//  WelcomeView.swift
//  Impromptu-app
//

import SwiftUI

/// The signed-out landing page: name, quote, and the way in.
struct WelcomeView: View {
    private enum Sheet: Identifiable {
        case signIn
        case signUp

        var id: Self { self }
    }

    @Environment(\.services) private var services
    @State private var sheet: Sheet?

    var body: some View {
        ZStack {
            BrandBackdrop()
            VStack(spacing: 0) {
                hero
                    .frame(maxHeight: .infinity)
                    // A little above center.
                    .offset(y: -36)
                Button("Get Started") { sheet = .signUp }
                    .buttonStyle(.brand)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
        }
        .safeAreaInset(edge: .top) {
            HStack(spacing: 10) {
                Spacer()
                Button("Sign In") { sheet = .signIn }
                    .buttonStyle(.brand(.secondary, compact: true))
                Button("Sign Up") { sheet = .signUp }
                    .buttonStyle(.brand(.primary, compact: true))
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .signIn:
                SignInView { self.sheet = .signUp }
            case .signUp:
                RegistrationView(services: services) { self.sheet = .signIn }
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 20) {
            Image(.logo)
                .resizable()
                .scaledToFit()
                // The artwork has empty space around the bubbles, so the frame is larger than they look.
                .frame(width: 150, height: 150)
                .padding(.bottom, -24)
                .accessibilityHidden(true)
            Text(Brand.appName)
                .font(.system(size: 52, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("“Real connections happen when you least expect them.”")
                .font(.system(.title3, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WelcomeView()
        .environment(SessionViewModel(services: .mock(signedIn: false)))
}
