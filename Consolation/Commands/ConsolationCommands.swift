//
//  ConsolationCommands.swift
//  Consolation
//
//  The menu bar on macOS and the hardware keyboard's ⌘ overlay on iPad. Audio and capture commands act on
//  `CaptureSessionManager` directly; About, Help and window sizing post notifications to the viewer window.
//

import SwiftUI

extension Notification.Name {
    static let showAboutCommand = Notification.Name(AppIdentifier.scoped("showAboutCommand"))
    static let showHelpCommand = Notification.Name(AppIdentifier.scoped("showHelpCommand"))
}

struct ConsolationCommands: Commands {
    let capture: CaptureSessionManager
    /// Bumped by the app after a rotation or mirror change, so the checkmarks re-read the saved transform.
    let previewTransformMenuRevision: Int
    let onPreviewTransformChanged: () -> Void

    @AppStorage(CaptureVideoStatsUserDefaults.showStatsKey) private var showVideoStats = false
    @AppStorage(CaptureVideoStatsUserDefaults.statsLocationKey) private var videoStatsLocationRawValue =
        CaptureVideoStatsUserDefaults.defaultLocation
    @AppStorage(CaptureVideoStatsUserDefaults.disableLowFPSWarningKey) private var disableLowFPSWarningOverlay = false
    #if os(macOS)
    @AppStorage(ViewerWindowUserDefaults.isAlwaysOnTopKey) private var isViewerWindowAlwaysOnTop = false
    #endif

    var body: some Commands {
        #if os(macOS)
        CommandGroup(replacing: .newItem) {}
        #endif
        CommandGroup(replacing: .appInfo) {
            Button("About \(AppIdentifier.name)") {
                NotificationCenter.default.post(name: .showAboutCommand, object: nil)
            }
        }
        CommandGroup(replacing: .help) {
            Button("\(AppIdentifier.name) Help") {
                NotificationCenter.default.post(name: .showHelpCommand, object: nil)
            }
            .keyboardShortcut("?", modifiers: [.command])
        }
        CommandGroup(after: .toolbar) {
            viewCommands
        }
        CommandMenu("Audio") {
            audioCommands
        }
    }

    @ViewBuilder
    private var viewCommands: some View {
        #if os(macOS)
        if capture.state == .running {
            Menu("Resize Window") {
                Button(".5x") {
                    NotificationCenter.default.post(name: .playbackSizeCommand, object: CGFloat(0.5))
                }
                Button("1x") {
                    NotificationCenter.default.post(name: .playbackSizeCommand, object: CGFloat(1))
                }
                Button("2x") {
                    NotificationCenter.default.post(name: .playbackSizeCommand, object: CGFloat(2))
                }
            }
            Divider()
        }
        #endif

        Menu("Video Stats") {
            videoStatsMenuOption(title: "Off", location: nil)
            ForEach(CaptureVideoStatsOverlayLocation.menuLocations, id: \.rawValue) { location in
                videoStatsMenuOption(title: location.menuTitle, location: location)
            }
        }
        Menu("Rotation") {
            ForEach(CaptureVideoPreviewRotation.allCases, id: \.rawValue) { rotation in
                previewRotationOption(rotation)
            }
        }
        Menu("Mirror Image") {
            previewMirrorOption(title: "Horizontal", mirror: .horizontal)
            previewMirrorOption(title: "Vertical", mirror: .vertical)
        }
        #if os(macOS)
        Divider()
        checkmarkButton(Text("Always on Top"), isOn: isViewerWindowAlwaysOnTop) {
            isViewerWindowAlwaysOnTop.toggle()
        }
        #endif
        Divider()
        Button(capture.state == .running ? "Stop Video" : "Start Video") {
            if capture.state == .running {
                capture.stopWatching()
            } else {
                Task { await capture.startWatching() }
            }
        }
        .disabled(capture.state != .running && !capture.canStartWatching)
        Divider()
        checkmarkButton(Text("Suppress Low FPS Warnings"), isOn: disableLowFPSWarningOverlay) {
            disableLowFPSWarningOverlay.toggle()
        }
        Divider()
    }

    @ViewBuilder
    private var audioCommands: some View {
        Section("Volume Level") {
            checkmarkButton(Text("Muted"), isOn: capture.isAudioMuted) {
                capture.setAudioMuted(!capture.isAudioMuted)
            }
            audioVolumeOption(label: "10%", level: 0.10)
            audioVolumeOption(label: "25%", level: 0.25)
            audioVolumeOption(label: "50%", level: 0.50)
            audioVolumeOption(label: "75%", level: 0.75)
            audioVolumeOption(label: "100%", level: 1.0)
        }

        Divider()

        Section("Buffer Size") {
            ForEach(CaptureAudioUserDefaults.bufferLengthOptions, id: \.self) { length in
                audioBufferLengthOption(length)
            }
        }
    }

    private func checkmarkButton(_ title: Text, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isOn {
                Label { title } icon: { Image(systemName: "checkmark") }
            } else {
                title
            }
        }
    }

    private func audioVolumeOption(label: String, level: Double) -> some View {
        Button(label) {
            capture.setVolumeLevel(level)
            if capture.isAudioMuted {
                capture.setAudioMuted(false)
            }
        }
    }

    private func audioBufferLengthOption(_ length: Int) -> some View {
        let label = length == CaptureAudioUserDefaults.defaultBufferLength
            ? "\(length) (default)"
            : "\(length)"
        return checkmarkButton(Text(label), isOn: capture.audioBufferLength == length) {
            capture.setAudioBufferLength(length)
        }
    }

    private func videoStatsMenuOption(title: String, location: CaptureVideoStatsOverlayLocation?) -> some View {
        checkmarkButton(Text(title), isOn: isVideoStatsOptionSelected(location: location)) {
            if let location {
                showVideoStats = true
                videoStatsLocationRawValue = location.rawValue
            } else {
                showVideoStats = false
            }
        }
    }

    private func isVideoStatsOptionSelected(location: CaptureVideoStatsOverlayLocation?) -> Bool {
        switch (showVideoStats, location) {
        case (false, nil):
            return true
        case (true, let selected?):
            return videoStatsLocationRawValue == selected.rawValue
        default:
            return false
        }
    }

    private var previewTransform: CaptureVideoPreviewTransform {
        _ = previewTransformMenuRevision
        return CaptureVideoPreviewTransformUserDefaults.load(forDeviceID: capture.selectedVideoDeviceUniqueID)
    }

    private func previewRotationOption(_ rotation: CaptureVideoPreviewRotation) -> some View {
        checkmarkButton(Text(rotation.menuTitle), isOn: previewTransform.rotation == rotation) {
            CaptureVideoPreviewTransformUserDefaults.saveRotation(
                rotation,
                forDeviceID: capture.selectedVideoDeviceUniqueID
            )
            onPreviewTransformChanged()
        }
        .disabled(capture.selectedVideoDeviceUniqueID == nil)
    }

    private func previewMirrorOption(title: String, mirror: CaptureVideoPreviewMirrorOptions) -> some View {
        let transform = previewTransform
        let isSelected = transform.mirrors.contains(mirror)
        return checkmarkButton(Text(title), isOn: isSelected) {
            var mirrors = transform.mirrors
            if isSelected {
                mirrors.remove(mirror)
            } else {
                mirrors.insert(mirror)
            }
            CaptureVideoPreviewTransformUserDefaults.saveMirrors(
                mirrors,
                forDeviceID: capture.selectedVideoDeviceUniqueID
            )
            onPreviewTransformChanged()
        }
        .disabled(capture.selectedVideoDeviceUniqueID == nil)
    }
}
