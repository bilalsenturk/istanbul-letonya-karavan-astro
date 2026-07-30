import Foundation

@main
struct UpdateManifestCheck {
    static func main() throws {
        let decoder = JSONDecoder()
        let withoutURL = try decoder.decode(
            UpdateManifest.self,
            from: Data(#"{"latestBuild":19,"minBuild":18}"#.utf8)
        )
        guard withoutURL.latestBuild == 19,
              withoutURL.minBuild == 18,
              withoutURL.testflightURL == nil else {
            fatalError("URL'siz manifest build bilgisini korumalı")
        }

        let withURL = try decoder.decode(
            UpdateManifest.self,
            from: Data(#"{"latestBuild":19,"minBuild":18,"testflightURL":"https://testflight.apple.com"}"#.utf8)
        )
        guard withURL.testflightURL == "https://testflight.apple.com" else {
            fatalError("TestFlight bağlantısı çözümlenmeli")
        }
    }
}
