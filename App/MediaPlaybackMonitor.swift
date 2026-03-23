import AppKit
import CoreAudio

/// Observes system media playback status from common players.
final class MediaPlaybackMonitor: NSObject, @unchecked Sendable {
    enum Source: Hashable {
        case musicApp
        case iTunes
        case spotify
        case systemAudio
    }

    var onChange: ((Bool) -> Void)?

    private(set) var isPlaying = false
    private var sourceStates: [Source: Bool] = [:]
    private var observedOutputDeviceID: AudioDeviceID?
    private var monitoringEnabled = false
    private let audioObservationQueue = DispatchQueue(
        label: "ca.lingerly.media-playback-monitor",
        qos: .utility
    )
    private lazy var defaultOutputDeviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.handleDefaultOutputDeviceChanged()
    }
    private lazy var outputDeviceRunningListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.refreshObservedOutputDeviceState()
    }

    override init() {
        super.init()
    }

    /// Enables or disables playback monitoring.
    func setMonitoringEnabled(_ enabled: Bool) {
        guard enabled != monitoringEnabled else {
            if enabled {
                refreshObservedOutputDeviceState()
            }
            return
        }

        monitoringEnabled = enabled
        if enabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    /// Removes playback observers and stops system-audio polling.
    deinit {
        stopMonitoring()
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    /// Starts distributed-notification and CoreAudio observation.
    private func startMonitoring() {
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
        startSystemAudioObservation()
    }

    /// Stops all playback observation and clears the aggregate playback state.
    private func stopMonitoring() {
        guard monitoringEnabled || observedOutputDeviceID != nil || !sourceStates.isEmpty || isPlaying else {
            return
        }
        stopSystemAudioObservation()
        DistributedNotificationCenter.default().removeObserver(self)
        publishPlaybackStateReset()
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

        let nextValue: Bool
        switch state.lowercased() {
        case "playing":
            nextValue = true
        case "paused", "stopped":
            nextValue = false
        default:
            return
        }

        publishSource(source, isPlaying: nextValue)
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

    /// Starts event-driven CoreAudio observation for the default output device.
    private func startSystemAudioObservation() {
        var address = defaultOutputDeviceAddress
        _ = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            audioObservationQueue,
            defaultOutputDeviceListener
        )
        updateObservedOutputDevice()
        refreshObservedOutputDeviceState()
    }

    /// Stops CoreAudio observation and removes any registered listeners.
    private func stopSystemAudioObservation() {
        if let observedOutputDeviceID {
            removeRunningStateListener(from: observedOutputDeviceID)
            self.observedOutputDeviceID = nil
        }

        var address = defaultOutputDeviceAddress
        _ = AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            audioObservationQueue,
            defaultOutputDeviceListener
        )
    }

    /// Rebinds running-state observation when the default output device changes.
    private func handleDefaultOutputDeviceChanged() {
        updateObservedOutputDevice()
        refreshObservedOutputDeviceState()
    }

    /// Keeps the running-state listener attached to the current default output device.
    private func updateObservedOutputDevice() {
        let currentOutputDeviceID = defaultOutputDeviceID()
        guard currentOutputDeviceID != observedOutputDeviceID else { return }

        if let observedOutputDeviceID {
            removeRunningStateListener(from: observedOutputDeviceID)
        }

        observedOutputDeviceID = currentOutputDeviceID

        if let currentOutputDeviceID {
            addRunningStateListener(to: currentOutputDeviceID)
        }
    }

    /// Adds a running-state listener to the given output device.
    private func addRunningStateListener(to deviceID: AudioDeviceID) {
        var address = deviceRunningAddress
        _ = AudioObjectAddPropertyListenerBlock(
            deviceID,
            &address,
            audioObservationQueue,
            outputDeviceRunningListener
        )
    }

    /// Removes the running-state listener from the given output device.
    private func removeRunningStateListener(from deviceID: AudioDeviceID) {
        var address = deviceRunningAddress
        _ = AudioObjectRemovePropertyListenerBlock(
            deviceID,
            &address,
            audioObservationQueue,
            outputDeviceRunningListener
        )
    }

    /// Refreshes aggregate playback state from the observed output device.
    private func refreshObservedOutputDeviceState() {
        let isAudioRunning = observedOutputDeviceID.map(isDeviceRunning) ?? false
        publishSource(.systemAudio, isPlaying: isAudioRunning)
    }

    /// Publishes a source-state update on the main thread.
    private func publishSource(_ source: Source, isPlaying: Bool) {
        if Thread.isMainThread {
            setSource(source, isPlaying: isPlaying)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.setSource(source, isPlaying: isPlaying)
            }
        }
    }

    /// Clears aggregate playback state on the main thread.
    private func publishPlaybackStateReset() {
        let resetState = { [weak self] in
            guard let self else { return }
            let wasPlaying = self.isPlaying
            self.sourceStates.removeAll()
            self.isPlaying = false
            if wasPlaying {
                self.onChange?(false)
            }
        }

        if Thread.isMainThread {
            resetState()
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let wasPlaying = self.isPlaying
                self.sourceStates.removeAll()
                self.isPlaying = false
                if wasPlaying {
                    self.onChange?(false)
                }
            }
        }
    }

    /// Resolves the current default CoreAudio output device identifier.
    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = defaultOutputDeviceAddress
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
        var address = deviceRunningAddress
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

    /// CoreAudio property used to observe default output-device changes.
    private var defaultOutputDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// CoreAudio property used to observe whether an output device is currently running.
    private var deviceRunningAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
