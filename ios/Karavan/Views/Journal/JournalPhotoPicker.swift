import SwiftUI

// Task 5'te gerçek seçici ile değiştirilecek.
struct JournalPhotoPicker: View {
    let onPick: ([Data]) -> Void
    var body: some View { Color.clear.onAppear { onPick([]) } }
}
