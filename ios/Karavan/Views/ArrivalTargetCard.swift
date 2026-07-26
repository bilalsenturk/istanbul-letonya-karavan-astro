import SwiftUI

struct ArrivalTargetCard: View {
    let target: ArrivalTarget?
    let isRestDay: Bool
    let canStart: Bool
    let actionText: String
    let onChoose: () -> Void
    let onEdit: () -> Void
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: target?.kind.symbol ?? "mappin.slash.circle.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(target == nil ? Theme.warn : Theme.c2)
                    .frame(width: 38, height: 38)
                    .background((target == nil ? Theme.warn : Theme.c2).opacity(0.13), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kesin varış noktası")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                    Text(target?.name ?? (isRestDay ? "Bu gün için gerekmiyor" : "Varış yeri gerekli"))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    if let address = target?.formattedAddress, !address.isEmpty {
                        Text(address).font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(3)
                    } else if !isRestDay {
                        Text("Kamp, otel veya tam adres seçmeden rota başlayamaz.")
                            .font(.system(size: 12)).foregroundStyle(Theme.warn)
                    }
                }
                Spacer()
                if target != nil {
                    Button(action: onEdit) { Image(systemName: "ellipsis.circle") }
                        .font(.system(size: 20)).foregroundStyle(Theme.muted)
                        .accessibilityLabel("Varış ayrıntılarını düzenle")
                }
            }

            if !isRestDay {
                if target == nil {
                    Button(action: onChoose) {
                        Label("Varış yerini seç", systemImage: "map.fill")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity).frame(height: 46)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.c2)
                } else {
                    Button(action: onStart) {
                        Label(actionText, systemImage: canStart ? "arrow.triangle.turn.up.right.circle.fill" : "lock.fill")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity).frame(height: 46)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(canStart ? Theme.c2 : Theme.muted)
                    .disabled(!canStart)
                }
            }
        }
        .card()
    }
}
