import Foundation
import SwiftUI

// Cihaz-ÖNCE depo: her kayıt önce diske yazılır, sonra buluta gönderilir.
// Yolculuğun büyük kısmı sinyalin zayıf olduğu sınır bölgelerinden geçiyor;
// buluta yazamamak kaydı kaybetmek anlamına gelmemeli.
@MainActor
final class JournalStore: ObservableObject {
    @Published private(set) var entries: [JournalEntry] = []
    @Published private(set) var pendingCount = 0
    @Published private(set) var cloudAvailable = true
    /// Kullanıcıya gösterilecek bulut sorunu. Sessizce yutulmamalı:
    /// kota dolduğunda kayıtlar cihazda birikir ve kimse fark etmez.
    @Published private(set) var cloudProblem: String?

    private var queue = JournalQueue()

    private var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("journal", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private var entriesFile: URL { dir.appendingPathComponent("entries.json") }
    private var queueFile: URL { dir.appendingPathComponent("queue.json") }

    init() {
        load()
    }

    // MARK: - Okuma / yazma

    private func load() {
        if let data = try? Data(contentsOf: entriesFile),
           let decoded = try? JSONDecoder().decode([JournalEntry].self, from: data) {
            entries = decoded.sorted { $0.createdAt > $1.createdAt }
        }
        if let data = try? Data(contentsOf: queueFile),
           let decoded = try? JSONDecoder().decode(JournalQueue.self, from: data) {
            queue = decoded
        }
        pendingCount = queue.pendingCount
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: entriesFile, options: .atomic)
        }
        if let data = try? JSONEncoder().encode(queue) {
            try? data.write(to: queueFile, options: .atomic)
        }
        pendingCount = queue.pendingCount
    }

    func photoURL(_ filename: String) -> URL {
        dir.appendingPathComponent(filename)
    }

    // MARK: - Düzenleme

    @discardableResult
    func add(_ entry: JournalEntry, photos: [Data]) -> JournalEntry {
        var saved = entry
        var names: [String] = []
        for (i, data) in photos.enumerated() {
            let name = "\(entry.id)-\(i).jpg"
            try? data.write(to: photoURL(name), options: .atomic)
            names.append(name)
        }
        saved.photoFilenames = names

        entries.insert(saved, at: 0)
        queue.enqueue(saved.id)
        persist()
        Task { await drainQueue() }
        return saved
    }

    func delete(_ entry: JournalEntry) {
        entries.removeAll { $0.id == entry.id }
        for name in entry.photoFilenames {
            try? FileManager.default.removeItem(at: photoURL(name))
        }
        queue.markSynced(entry.id)   // kuyruktan da düşür
        persist()
        Task { try? await JournalCloud.shared.delete(id: entry.id) }
    }

    func setShared(_ entry: JournalEntry, shared: Bool) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[i].isShared = shared
        queue.enqueue(entry.id)
        persist()
        Task { await drainQueue() }
    }

    // MARK: - Kuyruk boşaltma

    func drainQueue() async {
        cloudAvailable = await JournalCloud.shared.accountAvailable()
        guard cloudAvailable else {
            cloudProblem = "iCloud oturumu kapalı — kayıtların yalnızca bu cihazda."
            return
        }
        cloudProblem = nil

        while let id = queue.nextToSend(now: Date()) {
            guard let entry = entries.first(where: { $0.id == id }) else {
                queue.markSynced(id)
                continue
            }
            queue.markSyncing(id, now: Date())
            persist()

            let urls = entry.photoFilenames.map { photoURL($0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }

            do {
                try await JournalCloud.shared.save(entry, photoURLs: urls)
                queue.markSynced(id)
            } catch JournalCloudError.quotaExceeded {
                cloudProblem = "iCloud depolaman dolu — kayıtlar cihazda bekliyor."
                queue.markFailed(id, now: Date())
                persist()
                return
            } catch JournalCloudError.accountUnavailable {
                // Döngü başında uygunmuş gibi görünüp arada kapanmış olabilir
                // (hesaptan çıkış, kısıtlama vb.) — durumu da kullanıcı mesajını
                // da güncel tut, aksi halde arayüz "bulut var" der ama hiç
                // gönderemez.
                cloudAvailable = false
                cloudProblem = "iCloud oturumu kapalı — kayıtların yalnızca bu cihazda."
                queue.markFailed(id, now: Date())
                persist()
                return
            } catch {
                // network / notFound / unexpected — hepsi geçici veya tek
                // kayıtlık sorunlar sayılır; kuyrukta bekletip bir sonraki
                // tetiklemede (uygulama öne gelince, ağ dönünce) tekrar denenir.
                queue.markFailed(id, now: Date())
                persist()
                return   // bir sonraki tetiklemede devam et
            }
            persist()
        }
    }
}
