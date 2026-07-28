import SwiftUI
import VisionKit
import QuickLook
import LocalAuthentication
import UniformTypeIdentifiers

// Face ID'li belge kasası: pasaport/sigorta/ruhsat taranır ya da içe aktarılır;
// dosyalar tam dosya korumasıyla (cihaz kilitliyken şifreli) saklanır.
@MainActor
final class VaultStore: ObservableObject {
    @Published private(set) var files: [URL] = []

    private var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kasa", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.complete])
        return d
    }

    func refresh() {
        files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func save(data: Data, name: String) -> Bool {
        var url = dir.appendingPathComponent(name)
        // Aynı adlı dosya varsa (ör. aynı saniyede iki tarama) ezme — benzersiz ek koy.
        if FileManager.default.fileExists(atPath: url.path) {
            let base = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            let unique = "\(base)-\(UUID().uuidString.prefix(4))"
            url = url.deletingLastPathComponent()
                .appendingPathComponent(ext.isEmpty ? unique : "\(unique).\(ext)")
        }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            refresh()
            return true
        } catch {
            return false
        }
    }

    func delete(at offsets: IndexSet) {
        for i in offsets { try? FileManager.default.removeItem(at: files[i]) }
        refresh()
    }
}

struct DocumentVaultView: View {
    @StateObject private var store = VaultStore()
    @State private var unlocked = false
    @State private var authFailed = false
    @State private var showScanner = false
    @State private var showImporter = false
    @State private var previewURL: URL?
    @State private var saveFailed = false
    @State private var pendingSaveFailed = false   // tarama sheet'i kapanmadan alert isteme — arkada düşer

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if unlocked {
                fileList
            } else {
                lockScreen
            }
        }
        .navigationTitle("Belge Kasası")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if unlocked {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if VNDocumentCameraViewController.isSupported {
                            Button { showScanner = true } label: { Label("Kamerayla tara", systemImage: "doc.viewfinder") }
                        }
                        Button { showImporter = true } label: { Label("Dosyadan aktar", systemImage: "folder") }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 21))
                    }
                    .tint(Theme.c2)
                }
            }
        }
        .sheet(isPresented: $showScanner, onDismiss: {
            // Hata uyarısını sheet TAM KAPANDIKTAN sonra göster — kapanış
            // sürerken istenen alert sessizce düşer (masraf akışıyla aynı desen).
            if pendingSaveFailed { pendingSaveFailed = false; saveFailed = true }
        }) {
            DocScanRepresentable { pdfData in
                pendingSaveFailed = !store.save(data: pdfData, name: "Belge-\(Self.stamp()).pdf")
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.pdf, .image],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let src = urls.first else { return }
            let access = src.startAccessingSecurityScopedResource()
            defer { if access { src.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: src) {
                saveFailed = !store.save(data: data, name: src.lastPathComponent)
            } else {
                saveFailed = true   // dosya okunamadı — sessizce yutma
            }
        }
        .alert("Belge kaydedilemedi", isPresented: $saveFailed) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text("Dosya kasaya yazılamadı. Tekrar dene.")
        }
        .quickLookPreview($previewURL)
        .preferredColorScheme(.dark)
    }

    private var lockScreen: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill").font(.system(size: 44)).foregroundStyle(Theme.c4)
            Text("Pasaport, sigorta, ruhsat…\nYalnızca Face ID ile açılır.")
                .font(.system(size: 14)).foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
            Button {
                unlock()
            } label: {
                Label("Face ID ile aç", systemImage: "faceid")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26).padding(.vertical, 13)
                    .background(Theme.gradCool, in: Capsule())
            }
            .buttonStyle(.plain)
            if authFailed {
                Text("Doğrulama başarısız. Tekrar dene.")
                    .font(.system(size: 13)).foregroundStyle(Theme.bad)
            }
        }
        .padding(24)
    }

    private var fileList: some View {
        Group {
            if store.files.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.on.doc").font(.system(size: 36)).foregroundStyle(Theme.muted)
                    Text("Kasa boş. Sağ üstten belge tara ya da aktar.")
                        .font(.system(size: 14)).foregroundStyle(Theme.dim)
                }
            } else {
                List {
                    ForEach(store.files, id: \.self) { url in
                        Button { previewURL = url } label: {
                            HStack(spacing: 12) {
                                Image(systemName: url.pathExtension.lowercased() == "pdf" ? "doc.fill" : "photo.fill")
                                    .font(.system(size: 17)).foregroundStyle(Theme.c3)
                                Text(url.lastPathComponent)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "eye.fill").font(.system(size: 13)).foregroundStyle(Theme.muted)
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { store.delete(at: $0) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .onAppear { store.refresh() }
    }

    private func unlock() {
        let context = LAContext()
        context.localizedFallbackTitle = "Parola kullan"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            unlocked = true   // kilit kurulmamış cihazda engelleme (kasa yine dosya korumalı)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: "Belge kasasını aç") { ok, _ in
            DispatchQueue.main.async {
                unlocked = ok
                authFailed = !ok
            }
        }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}

// MARK: - Belge tarama → PDF

private struct DocScanRepresentable: UIViewControllerRepresentable {
    let onPDF: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPDF: onPDF, dismiss: { dismiss() }) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onPDF: (Data) -> Void
        let dismiss: () -> Void
        init(onPDF: @escaping (Data) -> Void, dismiss: @escaping () -> Void) {
            self.onPDF = onPDF
            self.dismiss = dismiss
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            let renderer = UIGraphicsPDFRenderer(bounds: .zero)
            let data = renderer.pdfData { ctx in
                for i in 0 ..< scan.pageCount {
                    let img = scan.imageOfPage(at: i)
                    let bounds = CGRect(origin: .zero, size: img.size)
                    ctx.beginPage(withBounds: bounds, pageInfo: [:])
                    img.draw(in: bounds)
                }
            }
            onPDF(data)
            dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { dismiss() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) { dismiss() }
    }
}
