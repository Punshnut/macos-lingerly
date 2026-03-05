import AppKit
import CoreAudio

/// Observes system media playback status from common players.
final class MediaPlaybackMonitor: NSObject {
    enum Source: Hashable {
        case musicApp
        case iTunes
        case spotify
        case systemAudio
    }

    var onChange: ((Bool) -> Void)?

    private(set) var isPlaying = false
    private var sourceStates: [Source: Bool] = [:]
    private var systemAudioTimer: Timer?

    override init() {
        super.init()
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
        startSystemAudioPolling()
    }

    /// Removes playback observers and stops system-audio polling.
    deinit {
        systemAudioTimer?.invalidate()
        systemAudioTimer = nil
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    /// Handles playback updates emitted by Apple Music.
    @objc private func musicPlayerInfoDidChange(_ notification: Notification) {
        updateState(from: notification, key: "Player State", source: .musicApp)
    }

    /// Handles playback updates emitted by Spotify.
    @objc private func spotifyPlaybackDidChange(_ notification: Notification) {
        updateState(from: notification, key: "Playback State", source: .spotify)
    }

    /// Handles playback updates emitted by legacy iTunes notifications.
    @objc private func iTunesPlayerInfoDidChange(_ notification: Notification) {
        updateState(from: notification, key: "Player State", source: .iTunes)
    }

    /// Normalizes player payloads into a shared playing/paused source state.
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

    /// Updates one source and emits onChange when aggregate playback flips.
    private func setSource(_ source: Source, isPlaying: Bool) {
        sourceStates[source] = isPlaying
        let newValue = sourceStates.values.contains(true)
        if newValue != self.isPlaying {
            self.isPlaying = newValue
            onChange?(newValue)
        }
    }

    /// Polls CoreAudio output state to detect non-app-specific playback.
    private func startSystemAudioPolling() {
        let timer = Timer.scheduledTimer(
            timeInterval: 1.5,
            target: self,
            selector: #selector(systemAudioTimerFired),
            userInfo: nil,
            repeats: true
        )
        systemAudioTimer = timer
        let initialState = isDefaultOutputDeviceRunning()
        setSource(.systemAudio, isPlaying: initialState)
    }

    /// Refreshes playback state from system output activity.
    @objc private func systemAudioTimerFired() {
        let isAudioRunning = isDefaultOutputDeviceRunning()
        setSource(.systemAudio, isPlaying: isAudioRunning)
    }

    /// Returns true when the current default output device reports active audio.
    private func isDefaultOutputDeviceRunning() -> Bool {
        guard let deviceID = defaultOutputDeviceID() else { return false }
        return isDeviceRunning(deviceID)
    }

    /// Resolves the current default CoreAudio output device identifier.
    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    /// Queries CoreAudio for whether the supplied output device is running.
    private func isDeviceRunning(_ deviceID: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &isRunning
        )
        guard status == noErr else { return false }
        return isRunning != 0
    }
}
