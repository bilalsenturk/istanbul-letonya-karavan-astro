import Foundation

enum SyncState: String, Codable {
    case pending, syncing, synced, failed
}

struct QueueItem: Codable, Equatable {
    let entryId: String
    var state: SyncState
    var attempts: Int
    var lastAttemptAt: Date?
}

// Gönderim kuyruğu — SAF durum makinesi. Ağ veya CloudKit bilmez;
// yalnızca hangi kaydın ne zaman denenebileceğini bilir. Bu ayrım
// kuyruğun cihazsız test edilebilmesini sağlar.
struct JournalQueue: Codable, Equatable {
    private(set) var items: [QueueItem] = []

    static let maxAttempts = 5

    /// Artan geri çekilme: 30 sn, 2 dk, 8 dk, 32 dk, 2 saat.
    /// Sinyalsiz sınır bölgesinde saniyede bir denemek pil yakar.
    static func backoff(attempts: Int) -> TimeInterval {
        30 * pow(4, Double(max(0, attempts - 1)))
    }

    mutating func enqueue(_ entryId: String) {
        guard !items.contains(where: { $0.entryId == entryId }) else { return }
        items.append(QueueItem(entryId: entryId, state: .pending, attempts: 0, lastAttemptAt: nil))
    }

    mutating func markSyncing(_ entryId: String, now: Date) {
        update(entryId) { $0.state = .syncing; $0.lastAttemptAt = now }
    }

    mutating func markSynced(_ entryId: String) {
        items.removeAll { $0.entryId == entryId }
    }

    mutating func markFailed(_ entryId: String, now: Date) {
        update(entryId) {
            $0.attempts += 1
            $0.lastAttemptAt = now
            $0.state = $0.attempts >= Self.maxAttempts ? .failed : .pending
        }
    }

    /// Şu an gönderilebilecek ilk kayıt. Gönderim sırasındakiler, vazgeçilenler
    /// ve geri çekilme süresi dolmayanlar atlanır.
    func nextToSend(now: Date) -> String? {
        items.first { item in
            guard item.state == .pending else { return false }
            guard item.attempts > 0, let last = item.lastAttemptAt else { return true }
            return now.timeIntervalSince(last) >= Self.backoff(attempts: item.attempts)
        }?.entryId
    }

    var pendingCount: Int {
        items.filter { $0.state != .failed }.count
    }

    private mutating func update(_ entryId: String, _ mutate: (inout QueueItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.entryId == entryId }) else { return }
        mutate(&items[i])
    }
}
