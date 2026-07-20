import SwiftUI

// Yolculuk müziği: parça listesi + çalar. Parçalar cihaza indirilip saklanır,
// sinyalsiz bölgelerde de çalar. Anons gelince ses otomatik kısılır.
struct MusicView: View {
    @ObservedObject private var music = MusicPlayer.shared
    @State private var tick = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if music.tracks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 36)).foregroundStyle(Theme.muted)
                    Text("Parça listesi yükleniyor…\nBağlantı yoksa daha önce indirilenler çalar.")
                        .font(.system(size: 14)).foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        nowPlayingCard
                        VStack(alignment: .leading, spacing: 10) {
                            MonoLabel(text: "Parçalar · \(music.tracks.count)", color: Theme.c4)
                            ForEach(music.tracks) { track in
                                trackRow(track)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Müzik")
        .navigationBarTitleDisplayMode(.inline)
        .task { await music.load() }
        .onReceive(timer) { tick = $0 }
        .preferredColorScheme(.dark)
    }

    // MARK: - Çalar

    @ViewBuilder private var nowPlayingCard: some View {
        if let track = music.current {
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Text(track.title)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                    if let artist = track.artist {
                        Text(artist)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                }

                // İlerleme (saniyede bir tazelenir)
                VStack(spacing: 5) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10))
                            Capsule().fill(Theme.gradWarm)
                                .frame(width: geo.size.width * music.progress)
                        }
                    }
                    .frame(height: 6)
                    HStack {
                        Text(music.currentTimeText)
                        Spacer()
                        Text(music.durationText)
                    }
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                }
                .id(tick)   // saniyelik tazeleme

                HStack(spacing: 26) {
                    Button { music.shuffle.toggle() } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(music.shuffle ? Theme.c4 : Theme.muted)
                    }
                    Button { music.previous() } label: {
                        Image(systemName: "backward.fill").font(.system(size: 21))
                            .foregroundStyle(Theme.text)
                    }
                    Button { music.toggle() } label: {
                        ZStack {
                            Circle().fill(Theme.gradWarm).frame(width: 62, height: 62)
                            Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    Button { music.next() } label: {
                        Image(systemName: "forward.fill").font(.system(size: 21))
                            .foregroundStyle(Theme.text)
                    }
                    Button { music.repeatAll.toggle() } label: {
                        Image(systemName: "repeat")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(music.repeatAll ? Theme.c4 : Theme.muted)
                    }
                }
                .buttonStyle(.plain)
            }
            .card()
        }
    }

    private func trackRow(_ track: Track) -> some View {
        let isCurrent = music.current?.id == track.id
        let isDownloading = music.downloading.contains(track.id)
        return Button {
            Task { await music.play(track) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isCurrent ? AnyShapeStyle(Theme.gradWarm) : AnyShapeStyle(Theme.panel))
                        .frame(width: 40, height: 40)
                    if isDownloading {
                        ProgressView().tint(Theme.c1).scaleEffect(0.7)
                    } else {
                        Image(systemName: isCurrent && music.isPlaying ? "waveform" : "music.note")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isCurrent ? .white : Theme.dim)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(isCurrent ? Theme.c1 : Theme.text)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let artist = track.artist {
                            Text(artist).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                        if let d = track.duration {
                            Text("· \(MusicPlayer.timeText(d))")
                                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: music.isDownloaded(track) ? "arrow.down.circle.fill" : "icloud.and.arrow.down")
                    .font(.system(size: 14))
                    .foregroundStyle(music.isDownloaded(track) ? Theme.ok : Theme.muted)
            }
            .padding(11)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isCurrent ? Theme.c1.opacity(0.5) : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// Panelde görünen küçük çalar (bir şey çalıyorsa).
struct MiniMusicBar: View {
    @ObservedObject private var music = MusicPlayer.shared

    var body: some View {
        if let track = music.current {
            HStack(spacing: 11) {
                Image(systemName: music.isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.c1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if let artist = track.artist {
                        Text(artist).font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                Button { music.toggle() } label: {
                    Image(systemName: music.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 27))
                        .foregroundStyle(Theme.c1)
                }
                .buttonStyle(.plain)
                Button { music.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.dim)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1))
        }
    }
}
