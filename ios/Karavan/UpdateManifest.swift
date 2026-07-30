import Foundation

struct UpdateManifest: Decodable, Equatable {
    let latestBuild: Int
    let minBuild: Int
    let testflightURL: String?
}
