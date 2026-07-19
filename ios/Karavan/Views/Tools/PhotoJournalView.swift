import SwiftUI
import Photos
import MapKit

// Otomatik foto günlüğü: yolculuk penceresinde çekilen KONUMLU fotoğraflar
// rota haritasına iğnelenir + tarih sırasıyla galeri. Sıfır etiketleme.
struct PhotoJournalView: View {
    @EnvironmentObject var store: TripStore
    @State private var assets: [PHAsset] = []
    @State private var status: PHAuthorizationStatus = .notDetermined

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 6)]

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !assets.isEmpty {
                        journalMap
                            .frame(height: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        MonoLabel(text: "\(assets.count) konumlu fotoğraf", color: Theme.c4)
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(assets, id: \.localIdentifier) { asset in
                                PhotoThumb(asset: asset)
                                    .aspectRatio(1, contentMode: .fill)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    } else {
                        emptyState
                    }
                }
                .padding(14)
            }
        }
        .navigationTitle("Foto Günlüğü")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .preferredColorScheme(.dark)
    }

    private var journalMap: some View {
        Map(initialPosition: .automatic) {
            ForEach(assets.prefix(150), id: \.localIdentifier) { asset in
                if let loc = asset.location {
                    Annotation("", coordinate: loc.coordinate) {
                        PhotoThumb(asset: asset)
                            .frame(width: 34, height: 34)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
                            .shadow(radius: 2)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.stack").font(.system(size: 36)).foregroundStyle(Theme.muted)
            Text(status == .denied
                 ? "Fotoğraf izni verilmedi. Ayarlar'dan açabilirsin."
                 : "Henüz konumlu yol fotoğrafı yok.\nYolda çektiklerin otomatik burada haritaya iğnelenir.")
                .font(.system(size: 14)).foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func load() async {
        let s = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        status = s
        guard s == .authorized || s == .limited else { return }

        // Pencere: kalkıştan 30 gün önce → bugün (kalkış yoksa son 60 gün)
        let from = (store.trip?.departureDate ?? Date()).addingTimeInterval(-30 * 86400)
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@", from as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 400

        let result = PHAsset.fetchAssets(with: .image, options: options)
        var found: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            if asset.location != nil { found.append(asset) }
        }
        assets = found
    }
}

// Fotoğraf küçük resmi (PhotoKit'ten async yüklenir, önbellekli).
struct PhotoThumb: View {
    let asset: PHAsset
    @State private var image: UIImage?

    private static let manager = PHCachingImageManager()

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Theme.panel
                ProgressView().tint(Theme.muted).scaleEffect(0.7)
            }
        }
        .onAppear {
            guard image == nil else { return }
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .opportunistic
            opts.isNetworkAccessAllowed = true
            Self.manager.requestImage(for: asset,
                                      targetSize: CGSize(width: 240, height: 240),
                                      contentMode: .aspectFill,
                                      options: opts) { img, _ in
                if let img { image = img }
            }
        }
    }
}
