import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Public trip payloads are retried in order. The persisted record deliberately
/// contains no request URL, header, token, or other credential material.
@MainActor
final class PublishOutbox {
    static let shared = PublishOutbox()

    private struct PendingPost: Codable, Equatable {
        let tripID: String
        let resourcePath: String
        let body: Data
    }

    private struct OutboxFile: Codable {
        var pending: [String: PendingPost] = [:]
    }

    private var state = OutboxFile()
    private var sending: Set<String> = []
    private var scope: PublishedTripScope?
    private let fileURL: URL
    private let sender: PublishedTripSending

    init(
        fileURL: URL? = nil,
        sender: PublishedTripSending? = nil,
        observeLifecycle: Bool = true
    ) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("publish-outbox.json")
        self.sender = sender ?? PublishedTripClient.shared
        load()
#if canImport(UIKit)
        if observeLifecycle {
            NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.retryPending() }
            }
        }
#endif
    }

    /// A nil scope pauses work but preserves queued public payloads. Re-enabling
    /// a scope drains records only for that selected trip.
    func setScope(_ scope: PublishedTripScope?) {
        self.scope = scope
        if scope != nil { retryPending() }
    }

    func enqueue(resource: PublishedTripResource, body: Data) {
        guard let scope else { return }
        let key = "\(scope.tripID):\(resource.rawValue)"
        state.pending[key] = PendingPost(tripID: scope.tripID, resourcePath: resource.rawValue, body: body)
        persist()
        Task { await drain(key: key) }
    }

    func retryPending() {
        guard let scope else { return }
        for (key, post) in state.pending where post.tripID == scope.tripID {
            Task { await drain(key: key) }
        }
    }

    var persistedKeys: [String] { state.pending.keys.sorted() }
    var persistedJSON: String {
        guard let data = try? JSONEncoder().encode(state) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private func drain(key: String) async {
        guard !sending.contains(key) else { return }
        sending.insert(key)
        defer { sending.remove(key) }

        while let activeScope = scope,
              let post = state.pending[key],
              post.tripID == activeScope.tripID {
            guard let resource = PublishedTripResource(rawValue: post.resourcePath) else {
                state.pending.removeValue(forKey: key)
                persist()
                continue
            }
            do {
                try await sender.put(scope: activeScope, resource: resource, body: post.body)
            } catch {
                return
            }
            guard state.pending[key] == post else { continue }
            state.pending.removeValue(forKey: key)
            persist()
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONDecoder().decode(OutboxFile.self, from: data) else {
            // The former format carried a URL and a shared-secret signature.
            // Do not retain that credential-bearing file after migration.
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        state = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
