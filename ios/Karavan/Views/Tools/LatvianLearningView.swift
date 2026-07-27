import SwiftUI

/// Araçlar sekmesinden Letonca kursuna giriş.
///
/// Kursun kendisi `LatvianHomeView`; burası yalnızca gezinme başlığını koyuyor.
struct LatvianLearningView: View {
    var body: some View {
        LatvianHomeView()
            .navigationTitle("Letonca")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
    }
}
