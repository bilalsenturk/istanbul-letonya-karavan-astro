import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var account: AccountSessionStore

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "location.north.circle.fill")
                        .font(.system(size: 54, weight: .medium))
                        .foregroundStyle(Theme.c2)
                    Text("KUZEY")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text("Rotalarınıza ve paylaşılan yolculuklara erişin.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                VStack(spacing: 12) {
                    SignInWithAppleButton(.continue) { request in
                        account.configureAppleRequest(request)
                    } onCompletion: { result in
                        Task { await account.completeAppleAuthorization(result) }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .disabled(account.isSigningIn)
                    .accessibilityLabel("Apple ile giriş yap")

                    if account.isSigningIn {
                        ProgressView().tint(Theme.c2)
                    } else if let message = account.errorMessage {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.warn)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
        }
    }
}
