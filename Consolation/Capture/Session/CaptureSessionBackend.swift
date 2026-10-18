//
//  CaptureSessionBackend.swift
//  Consolation
//

import AVFoundation
import Foundation

/// Serializes `AVCaptureSession` configuration and `startRunning` / `stopRunning`.
actor CaptureSessionBackend {
    private var videoInput: AVCaptureDeviceInput?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var videoFrameRateMonitor: CaptureVideoFrameRateMonitor?
    private var audioInput: AVCaptureDeviceInput?
    private var audioDataOutput: AVCaptureAudioDataOutput?
    private var audioPlayback: CaptureAudioPlayback?
    private(set) var activeVideoSize: CGSize?
    /// Nominal capture FPS from locked min/max frame duration after configuration (for stats UI).
    private(set) var activeNominalFrameRate: Double?
    private var videoStatsUpdateHandler: (@Sendable (CaptureVideoFrameRateStats) -> Void)?

    func setVideoStatsUpdateHandler(_ handler: (@Sendable (CaptureVideoFrameRateStats) -> Void)?) {
        videoStatsUpdateHandler = handler
    }

    func startWatching(
        with session: AVCaptureSession,
        configuration: CaptureSessionStartConfiguration
    ) throws -> String {
        session.beginConfiguration()

        tearDownSessionInputs(session: session)

        guard let device = Self.resolveVideoDevice(uniqueID: configuration.videoDeviceUniqueID) else {
            session.commitConfiguration()
            throw CaptureSessionError.noVideoDevice
        }

        setPreferredSessionPresetIfAvailable(session)

        do {
            let input = try addVideoInput(for: device, to: session)
            try configureVideoDevice(
                device,
                input: input,
                session: session,
                formatPreferences: configuration.formatPreferences
            )
            addVideoFrameRateMonitor(to: session)
        } catch {
            session.commitConfiguration()
            throw error
        }

        addAudioInput(
            matchingVideoDevice: device,
            to: session,
            initialAudioMuted: configuration.initialAudioMuted,
            initialVolumeLevel: configuration.initialVolumeLevel,
            initialBufferLength: configuration.initialBufferLength
        )

        session.commitConfiguration()
        session.startRunning()
        reapplyFormatAfterStart(device: device, preferences: configuration.formatPreferences)
        logActiveVideoFormat(for: device)
        return device.localizedName
    }

    func stopWatching(with session: AVCaptureSession) {
        if session.isRunning {
            session.stopRunning()
        }

        session.beginConfiguration()
        tearDownAudio(session: session)
        tearDownVideoFrameRateMonitor(session: session)
        if let input = videoInput {
            session.removeInput(input)
            videoInput = nil
        }
        activeVideoSize = nil
        activeNominalFrameRate = nil
        session.commitConfiguration()
    }

    func setAudioMuted(_ muted: Bool) {
        audioPlayback?.setMuted(muted)
    }

    func setVolumeLevel(_ level: Double) {
        audioPlayback?.setVolumeLevel(level)
    }

    func setAudioBufferLength(_ length: Int) {
        audioPlayback?.setMaxPendingScheduledBuffers(length)
    }

    private func tearDownAudio(session: AVCaptureSession) {
        if let output = audioDataOutput {
            output.setSampleBufferDelegate(nil, queue: nil)
            session.removeOutput(output)
            audioDataOutput = nil
        }
        if let aIn = audioInput {
            session.removeInput(aIn)
            audioInput = nil
        }
        audioPlayback?.stop()
        audioPlayback = nil
    }

    private func tearDownSessionInputs(session: AVCaptureSession) {
        tearDownAudio(session: session)
        tearDownVideoFrameRateMonitor(session: session)
        if let existing = videoInput {
            session.removeInput(existing)
            videoInput = nil
        }
    }

    private func tearDownVideoFrameRateMonitor(session: AVCaptureSession) {
        if let output = videoDataOutput {
            output.setSampleBufferDelegate(nil, queue: nil)
            session.removeOutput(output)
            videoDataOutput = nil
        }
        videoFrameRateMonitor = nil
    }

    private func addVideoInput(
        for device: AVCaptureDevice,
        to session: AVCaptureSession
    ) throws -> AVCaptureDeviceInput {
        let input = try AVCaptureDeviceInput(device: device)

        guard session.canAddInput(input) else {
            throw CaptureSessionError.cannotAddVideoInput
        }

        session.addInput(input)
        videoInput = input
        return input
    }

    private func configureVideoDevice(
        _ device: AVCaptureDevice,
        input: AVCaptureDeviceInput,
        session: AVCaptureSession,
        formatPreferences: CaptureVideoFormatPreferences
    ) throws {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            try CaptureFormatSelector.applyPreferredFormat(device: device, preferences: formatPreferences)
        } catch {
            session.removeInput(input)
            videoInput = nil
            throw error
        }

        let format = device.activeFormat
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        activeVideoSize = CGSize(width: CGFloat(dims.width), height: CGFloat(dims.height))
        updateActiveNominalFrameRate(device: device)
    }

    private func addVideoFrameRateMonitor(to session: AVCaptureSession) {
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true

        let monitor = CaptureVideoFrameRateMonitor()
        let monitorID = ObjectIdentifier(monitor)
        monitor.onStatsInterval = { stats in
            Task { await self.publishVideoStats(stats, from: monitorID) }
        }
        output.setSampleBufferDelegate(monitor, queue: monitor.queue)

        guard session.canAddOutput(output) else {
            output.setSampleBufferDelegate(nil, queue: nil)
            return
        }

        session.addOutput(output)
        videoDataOutput = output
        videoFrameRateMonitor = monitor
    }

    /// Drops samples from a monitor that has since been torn down or replaced.
    private func publishVideoStats(_ stats: CaptureVideoFrameRateStats, from monitorID: ObjectIdentifier) {
        guard let current = videoFrameRateMonitor, ObjectIdentifier(current) == monitorID else { return }
        videoStatsUpdateHandler?(stats)
    }

    private func addAudioInput(
        matchingVideoDevice device: AVCaptureDevice,
        to session: AVCaptureSession,
        initialAudioMuted: Bool,
        initialVolumeLevel: Double,
        initialBufferLength: Int
    ) {
        guard let audioDevice = CaptureAudioDeviceSelection.pickPreferredAudioDevice(matchingVideoDevice: device),
              let input = try? AVCaptureDeviceInput(device: audioDevice),
              session.canAddInput(input)
        else {
            return
        }

        session.addInput(input)
        audioInput = input
        attachAudioOutput(
            for: input,
            to: session,
            initialAudioMuted: initialAudioMuted,
            initialVolumeLevel: initialVolumeLevel,
            initialBufferLength: initialBufferLength
        )
    }

    private func attachAudioOutput(
        for input: AVCaptureDeviceInput,
        to session: AVCaptureSession,
        initialAudioMuted: Bool,
        initialVolumeLevel: Double,
        initialBufferLength: Int
    ) {
        // Low-latency AVAudioEngine path. (`AVCaptureAudioPreviewOutput` exists on macOS only, not iOS.)
        let output = AVCaptureAudioDataOutput()
        configureAudioOutput(output)

        let playback = CaptureAudioPlayback()
        guard (try? playback.prepareSessionRouting()) != nil else {
            session.removeInput(input)
            audioInput = nil
            return
        }

        output.setSampleBufferDelegate(playback, queue: playback.workQueue)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            audioInput = nil
            return
        }

        session.addOutput(output)
        #if os(iOS)
        for connection in output.connections {
            connection.isEnabled = true
        }
        #endif
        audioDataOutput = output
        audioPlayback = playback
        playback.setAudioBeforeCaptureStarts(muted: initialAudioMuted, volumeLevel: initialVolumeLevel)
        playback.setMaxPendingScheduledBuffers(initialBufferLength)
    }

    private func configureAudioOutput(_ output: AVCaptureAudioDataOutput) {
        // Request standard 32-bit float non-interleaved PCM to avoid garbled integer/interleaved formats.
        // `audioSettings` is macOS-only; iOS always uses the capture device’s native PCM (see `CaptureAudioPlayback`).
        #if os(macOS)
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true,
            AVLinearPCMBitDepthKey: 32
        ]
        #endif
    }

    /// UVC / external capture on both macOS and iPadOS can reset active format or frame duration when
    /// the session starts; re-apply preferences immediately after `startRunning()`.
    private func reapplyFormatAfterStart(device: AVCaptureDevice, preferences: CaptureVideoFormatPreferences) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            try CaptureFormatSelector.reapplyFormatAndFrameDuration(device: device, preferences: preferences)
            updateActiveNominalFrameRate(device: device)
        } catch {
            #if DEBUG
            NSLog("[VideoCapture] failed to reapply format after startRunning: \(error)")
            #endif
        }
    }

    private func updateActiveNominalFrameRate(device: AVCaptureDevice) {
        let minDuration = device.activeVideoMinFrameDuration
        let maxDuration = device.activeVideoMaxFrameDuration
        guard minDuration.seconds > 0, minDuration.seconds.isFinite else {
            activeNominalFrameRate = nil
            return
        }
        if maxDuration.seconds > 0, maxDuration.seconds.isFinite,
           abs(minDuration.seconds - maxDuration.seconds) < 1e-6 {
            activeNominalFrameRate = 1.0 / minDuration.seconds
        } else {
            activeNominalFrameRate = 1.0 / minDuration.seconds
        }
    }

}

private extension CaptureSessionBackend {
    func setPreferredSessionPresetIfAvailable(_ session: AVCaptureSession) {
        #if os(iOS)
        if session.canSetSessionPreset(.inputPriority) {
            session.sessionPreset = .inputPriority
        }
        #endif
    }

    func logActiveVideoFormat(for device: AVCaptureDevice) {
        let minDuration = device.activeVideoMinFrameDuration
        let maxDuration = device.activeVideoMaxFrameDuration
        let minFPS = minDuration.seconds > 0 ? 1 / minDuration.seconds : 0
        let maxFPS = maxDuration.seconds > 0 ? 1 / maxDuration.seconds : 0
        #if DEBUG
        NSLog(
            "[VideoCapture] active format: " +
            "\(CaptureFormatSelector.videoFormatDescription(device.activeFormat)), " +
            "minFPS=\(minFPS), maxFPS=\(maxFPS)"
        )
        #endif
    }

    /// Resolves the device chosen in the connect panel, with a simulator fallback when discovery is empty.
    static func resolveVideoDevice(uniqueID: String) -> AVCaptureDevice? {
        if let device = AVCaptureDevice(uniqueID: uniqueID), device.hasMediaType(.video) {
            return device
        }

        #if targetEnvironment(simulator)
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices.first
        #else
        return nil
        #endif
    }
}
