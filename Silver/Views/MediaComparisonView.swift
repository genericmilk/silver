import SwiftUI
import AVKit
import ImageIO

struct MediaComparisonView: View {
    let comparison: MediaComparison
    @Environment(Preferences.self) private var preferences
    @State private var preview = MediaPreviewModel()

    var body: some View {
        Group {
            if preferences.diffStyle == "split" {
                HStack(spacing: 0) {
                    pane("Before", version: preview.before)
                    Divider()
                    pane("After", version: preview.after)
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        pane("Before", version: preview.before).frame(minHeight: 260)
                        Divider()
                        pane("After", version: preview.after).frame(minHeight: 260)
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task { await preview.load(comparison) }
        .onDisappear { preview.stop() }
    }

    private func pane(_ title: String, version: PreparedMediaVersion) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).fontWeight(.medium)
                Spacer(minLength: 8)
                if let metadata = version.metadata { Text(metadata).font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.trailing) }
            }.font(.callout).padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            Group {
                switch version {
                case .loading:
                    ProgressView().controlSize(.small)
                case .absent:
                    Text("Not in this version").font(.callout).foregroundStyle(.secondary)
                case .failed(let message):
                    ContentUnavailableView("Unable to Preview", systemImage: comparison.kind == .image ? "photo" : "waveform", description: Text(message))
                case .image(let image, _, let path):
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                        .padding(20).accessibilityLabel((path as NSString).lastPathComponent)
                case .audio(let player, _, _):
                    VStack(spacing: 20) {
                        Image(systemName: "waveform").font(.system(size: 40, weight: .light)).foregroundStyle(.secondary).accessibilityHidden(true)
                        NativeAudioPlayer(player: player).frame(height: 76)
                    }.padding(20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum PreparedMediaVersion {
    case loading
    case absent
    case failed(String)
    case image(NSImage, metadata: String, path: String)
    case audio(AVPlayer, metadata: String, path: String)
    var metadata: String? {
        switch self { case .image(_, let value, _), .audio(_, let value, _): value; default: nil }
    }
    var player: AVPlayer? { if case .audio(let player, _, _) = self { player } else { nil } }
}

/// The lease removes only Silver's own temporary snapshots after the preview is released.
private final class MediaPreviewFiles: @unchecked Sendable {
    let directory: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Silver-Media-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
}

@MainActor @Observable private final class MediaPreviewModel {
    var before = PreparedMediaVersion.loading
    var after = PreparedMediaVersion.loading
    @ObservationIgnored private var files: MediaPreviewFiles?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    private var loaded = false

    func load(_ comparison: MediaComparison) async {
        guard !loaded else { return }
        loaded = true
        do {
            let lease = try MediaPreviewFiles()
            files = lease
            async let old = prepare(comparison.before, kind: comparison.kind, name: "before", lease: lease)
            async let new = prepare(comparison.after, kind: comparison.kind, name: "after", lease: lease)
            let (oldVersion, newVersion) = await (old, new)
            guard !Task.isCancelled else { oldVersion.player?.pause(); newVersion.player?.pause(); return }
            before = oldVersion
            after = newVersion
            if let oldPlayer = before.player, let newPlayer = after.player {
                observe(oldPlayer, pausing: newPlayer)
                observe(newPlayer, pausing: oldPlayer)
            }
        } catch {
            before = .failed(error.localizedDescription)
            after = .failed(error.localizedDescription)
        }
    }
    func stop() { before.player?.pause(); after.player?.pause() }
    private func observe(_ player: AVPlayer, pausing other: AVPlayer) {
        observations.append(player.observe(\.rate, options: [.new]) { [weak player, weak other] _, _ in
            Task { @MainActor in if let player, player.rate > 0 { other?.pause() } }
        })
    }
    private func prepare(_ version: MediaVersion, kind: MediaKind, name: String, lease: MediaPreviewFiles) async -> PreparedMediaVersion {
        switch version {
        case .absent: return .absent
        case .unavailable(let message): return .failed(message)
        case .content(let data, let path):
            do {
                guard !data.starts(with: Data("version https://git-lfs.github.com/spec/v1".utf8)) else { return .failed("Git LFS pointers do not contain the media needed for a preview.") }
                let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
                let format = (path as NSString).pathExtension.uppercased()
                switch kind {
                case .image:
                    let decoded = try await Task.detached(priority: .userInitiated) {
                        try MediaImageDecoder.decode(data)
                    }.value
                    try Task.checkCancellation()
                    let image = NSImage(cgImage: decoded.image, size: .zero)
                    return .image(image, metadata: "\(format) · \(decoded.width) × \(decoded.height) · \(size)", path: path)
                case .audio:
                    let destination = lease.directory.appendingPathComponent(name).appendingPathExtension((path as NSString).pathExtension)
                    try await Task.detached(priority: .userInitiated) { try data.write(to: destination, options: .atomic) }.value
                    try Task.checkCancellation()
                    let asset = AVURLAsset(url: destination)
                    guard try await asset.load(.isPlayable) else { return .failed("macOS cannot play this audio format.") }
                    let duration = try await asset.load(.duration).seconds
                    try Task.checkCancellation()
                    let seconds = duration.isFinite && duration > 0 ? Int(duration) : 0
                    let time = seconds >= 3_600 ? String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60) : String(format: "%d:%02d", seconds / 60, seconds % 60)
                    let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
                    player.actionAtItemEnd = .pause
                    return .audio(player, metadata: "\(format) · \(time) · \(size)", path: path)
                }
            } catch is CancellationError { return .loading }
            catch { return .failed(error.localizedDescription) }
        }
    }
}

private struct NativeAudioPlayer: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = false
        view.showsSharingServiceButton = false
        view.showsFrameSteppingButtons = false
        view.player = player
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}
