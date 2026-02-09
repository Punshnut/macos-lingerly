import AppKit

/// Observes system media playback status from common players.
final class MediaPlaybackMonitor {
    enum Source: Hashable {
        case musicApp
        case iTunes
        case spotify
    }

    var onChange: ((Bool) -> Void)?

    private(set) var isPlaying = false
    private var sourceStates: [Source: Bool] = [:]

    init() {
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(
            self,
            selector: #selector(musicPlayerInfoDidChange(_:)),
            name: Notification.Name("com.apple.Music.playerInfo"),
            object: nil
        )
        distributed.addObserver(
            self,
            selector: #selector(iTunesPlayerInfoDidChange(_:)),
            name: Notification.Name("com.apple.iTunes.playerInfo"),
            object: nil
        )
        distributed.addObserver(
            self,
            selector: #selector(spotifyPlaybackDidChange(_:)),
            name: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func musicPlayerInfoDidChange(_ notification: Notification) {
        updateState(from: notification, key: "Player State", source: .musicApp)
    }

    @objc private func spotifyPlaybackDidChange(_ notification: Notification) {
        updateState(from: notification, key: "Playback State", source: .spotify)
    }

    @objc private func iTunesPlayerInfoDidChange(_ notification: Notification) {
        updateState(from: notification, key: "Player State", source: .iTunes)
    }

    private func updateState(from notification: Notification, key: String, source: Source) {
        guard let info = notification.userInfo,
              let state = info[key] as? String else {
            return
        }

        switch state.lowercased() {
        case "playing":
            setSource(source, isPlaying: true)
        case "paused", "stopped":
            setSource(source, isPlaying: false)
        default:
            break
        }
    }

    private func setSource(_ source: Source, isPlaying: Bool) {
        sourceStates[source] = isPlaying
        let newValue = sourceStates.values.contains(true)
        if newValue != self.isPlaying {
            self.isPlaying = newValue
            onChange?(newValue)
        }
    }
}
