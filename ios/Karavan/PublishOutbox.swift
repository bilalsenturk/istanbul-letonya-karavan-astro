import Foundation
import UIKit

// Web'e POST edilen yükler için küçük giden kutusu: gönderimler sırayla yapılır,
// aynı uç için yalnızca EN YENİ yük bekletilir (latest-wins) ve başarısız yük
// diske yazılıp yeniden başlatmada / app öne gelince tekrar denenir.
@MainActor
final class PublishOutbox {
    static let shared = PublishOutbox()

    private struct PendingPost: Codable, Equatable {
        var url: String
        var body: Data
        var signature: String
    }

    private struct OutboxFile: Codable {
        var pending: [String: PendingPost] = [:]
        var lastSent: [String: String] = [:]   // anahtar -> son BAŞARILI imza
    }

    private var state = OutboxFile()
    private var sending: Set<String> = []
    private let fileURL: URL

    private init() {
        fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("publish-outbox.json")
        load()
        // Soğuk açılışta willEnterForeground TETİKLENMEZ; diskte yarım kalmış
        // yük varsa hemen boşalt.
        retryPending()
        // App öne gelince yarım kalan gönderimleri tekrar dene.
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.retryPending() }
        }
    }

    /// Aynı imza zaten başarıyla gönderildiyse atla; değilse sıraya al ve gönder.
    func enqueue(key: String, url: URL, body: Data, signature: String) {
        guard signature != state.lastSent[key],
              state.pending[key]?.signature != signature else { return }
        state.pending[key] = PendingPost(url: url.absoluteString, body: body, signature: signature)
        persist()
        Task { await drain(key: key) }
    }

    /// Diskte/bellekte bekleyen tüm yükleri tekrar göndermeyi dene.
    func retryPending() {
        for key in state.pending.keys {
            Task { await drain(key: key) }
        }
    }

    // MARK: - Sıralı gönderim

    /// Anahtar başına tek uçuş: gönderim sürerken gelen yeni yük, mevcut bittiğinde
    /// döngüde sıradaki olarak gönderilir (sıra bozulmaz, en yeni kazanır).
    private func drain(key: String) async {
        guard !sending.contains(key) else { return }
        sending.insert(key)
        defer { sending.remove(key) }

        while let post = state.pending[key], let url = URL(string: post.url) {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(Config.livePostSecret, forHTTPHeaderField: "x-live-secret")
            req.httpBody = post.body
            req.timeoutInterval = 10

            guard let (_, response) = try? await URLSession.shared.data(for: req),
                  let http = response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode)
            else { return }   // başarısız: sırada kalsın, sonra tekrar denenir

            // Uçuş sırasında daha yeni bir yük geldiyse onu ezmeden döngüye devam et.
            guard state.pending[key] == post else { continue }
            state.pending.removeValue(forKey: key)
            state.lastSent[key] = post.signature
            persist()
        }
    }

    // MARK: - Kalıcılık

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(OutboxFile.self, from: data)
        else { return }
        state = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
