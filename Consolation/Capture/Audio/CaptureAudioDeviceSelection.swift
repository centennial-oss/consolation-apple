//
//  CaptureAudioDeviceSelection.swift
//  Consolation
//

import AVFoundation
import Foundation
#if os(iOS)
import AVFAudio
#endif

enum CaptureAudioDeviceSelection {
    /// Names that almost always mean the Mac / headset / Continuity — never use for HDMI capture audio.
    nonisolated private static let excludedBuiltInOrAmbientTokens: [String] = [
        "macbook", "imac", "mac studio", "mac pro", "mac mini",
        "built-in", "internal microphone", "internal mic",
        "facetime", "studio display", "airpods", "headset", "headphones",
        "iphone", "ipad", "continuity"
    ]

    nonisolated private static func isLikelyBuiltInOrAmbientMic(name: String) -> Bool {
        let normalizedName = name.lowercased()
        return excludedBuiltInOrAmbientTokens.contains { normalizedName.contains($0) }
    }

    /// Picks the **single** audio endpoint tied to the USB capture device (HDMI audio from the card).
    /// Returns `nil` when there is no confident match — avoids mixing in the Mac mic (feedback / garble).
    nonisolated static func pickPreferredAudioDevice(
        matchingVideoDevice videoDevice: AVCaptureDevice
    ) -> AVCaptureDevice? {
        #if os(iOS)
        let audioDeviceTypes: [AVCaptureDevice.DeviceType] = [.microphone, .external]
        #else
        let audioDeviceTypes: [AVCaptureDevice.DeviceType] = [.microphone]
        #endif
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: audioDeviceTypes,
            mediaType: .audio,
            position: .unspecified
        )
        let devices = discovery.devices
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .mixWithOthers, .allowBluetoothHFP, .allowBluetoothA2DP]
            )
            try audioSession.setActive(true)
            if let externalInput = audioSession.availableInputs?.first(where: { $0.portType != .builtInMic }) {
                try audioSession.setPreferredInput(externalInput)
            }
        } catch {
            #if DEBUG
            NSLog("[iOSAudioSession] setup failed before device selection: \(error)")
            #endif
        }
        #endif
        guard !devices.isEmpty else { return nil }

        let videoName = videoDevice.localizedName
        if let heuristic = pickHeuristicAudioMatch(devices: devices, videoName: videoName) {
            return heuristic
        }

        #if targetEnvironment(simulator)
        return devices.first
        #else
        return nil
        #endif
    }

    /// Exact name, substring, and token overlap between video device name and audio endpoints.
    nonisolated private static func pickHeuristicAudioMatch(
        devices: [AVCaptureDevice],
        videoName: String
    ) -> AVCaptureDevice? {
        if let exact = devices.first(where: { $0.localizedName.caseInsensitiveCompare(videoName) == .orderedSame }) {
            return exact
        }

        let candidates = devices.filter { !isLikelyBuiltInOrAmbientMic(name: $0.localizedName) }
        if videoName.count >= 4 {
            if let substringMatch = candidates.first(where: {
                videoName.localizedCaseInsensitiveContains($0.localizedName) && $0.localizedName.count >= 4
            }) {
                return substringMatch
            }
            if let substringMatch = candidates.first(where: {
                $0.localizedName.localizedCaseInsensitiveContains(videoName)
            }) {
                return substringMatch
            }
        }

        let tokens = significantTokens(from: videoName)
        var best: (device: AVCaptureDevice, score: Int)?
        for device in candidates {
            let audioName = device.localizedName
            guard !isLikelyBuiltInOrAmbientMic(name: audioName) else { continue }
            var score = 0
            for token in tokens where audioName.localizedCaseInsensitiveContains(token) {
                score += token.count + 10
            }
            if isBetterMatch(score: score, audioName: audioName, than: best) {
                best = (device, score)
            }
        }
        return best?.device
    }
    /// Words / fragments from the video device name useful for matching audio (drops tiny noise words).
    nonisolated private static func significantTokens(from name: String) -> [String] {
        let separators = CharacterSet.alphanumerics.inverted
        return name
            .components(separatedBy: separators)
            .map { $0.lowercased() }
            .filter { $0.count >= 3 }
    }

    nonisolated private static func isBetterMatch(
        score: Int,
        audioName: String,
        than best: (device: AVCaptureDevice, score: Int)?
    ) -> Bool {
        guard score > 0 else { return false }
        guard let best else { return true }
        return score > best.score || (score == best.score && audioName.count > best.device.localizedName.count)
    }
}
