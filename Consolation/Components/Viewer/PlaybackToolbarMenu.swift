//
//  PlaybackToolbarMenu.swift
//  Consolation
//

import SwiftUI

struct PlaybackToolbarMenu<Content: View>: View, Equatable {
    let systemName: String
    let accessibilityLabel: String
    var iconColor: Color = .primary
    var hoverTint: Color = Color.white
    var dimension: CGFloat = 42
    @Binding var isPresented: Bool
    let onPresentedChanged: (Bool) -> Void
    @ViewBuilder let menuContent: () -> Content

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    private var iconPointSize: CGFloat { dimension * 0.5 }

    static func == (lhs: PlaybackToolbarMenu<Content>, rhs: PlaybackToolbarMenu<Content>) -> Bool {
        lhs.systemName == rhs.systemName
            && lhs.accessibilityLabel == rhs.accessibilityLabel
            && lhs.iconColor == rhs.iconColor
            && lhs.hoverTint == rhs.hoverTint
            && lhs.dimension == rhs.dimension
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            ZStack {
                Circle()
                    .fill(isHovered && isEnabled ? hoverTint.opacity(0.16) : Color.clear)
                Image(systemName: systemName)
                    .font(.system(size: iconPointSize, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .allowsHitTesting(false)
            }
            .frame(width: dimension, height: dimension)
            .contentShape(Circle())
            .onHover { isHovered = $0 }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented) {
            menuContent()
                .padding(.vertical, 12)
                .padding(.leading, 12)
                .frame(width: 280, alignment: .leading)
                .tint(.primary)
                .presentationCompactAdaptation(.popover)
                .onDisappear {
                    // Backup for flaky `onChange(of: isPresented)` (nested menus); defer matches other dismiss paths.
                    DispatchQueue.main.async {
                        onPresentedChanged(false)
                    }
                }
        }
        .onChange(of: isPresented) { _, newValue in
            onPresentedChanged(newValue)
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

struct IPadSettingsMenuContent: View, Equatable {
    let capture: CaptureSessionManager
    let selectedVideoDeviceUniqueID: String?

    @Environment(\.dismiss) private var dismiss

    @AppStorage(CaptureVideoStatsUserDefaults.showStatsKey) var showVideoStats = false
    @AppStorage(CaptureVideoStatsUserDefaults.statsLocationKey)
    var videoStatsLocationRawValue = CaptureVideoStatsUserDefaults.defaultLocation
    @AppStorage(CaptureVideoStatsUserDefaults.disableLowFPSWarningKey) var disableLowFPSWarningOverlay = false

    @State private var previewTransformMenuRefresh = 0

    static func == (lhs: IPadSettingsMenuContent, rhs: IPadSettingsMenuContent) -> Bool {
        lhs.capture === rhs.capture && lhs.selectedVideoDeviceUniqueID == rhs.selectedVideoDeviceUniqueID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            videoStatsMenu
            lowFPSMenu
            previewRotationMenu
            previewMirrorMenu
            audioBufferLengthMenu
            Divider()
            Button("\(AppIdentifier.name) Help") {
                NotificationCenter.default.post(name: .showHelpCommand, object: nil)
                dismissPopoverAfterSelection()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Button("About \(AppIdentifier.name)") {
                NotificationCenter.default.post(name: .showAboutCommand, object: nil)
                dismissPopoverAfterSelection()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var videoStatsMenu: some View {
        Menu {
            videoStatsMenuOption(title: "Off", location: nil)
            ForEach(CaptureVideoStatsOverlayLocation.menuLocations, id: \.rawValue) { location in
                videoStatsMenuOption(title: location.menuTitle, location: location)
            }
        } label: {
            menuRow("Video Stats")
        }
        .buttonStyle(.plain)
    }

    private var lowFPSMenu: some View {
        Menu {
            Button {
                disableLowFPSWarningOverlay.toggle()
                dismissPopoverAfterSelection()
            } label: {
                if !disableLowFPSWarningOverlay {
                    Label("On", systemImage: "checkmark")
                } else {
                    Text("On")
                }
            }
            Button {
                disableLowFPSWarningOverlay.toggle()
                dismissPopoverAfterSelection()
            } label: {
                if disableLowFPSWarningOverlay {
                    Label("Off", systemImage: "checkmark")
                } else {
                    Text("Off")
                }
            }
        } label: {
            menuRow("Low FPS Warnings")
        }
        .buttonStyle(.plain)
    }

    private var previewRotationMenu: some View {
        Menu {
            ForEach(CaptureVideoPreviewRotation.allCases, id: \.rawValue) { rotation in
                previewRotationOption(rotation)
            }
        } label: {
            menuRow("Rotation")
        }
        .buttonStyle(.plain)
    }

    private var previewMirrorMenu: some View {
        Menu {
            previewMirrorOption(title: "Horizontal", mirror: .horizontal)
            previewMirrorOption(title: "Vertical", mirror: .vertical)
        } label: {
            menuRow("Mirror Image")
        }
        .buttonStyle(.plain)
    }

    private var audioBufferLengthMenu: some View {
        Menu {
            ForEach(CaptureAudioUserDefaults.bufferLengthOptions, id: \.self) { length in
                audioBufferLengthOption(length)
            }
        } label: {
            menuRow("Audio Buffer Size")
        }
        .buttonStyle(.plain)
    }

    private func menuRow(_ title: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer(minLength: 16)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func videoStatsMenuOption(title: String, location: CaptureVideoStatsOverlayLocation?) -> some View {
        let isSelected = isVideoStatsOptionSelected(location: location)
        Button {
            if let location {
                showVideoStats = true
                videoStatsLocationRawValue = location.rawValue
            } else {
                showVideoStats = false
            }
            dismissPopoverAfterSelection()
        } label: {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
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

    private func previewRotationOption(_ rotation: CaptureVideoPreviewRotation) -> some View {
        _ = previewTransformMenuRefresh
        let transform = CaptureVideoPreviewTransformUserDefaults.load(
            forDeviceID: selectedVideoDeviceUniqueID
        )
        return Button {
            CaptureVideoPreviewTransformUserDefaults.saveRotation(
                rotation,
                forDeviceID: selectedVideoDeviceUniqueID
            )
            previewTransformMenuRefresh += 1
            dismissPopoverAfterSelection()
        } label: {
            if transform.rotation == rotation {
                Label(rotation.menuTitle, systemImage: "checkmark")
            } else {
                Text(rotation.menuTitle)
            }
        }
        .disabled(selectedVideoDeviceUniqueID == nil)
    }

    private func previewMirrorOption(title: String, mirror: CaptureVideoPreviewMirrorOptions) -> some View {
        _ = previewTransformMenuRefresh
        let transform = CaptureVideoPreviewTransformUserDefaults.load(
            forDeviceID: selectedVideoDeviceUniqueID
        )
        let isSelected = transform.mirrors.contains(mirror)
        return Button {
            var mirrors = transform.mirrors
            if isSelected {
                mirrors.remove(mirror)
            } else {
                mirrors.insert(mirror)
            }
            CaptureVideoPreviewTransformUserDefaults.saveMirrors(
                mirrors,
                forDeviceID: selectedVideoDeviceUniqueID
            )
            previewTransformMenuRefresh += 1
            dismissPopoverAfterSelection()
        } label: {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
        .disabled(selectedVideoDeviceUniqueID == nil)
    }

    @ViewBuilder
    private func audioBufferLengthOption(_ length: Int) -> some View {
        let label = length == CaptureAudioUserDefaults.defaultBufferLength
            ? "\(length) (default)"
            : "\(length)"
        Button {
            capture.setAudioBufferLength(length)
            dismissPopoverAfterSelection()
        } label: {
            if capture.audioBufferLength == length {
                Label(label, systemImage: "checkmark")
            } else {
                Text(label)
            }
        }
    }

    /// Nested `Menu` actions complete after SwiftUI updates; deferring avoids fighting UIKit menu teardown
    /// and forces the settings popover (and submenu snapshots) to disappear so the next open shows fresh state.
    private func dismissPopoverAfterSelection() {
        DispatchQueue.main.async {
            dismiss()
        }
    }
}
