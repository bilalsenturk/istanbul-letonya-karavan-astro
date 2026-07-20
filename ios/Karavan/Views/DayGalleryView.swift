import SwiftUI

// Gün detayının en üstündeki yatay kaydırmalı şehir galerisi.
// Her görselin altında kısa açıklaması var; dokununca tam ekran açılır.
struct DayGalleryView: View {
    let photos: [GalleryPhoto]
    var height: CGFloat = 200

    @State private var selected: GalleryPhoto?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(photos) { photo in
                        Button { selected = photo } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                CampImage(path: photo.file, height: height, width: height * 1.5, cornerRadius: 16)
                                Text(photo.caption)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.dim)
                                    .lineLimit(1)
                                    .frame(width: height * 1.5, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
            HStack(spacing: 5) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 10))
                Text("\(photos.count) fotoğraf · kaydır")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(Theme.muted)
        }
        .fullScreenCover(item: $selected) { photo in
            PhotoDetailView(photo: photo)
        }
    }
}

private struct PhotoDetailView: View {
    let photo: GalleryPhoto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Spacer()
                CampImage(path: photo.file, height: 320, cornerRadius: 18)
                VStack(spacing: 6) {
                    Text(photo.caption)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(photo.cityName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    if let credit = photo.credit, !credit.isEmpty {
                        Text("\(credit)\(photo.license.map { " · \($0)" } ?? "")")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
                Spacer()
                Button { dismiss() } label: {
                    Text("Kapat")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 30).padding(.vertical, 12)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 28)
            }
        }
    }
}
