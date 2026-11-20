import Foundation
import AVFoundation
import SwiftUI

/// Built-in cross-notebook audio & music deck (Amphi Music parity) styled with BelloBook tokens.
@MainActor
final class AudioDeck: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = AudioDeck()

    struct QueueItem: Identifiable, Equatable {
        let id: UUID
        var notebookID: UUID
        var attachment: MediaAttachment
        var url: URL
    }

    @Published var queue: [QueueItem] = []
    @Published var currentIndex: Int? = nil
    @Published var isPlaying: Bool = false
    @Published var progress: Double = 0
    @Published var duration: Double = 0
    @Published var showFloatingBar: Bool = false

    private var player: AVAudioPlayer?
    private var timer: Timer?

    var currentItem: QueueItem? {
        guard let idx = currentIndex, queue.indices.contains(idx) else { return nil }
        return queue[idx]
    }

    func play(attachment: MediaAttachment, notebookID: UUID) {
        let url = MediaVault.shared.fileURL(for: attachment, in: notebookID)
        if let existingIdx = queue.firstIndex(where: { $0.id == attachment.id }) {
            loadAndPlay(at: existingIdx)
            return
        }
        let item = QueueItem(id: attachment.id, notebookID: notebookID, attachment: attachment, url: url)
        queue.append(item)
        loadAndPlay(at: queue.count - 1)
    }

    func enqueue(attachment: MediaAttachment, notebookID: UUID) {
        guard !queue.contains(where: { $0.id == attachment.id }) else { return }
        let url = MediaVault.shared.fileURL(for: attachment, in: notebookID)
        queue.append(QueueItem(id: attachment.id, notebookID: notebookID, attachment: attachment, url: url))
        showFloatingBar = true
    }

    func togglePlayPause() {
        guard let player else {
            if !queue.isEmpty { loadAndPlay(at: currentIndex ?? 0) }
            return
        }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func next() {
        guard !queue.isEmpty else { return }
        let nextIdx = ((currentIndex ?? -1) + 1) % queue.count
        loadAndPlay(at: nextIdx)
    }

    func previous() {
        guard !queue.isEmpty else { return }
        let prevIdx = ((currentIndex ?? 0) - 1 + queue.count) % queue.count
        loadAndPlay(at: prevIdx)
    }

    func seek(to fraction: Double) {
        guard let player, duration > 0 else { return }
        let clamped = min(max(fraction, 0), 1)
        player.currentTime = clamped * duration
        progress = clamped
    }

    func updateMetadata(id: UUID, title: String, artist: String, album: String) {
        if let idx = queue.firstIndex(where: { $0.id == id }) {
            queue[idx].attachment.title = title
            queue[idx].attachment.artist = artist
            queue[idx].attachment.album = album
        }
    }

    func stopAndDismiss() {
        player?.stop()
        player = nil
        timer?.invalidate()
        timer = nil
        isPlaying = false
        showFloatingBar = false
    }

    private func loadAndPlay(at index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        showFloatingBar = true
        let item = queue[index]
        do {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            let audioPlayer = try AVAudioPlayer(contentsOf: item.url)
            audioPlayer.delegate = self
            audioPlayer.prepareToPlay()
            audioPlayer.play()
            player = audioPlayer
            duration = audioPlayer.duration
            progress = 0
            isPlaying = true
            startTimer()
        } catch {
            isPlaying = false
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player, player.duration > 0 else { return }
                self.duration = player.duration
                self.progress = player.currentTime / player.duration
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.queue.count > 1 {
                self.next()
            } else {
                self.isPlaying = false
                self.progress = 0
            }
        }
    }
}

/// Compact floating audio bar styled to match `Style.swift` (MyScript blue + ambientShadow).
struct AudioDeckMiniBar: View {
    @ObservedObject var deck = AudioDeck.shared

    var body: some View {
        if deck.showFloatingBar, let item = deck.currentItem {
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Style.accent)
                    .frame(width: 30, height: 30)
                    .background(Style.accent.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.attachment.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(item.attachment.artist.isEmpty ? "BelloBook Audio" : item.attachment.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button(action: deck.previous) {
                    Image(systemName: "backward.fill").font(.caption)
                }
                Button(action: deck.togglePlayPause) {
                    Image(systemName: deck.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Style.accent)
                }
                Button(action: deck.next) {
                    Image(systemName: "forward.fill").font(.caption)
                }
                Button(action: deck.stopAndDismiss) {
                    Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: 420)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Style.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Style.cardRadius)
                    .stroke(Color.hairline, lineWidth: 1)
            )
            .ambientShadow()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
