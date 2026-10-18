//
//  CaptureSessionManager.swift
//  Consolation
//

// `AVCaptureSession` has no Sendable annotation, yet it is deliberately shared between the main-actor preview
// layers and `CaptureSessionBackend`, which serializes every mutation. Every hand-off of `session` to the backend
// stays in this file, under this import: Xcode 26's compiler (CI's) rejects the hand-off anywhere else.
@preconcurrency import AVFoundation
import Foundation
import Observation

struct CaptureDeviceSummary: Identifiable, Hashable, Sendable {
    let id: String
    let localizedName: String
}

/// Owns the shared `AVCaptureSession` for preview layers and publishes UI state on the main actor.
@MainActor
@Observable
final class CaptureSessionManager {
    var state: CaptureState = .idle {
        didSet {
            if state != .running { clearVideoFrameRateStats() }
        }
    }

    /// Device name while running, or auxiliary detail for failures.
    var statusMessage: String?

    /// True when at least one non-Continuity external video device is present (USB capture path).
    private(set) var isExternalCaptureDeviceConnected = false

    /// Localized name of the currently detected USB video capture device, when present.
    private(set) var externalCaptureDeviceName: String?

    /// USB capture cards (UVC) vs built-in / Continuity / other cameras, for the connect panel.
    var usbCaptureDeviceEntries: [CaptureDeviceSummary] = []
    var cameraDeviceEntries: [CaptureDeviceSummary] = []

    /// `true` when discovery finds no video devices at all.
    var hasNoVideoDevices = true

    /// Persisted choice for the connect panel; `nil` only before the first successful refresh.
    var selectedVideoDeviceUniqueID: String?

    /// Live audio from the capture card is audible when `false`.
    /// Persisted across launches; see `CaptureAudioUserDefaults`.
    var isAudioMuted: Bool

    /// Live audio output level, separate from mute so unmuting restores the prior level.
    var volumeLevel: Double

    /// Max number of queued PCM buffers kept pending in `CaptureAudioPlayback`.
    var audioBufferLength: Int

    /// Published dimensions of the currently active video feed to inform UI aspect ratio logic natively.
    var videoSize: CGSize?

    /// Locked nominal capture rate after session start (from device min/max frame duration); stats overlay uses this.
    var nominalVideoFrameRate: Double?

    /// Latest once-per-second delivery sample from the video data output while running; `nil` otherwise.
    /// Written only by `receiveVideoFrameRateStats(_:)` and `clearVideoFrameRateStats()`.
    var videoFrameRateStats: CaptureVideoFrameRateStats?

    /// Consecutive samples delivered well below the configured frame rate; drives the low-FPS warning overlay.
    var lowFrameRateSampleStreak = 0

    /// Idle-card notice for camera/mic: undecided, denied in Settings, or `none` when both allowed.
    private(set) var mediaPermissionNotice: CaptureMediaPermissionNotice = .none

    /// Shared with `AVCaptureVideoPreviewLayer`; mutations happen only on `CaptureSessionBackend`.
    nonisolated let session = AVCaptureSession()

    @ObservationIgnored let backend = CaptureSessionBackend()
    /// Device connect / disconnect observers; cancelled when the manager goes away.
    @ObservationIgnored var hardwareObservationTasks: [Task<Void, Never>] = []
    @ObservationIgnored var activeSessionVideoDeviceUniqueID: String?
    @ObservationIgnored var lastLoggedVideoCapabilitiesSignature: String?

    /// Resolved before each `startWatching`; published so the connect panel updates labels and checkmarks.
    var formatPreferences: CaptureVideoFormatPreferences

    /// Pass `nil` to load the built-in default today, and later persisted values.
    init(formatPreferences: CaptureVideoFormatPreferences? = nil) {
        CaptureAudioUserDefaults.registerDefaults()
        isAudioMuted = CaptureAudioUserDefaults.loadIsMuted()
        volumeLevel = CaptureAudioUserDefaults.loadVolumeLevel()
        audioBufferLength = CaptureAudioUserDefaults.loadBufferLength()
        self.formatPreferences = formatPreferences ?? .defaultForLaunch
        if formatPreferences == nil { loadStoredFormatPreferences() }
        Task { [weak self] in
            guard let self else { return }
            await self.backend.setVideoStatsUpdateHandler { [weak self] stats in
                Task { @MainActor [weak self] in
                    self?.receiveVideoFrameRateStats(stats)
                }
            }
        }
        beginObservingVideoHardwareChanges()
        refreshVideoDeviceUniverse(reconcileSelection: true)
        refreshMediaCaptureAuthorizationStatuses()
    }

    deinit {
        hardwareObservationTasks.forEach { $0.cancel() }
    }

    func refreshMediaCaptureAuthorizationStatuses() {
        mediaPermissionNotice = CaptureMediaPermissionNotice.current()
    }

    func refreshExternalCapturePresence() {
        let name = Self.connectedExternalVideoDeviceName()
        if externalCaptureDeviceName != name {
            externalCaptureDeviceName = name
        }
        let isConnected = name != nil
        if isExternalCaptureDeviceConnected != isConnected {
            isExternalCaptureDeviceConnected = isConnected
        }
    }

    func selectVideoDevice(uniqueID: String) {
        selectedVideoDeviceUniqueID = uniqueID
        CaptureVideoDeviceUserDefaults.saveSelectedDeviceUniqueID(uniqueID)
        applyFormatPreferencesForSelectedDevice(uniqueID: uniqueID)
        exitFailedConnectStateAfterUserChangedSelection()
    }

    func selectVideoFormat(width: Int, height: Int, frameRate: Double) {
        formatPreferences = formatPreferences.withPreferredFormat(width: width, height: height, frameRate: frameRate)
        formatPreferences.saveToStorage()
        if let deviceID = selectedVideoDeviceUniqueID {
            CaptureVideoFormatUserDefaults.savePreferredFormat(
                width: width,
                height: height,
                frameRate: frameRate,
                forDeviceID: deviceID
            )
        }
        exitFailedConnectStateAfterUserChangedSelection()
    }

    /// After a failed start (e.g. no supported format), `canStartWatching` stays false until the user changes setup.
    private func exitFailedConnectStateAfterUserChangedSelection() {
        guard case .failed = state else { return }
        state = .idle
        statusMessage = nil
    }

    /// Primary line for the connect panel when a USB capture card is available (status copy).
    var primaryUSBVideoCaptureDisplayName: String? {
        usbCaptureDeviceEntries.first?.localizedName ?? externalCaptureDeviceName
    }

    /// Device button label: main title (device name or prompt).
    func connectPanelDevicePrimaryLabel() -> String {
        guard let id = selectedVideoDeviceUniqueID,
              let device = AVCaptureDevice(uniqueID: id)
        else {
            return hasNoVideoDevices ? "No devices found" : "Choose a device"
        }
        return device.localizedName
    }

    /// Resolution / frame rate line for the connect panel (explicit if valid, else automatic pick).
    func connectPanelResolutionLabel() -> String {
        guard let id = selectedVideoDeviceUniqueID,
              let device = AVCaptureDevice(uniqueID: id)
        else {
            return "—"
        }
        if let dims = CaptureFormatSelector.effectiveFormatForDisplay(device: device, preferences: formatPreferences) {
            return CaptureVideoFormatDisplayStrings.resolutionAndFrameLabel(
                width: dims.width,
                height: dims.height,
                frameRate: dims.frameRate
            )
        }
        return "Default"
    }

    var canStartWatching: Bool { shouldShowStartWatchingButton && mediaPermissionNotice != .deniedOrRestricted }

    var shouldShowStartWatchingButton: Bool {
        guard !hasNoVideoDevices else { return false }
        switch state {
        case .ready, .idle, .noDevice:
            return true
        case .requestingPermission, .running, .failed:
            return false
        }
    }

    nonisolated static func hasConnectedExternalVideoDevice() -> Bool {
        connectedExternalVideoDeviceName() != nil
    }

    nonisolated static func connectedExternalVideoDeviceName() -> String? {
        CaptureVideoDeviceDiscovery.connectedUSBVideoCaptureDisplayName()
    }

    func startWatching() async {
        defer { refreshMediaCaptureAuthorizationStatuses() }

        guard let deviceID = selectedVideoDeviceUniqueID,
              AVCaptureDevice(uniqueID: deviceID) != nil
        else {
            state = .noDevice
            statusMessage = "No video devices are available."
            return
        }

        statusMessage = nil
        state = .requestingPermission

        let granted = await CaptureSessionMediaAccess.requestCameraAccessIfNeeded()
        guard granted else {
            state = .failed("Camera access is required to use this app.")
            statusMessage = "Allow camera access in Settings to continue."
            return
        }

        _ = await CaptureSessionMediaAccess.requestMicrophoneAccessIfNeeded()

        let muted = CaptureAudioUserDefaults.loadIsMuted()
        let volumeLevel = CaptureAudioUserDefaults.loadVolumeLevel()
        let bufferLength = CaptureAudioUserDefaults.loadBufferLength()
        let configuration = makeStartConfiguration(
            deviceID: deviceID,
            muted: muted,
            volumeLevel: volumeLevel,
            bufferLength: bufferLength
        )
        do {
            let name = try await backend.startWatching(with: session, configuration: configuration)
            await applySuccessfulStartWatching(
                deviceID: deviceID,
                displayName: name,
                muted: muted,
                volumeLevel: volumeLevel,
                bufferLength: bufferLength
            )
        } catch {
            handleStartWatchingError(error)
        }
    }

    func stopWatching() {
        nominalVideoFrameRate = nil
        Task {
            await stopBackendCapture()
            self.state = .idle
            self.statusMessage = nil
            self.activeSessionVideoDeviceUniqueID = nil
            self.isAudioMuted = CaptureAudioUserDefaults.loadIsMuted()
            self.volumeLevel = CaptureAudioUserDefaults.loadVolumeLevel()
            self.audioBufferLength = CaptureAudioUserDefaults.loadBufferLength()
            self.videoSize = nil
            self.nominalVideoFrameRate = nil
            self.refreshMediaCaptureAuthorizationStatuses()
        }
    }

    func setAudioMuted(_ muted: Bool) {
        isAudioMuted = muted
        CaptureAudioUserDefaults.saveIsMuted(muted)
        Task {
            await backend.setAudioMuted(muted)
        }
    }

    func setVolumeLevel(_ level: Double) {
        let clamped = min(max(level, 0), 1)
        volumeLevel = clamped
        CaptureAudioUserDefaults.saveVolumeLevel(clamped)
        Task {
            await backend.setVolumeLevel(clamped)
        }
    }

    func setAudioBufferLength(_ length: Int) {
        let normalizedLength = CaptureAudioUserDefaults.bufferLengthOptions.contains(length)
            ? length
            : CaptureAudioUserDefaults.defaultBufferLength
        audioBufferLength = normalizedLength
        CaptureAudioUserDefaults.saveBufferLength(normalizedLength)
        Task {
            await backend.setAudioBufferLength(normalizedLength)
        }
    }
}

// MARK: - Backend hand-off

extension CaptureSessionManager {
    /// Stops capture on the backend and tears down its inputs and outputs.
    func stopBackendCapture() async {
        await backend.stopWatching(with: session)
    }
}

// MARK: - Start watching

private extension CaptureSessionManager {
    func makeStartConfiguration(
        deviceID: String,
        muted: Bool,
        volumeLevel: Double,
        bufferLength: Int
    ) -> CaptureSessionStartConfiguration {
        CaptureSessionStartConfiguration(
            videoDeviceUniqueID: deviceID,
            formatPreferences: formatPreferences,
            initialAudioMuted: muted,
            initialVolumeLevel: volumeLevel,
            initialBufferLength: bufferLength
        )
    }

    func handleStartWatchingError(_ error: Error) {
        activeSessionVideoDeviceUniqueID = nil
        nominalVideoFrameRate = nil
        if let captureError = error as? CaptureSessionError {
            switch captureError {
            case .noVideoDevice:
                state = .noDevice
                statusMessage = captureError.localizedDescription
            case .cannotAddVideoInput:
                state = .failed(captureError.localizedDescription)
                statusMessage = captureError.localizedDescription
            }
            return
        }
        state = .failed(error.localizedDescription)
        statusMessage = error.localizedDescription
    }

    func applySuccessfulStartWatching(
        deviceID: String,
        displayName: String,
        muted: Bool,
        volumeLevel: Double,
        bufferLength: Int
    ) async {
        state = .running
        statusMessage = displayName
        activeSessionVideoDeviceUniqueID = deviceID
        isAudioMuted = muted
        self.volumeLevel = volumeLevel
        audioBufferLength = bufferLength
        await backend.setAudioMuted(muted)
        await backend.setVolumeLevel(volumeLevel)
        await backend.setAudioBufferLength(bufferLength)
        videoSize = await backend.activeVideoSize
        nominalVideoFrameRate = await backend.activeNominalFrameRate
    }

    func loadStoredFormatPreferences() {
        Task(priority: .userInitiated) { [weak self] in
            let loadedPreferences = await Self.formatPreferencesFromStorage()
            self?.formatPreferences = loadedPreferences
        }
    }

    /// Reads the persisted format choice off the main actor.
    @concurrent
    nonisolated static func formatPreferencesFromStorage() async -> CaptureVideoFormatPreferences {
        CaptureVideoFormatPreferences.loadFromStorage()
    }
}
