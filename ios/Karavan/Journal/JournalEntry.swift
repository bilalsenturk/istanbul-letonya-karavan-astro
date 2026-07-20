import Foundation

// Günlük kaydı. Cihazda JSON olarak saklanır, CloudKit özel veritabanına
// kuyruktan gönderilir. Fotoğraflar ayrı dosyalar; burada yalnızca adları durur.
struct JournalEntry: Codable, Identifiable, Equatable {
    let id: String
    var text: String
    var createdAt: Date
    var latitude: Double?
    var longitude: Double?
    var stopId: String?
    var mood: String?
    var photoFilenames: [String]
    /// Varsayılan GİZLİ. Paylaşmak bilinçli bir eylem olmalı —
    /// sonradan gizliye almak zor, baştan gizli olmak kolay.
    var isShared: Bool

    init(id: String = UUID().uuidString,
         text: String,
         createdAt: Date = Date(),
         latitude: Double? = nil,
         longitude: Double? = nil,
         stopId: String? = nil,
         mood: String? = nil,
         photoFilenames: [String] = [],
         isShared: Bool = false) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.latitude = latitude
        self.longitude = longitude
        self.stopId = stopId
        self.mood = mood
        self.photoFilenames = photoFilenames
        self.isShared = isShared
    }
}
