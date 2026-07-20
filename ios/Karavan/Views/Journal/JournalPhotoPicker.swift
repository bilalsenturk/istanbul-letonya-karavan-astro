import Photos
import SwiftUI

// Fotoğraf seçici. Yolculuk penceresindeki KONUMLU fotoğraflar önde gelir —
// günlüğe eklenecek fotoğraf büyük ihtimalle yolda çekilmiş olandır.
struct JournalPhotoPicker: View {
    let onPick: ([Data]) -> Void

    @EnvironmentObject var store: TripStore
    @Environment(\.dismiss) private var dismiss

    @State private var assets: [PHAsset] = []
    @State private var selected: Set<String> = []
    @State private var status: PHAuthorizationStatus = .notDetermined
    @State private var isLoadingImages: Bool = false
    @State private var loadingTask: Task<Void, Never>? = nil

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if status == .denied || status == .restricted {
                    deniedState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(assets, id: \.localIdentifier) { asset in
                                thumb(asset)
                            }
                        }
                        .padding(4)
                    }
                }
            }
            .navigationTitle("Fotoğraf seç")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }.tint(Theme.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLoadingImages {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Yükleniyor...")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .tint(Theme.c2)
                    } else {
                        Button("Ekle (\(selected.count))") { pickSelected() }
                            .font(.system(size: 15, weight: .bold))
                            .tint(Theme.c2)
                            .disabled(selected.isEmpty)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
        .onDisappear {
            // View kapanırken devam eden Task'i iptal et — böylece onPick çağrılmaz.
            loadingTask?.cancel()
        }
    }

    private var deniedState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34)).foregroundStyle(Theme.muted)
            Text("Fotoğraflara erişim kapalı.\nAyarlar → Kuzey → Fotoğraflar'dan açabilirsin.")
                .font(.system(size: 14)).foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
        }
        .padding(30)
    }

    private func thumb(_ asset: PHAsset) -> some View {
        let isOn = selected.contains(asset.localIdentifier)
        return PhotoThumb(asset: asset)
            .aspectRatio(1, contentMode: .fill)
            .clipped()
            .overlay(alignment: .topTrailing) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(isOn ? Theme.c1 : .white.opacity(0.8))
                    .shadow(radius: 2)
                    .padding(5)
            }
            .onTapGesture {
                if isOn { selected.remove(asset.localIdentifier) }
                else { selected.insert(asset.localIdentifier) }
            }
    }

    private func load() async {
        let s = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        status = s
        guard s == .authorized || s == .limited else { return }

        let from = (store.trip?.departureDate ?? Date()).addingTimeInterval(-30 * 86400)
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@", from as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 400

        let result = PHAsset.fetchAssets(with: .image, options: options)
        var located: [PHAsset] = []
        var others: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            if asset.location != nil { located.append(asset) } else { others.append(asset) }
        }
        assets = located + others   // konumlu olanlar önde
    }

    private func pickSelected() {
        // Eğer yükleme zaten sürüyorsa, ikinci kez başlatmayı engelle.
        guard !isLoadingImages else { return }

        isLoadingImages = true

        let chosen = assets.filter { selected.contains($0.localIdentifier) }

        // Task'i @State'te tut — View kapanıp Task iptal olursa, onPick çağrılmayacak.
        let task = Task {
            var out: [Data] = []
            for asset in chosen {
                // Eğer Task iptal edildi ise hemen çık.
                if Task.isCancelled { return }
                if let data = await Self.jpeg(from: asset) { out.append(data) }
            }

            // Task iptal edilmemişse callback'i çağır.
            if !Task.isCancelled {
                onPick(out)
                dismiss()
            }

            isLoadingImages = false
        }

        loadingTask = task
    }

    /// Fotoğrafı makul boyutta JPEG'e indir — iCloud kotasını ve yüklemeyi hafifletir.
    private static func jpeg(from asset: PHAsset) async -> Data? {
        await withCheckedContinuation { cont in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 1600, height: 1600),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                cont.resume(returning: image?.jpegData(compressionQuality: 0.8))
            }
        }
    }
}

// Anlık çekim. Yolda görülen şeyi hemen günlüğe koyabilmek için —
// önce Fotoğraflar'a kaydedip sonra seçmek fazladan iki adım.
struct JournalCamera: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: JournalCamera
        init(_ parent: JournalCamera) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
