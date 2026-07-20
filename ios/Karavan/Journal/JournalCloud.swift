import CloudKit
import Foundation

enum JournalCloudError: Error {
    case accountUnavailable
    case quotaExceeded
    case network
}

// CloudKit ÖZEL veritabanı — kayıtlar yalnızca sahibinin iCloud hesabında.
// Paylaşım burada YOK: paylaşılan kayıtlar ayrı bir yoldan (Vercel aynası) gider.
actor JournalCloud {
    static let shared = JournalCloud()

    private let container = CKContainer(identifier: "iCloud.com.bilalsenturk.kuzey")
    private var db: CKDatabase { container.privateCloudDatabase }

    private static let recordType = "JournalEntry"

    func accountAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    func save(_ entry: JournalEntry, photoURLs: [URL]) async throws {
        guard await accountAvailable() else { throw JournalCloudError.accountUnavailable }

        let record = CKRecord(recordType: Self.recordType,
                              recordID: CKRecord.ID(recordName: entry.id))
        record["text"] = entry.text as NSString
        record["createdAt"] = entry.createdAt as NSDate
        record["isShared"] = (entry.isShared ? 1 : 0) as NSNumber
        if let lat = entry.latitude { record["latitude"] = lat as NSNumber }
        if let lng = entry.longitude { record["longitude"] = lng as NSNumber }
        if let stopId = entry.stopId { record["stopId"] = stopId as NSString }
        if let mood = entry.mood { record["mood"] = mood as NSString }
        if !photoURLs.isEmpty {
            record["photos"] = photoURLs.map { CKAsset(fileURL: $0) }
        }

        do {
            _ = try await db.save(record)
        } catch let error as CKError {
            throw Self.mapError(error)
        }
    }

    func fetchAll() async throws -> [JournalEntry] {
        guard await accountAvailable() else { throw JournalCloudError.accountUnavailable }

        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        do {
            let (results, _) = try await db.records(matching: query)
            return results.compactMap { _, result in
                guard let record = try? result.get() else { return nil }
                return Self.entry(from: record)
            }
        } catch let error as CKError {
            throw Self.mapError(error)
        }
    }

    func delete(id: String) async throws {
        // save/fetchAll ile aynı hesap ve hata sözleşmesi: silme de sessizce
        // yarım kalmamalı — çağıran taraf her zaman aynı üç hatayı bekleyebilmeli.
        guard await accountAvailable() else { throw JournalCloudError.accountUnavailable }

        do {
            _ = try await db.deleteRecord(withID: CKRecord.ID(recordName: id))
        } catch let error as CKError {
            throw Self.mapError(error)
        }
    }

    private static func mapError(_ error: CKError) -> Error {
        switch error.code {
        case .quotaExceeded: return JournalCloudError.quotaExceeded
        case .networkUnavailable, .networkFailure: return JournalCloudError.network
        case .notAuthenticated: return JournalCloudError.accountUnavailable
        default: return error
        }
    }

    private static func entry(from record: CKRecord) -> JournalEntry? {
        guard let text = record["text"] as? String,
              let createdAt = record["createdAt"] as? Date else { return nil }
        let assets = record["photos"] as? [CKAsset] ?? []
        return JournalEntry(
            id: record.recordID.recordName,
            text: text,
            createdAt: createdAt,
            latitude: record["latitude"] as? Double,
            longitude: record["longitude"] as? Double,
            stopId: record["stopId"] as? String,
            mood: record["mood"] as? String,
            photoFilenames: assets.compactMap { $0.fileURL?.lastPathComponent },
            isShared: (record["isShared"] as? Int ?? 0) == 1
        )
    }
}
