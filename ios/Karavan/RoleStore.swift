import SwiftUI

// Cihaz rolü: bu telefonu SÜRÜCÜ mü YOLCU mu kullanıyor? Hesap yok — rol
// cihaza kaydedilir. Gün/kamp planı her cihazdan düzenlenir; kalkış tarihini
// değiştirmek ve navigasyonu başlatmak yalnızca sürücünün cihazına aittir.
@MainActor
final class RoleStore: ObservableObject {
    /// Tek örnek: arayüz (environmentObject) ve LegLauncher kilidi aynı depoyu kullanır.
    static let shared = RoleStore()

    /// Kullanıcı rolü değiştirince seçim "yapıldı" sayılır — ilk açılış
    /// sorusu (RolePrompt) bir daha gösterilmez.
    @Published var isDriver: Bool {
        didSet {
            let d = UserDefaults.standard
            d.set(isDriver, forKey: Self.driverKey)
            d.set(true, forKey: Self.chosenKey)
            hasChosenRole = true
        }
    }

    /// Rol hiç seçildi mi? False ise ilk açılışta soru gösterilir.
    @Published private(set) var hasChosenRole: Bool

    // App Group'a DEĞİL, standart defaults'a yazılır: rol cihaz başınadır,
    // widget/uzantı üzerinden başka bir bağlama sızmasın.
    private static let driverKey = "device-role-is-driver"
    private static let chosenKey = "device-role-chosen"

    private init() {
        let d = UserDefaults.standard
        if d.object(forKey: Self.chosenKey) != nil {
            // Rol daha önce açıkça seçilmiş.
            hasChosenRole = true
            isDriver = d.bool(forKey: Self.driverKey)
        } else if d.object(forKey: TripPlanStore.ownerKey) != nil {
            // Önceki kurulumdan gelen cihaz: planı yöneten telefon büyük
            // olasılıkla sürücününki — rolü ondan tohumla, soru sorma.
            hasChosenRole = true
            isDriver = d.bool(forKey: TripPlanStore.ownerKey)
            // init'te didSet ÇALIŞMAZ: tohumu elle kalıcı yap. Yoksa sahiplik
            // başka cihaza geçince bir sonraki açılışta rol sessizce yolcuya döner.
            d.set(isDriver, forKey: Self.driverKey)
            d.set(true, forKey: Self.chosenKey)
        } else {
            // Gerçekten yeni kurulum: soru gösterilecek.
            hasChosenRole = false
            isDriver = false
        }
    }
}

// İlk açılışta bir kez sorulur: "Bu cihazı kim kullanıyor?"
// Görsel dil DepartureModal ile aynı (panel + köşe + sıcak degrade düğme).
struct RolePrompt: View {
    @EnvironmentObject var role: RoleStore

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.gradWarm).frame(width: 72, height: 72)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text("Kurulum")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.c1)
                Text("Bu cihazı kim kullanıyor?")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                Text("Kalkış tarihi ve navigasyon başlatma sürücünün; gün ve kamp planı herkesin.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button { role.isDriver = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "steeringwheel").font(.system(size: 15, weight: .bold))
                        Text("Sürücü (kaptan)").font(.system(size: 16, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.gradWarm, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)

                Button { role.isDriver = false } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill").font(.system(size: 14, weight: .bold))
                        Text("Yolcu").font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .padding(.horizontal, 26)
        .presentationDetents([.height(430)])
        .presentationBackground(.clear)
    }
}
