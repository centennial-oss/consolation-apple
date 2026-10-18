//
//  ContentViewConnectPanel.swift
//  Consolation
//

import AVFoundation
import SwiftUI

struct ContentViewConnectPanel: View {
    let capture: CaptureSessionManager
    @State private var compatibilityIssueForSheet: CaptureDeviceCompatibilityIssue?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            deviceMenuPill
            resolutionMenuPill
        }
        .frame(maxWidth: 320)
        .sheet(item: $compatibilityIssueForSheet) { issue in
            CaptureDeviceCompatibilityIssueView(issue: issue)
        }
    }

    private var deviceMenuPill: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Device")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            HStack(spacing: 8) {
                Menu {
                    Section("Video Capture Cards") {
                        if capture.usbCaptureDeviceEntries.isEmpty {
                            Text("     No Capture Cards Detected")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(capture.usbCaptureDeviceEntries) { entry in
                                deviceMenuButton(entry: entry)
                            }
                        }
                    }
                    if !capture.cameraDeviceEntries.isEmpty {
                        Section("Cameras") {
                            ForEach(capture.cameraDeviceEntries) { entry in
                                deviceMenuButton(entry: entry)
                            }
                        }
                    }
                } label: {
                    ConnectPanelPillLabel(value: capture.connectPanelDevicePrimaryLabel())
                }
                .disabled(capture.hasNoVideoDevices || isConnecting)
                .buttonStyle(.plain)

                if let issue = selectedDeviceCompatibilityIssue {
                    Button {
                        compatibilityIssueForSheet = issue
                    } label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.yellow)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Capture card compatibility warning")
                }
            }
        }
    }

    private var selectedDeviceCompatibilityIssue: CaptureDeviceCompatibilityIssue? {
        guard let id = capture.selectedVideoDeviceUniqueID,
              let device = AVCaptureDevice(uniqueID: id)
        else { return nil }
        return CaptureDeviceCompatibilityIssues.issue(for: device)
    }

    private func deviceMenuButton(entry: CaptureDeviceSummary) -> some View {
        Button {
            capture.selectVideoDevice(uniqueID: entry.id)
        } label: {
            if entry.id == capture.selectedVideoDeviceUniqueID {
                Label(entry.localizedName, systemImage: "checkmark")
            } else {
                Text(entry.localizedName)
            }
        }
    }

    @ViewBuilder
    private var resolutionMenuPill: some View {
        if let id = capture.selectedVideoDeviceUniqueID,
           let device = AVCaptureDevice(uniqueID: id) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Resolution")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                resolutionMenu(for: device)
                    .disabled(capture.hasNoVideoDevices || isConnecting)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Resolution")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                ConnectPanelPillLabel(value: "—")
                    .opacity(0.45)
                    .allowsHitTesting(false)
            }
        }
    }

    private func resolutionMenu(for device: AVCaptureDevice) -> some View {
        let options = CaptureFormatSelector.resolutionMenuOptions(device: device)
        return Menu {
            ForEach(platformMenuOrder(options)) { resolution in
                Menu {
                    ForEach(platformMenuOrder(resolution.frameRatesDescending), id: \.self) { fps in
                        formatMenuButton(
                            device: device,
                            resolution: resolution,
                            fps: fps
                        )
                    }
                } label: {
                    Text(CaptureVideoFormatDisplayStrings.resolutionLabel(
                        width: resolution.width,
                        height: resolution.height
                    ))
                }
            }
        } label: {
            ConnectPanelPillLabel(value: capture.connectPanelResolutionLabel())
        }
        .buttonStyle(.plain)
    }

    private func formatMenuButton(
        device: AVCaptureDevice,
        resolution: CaptureVideoFormatMenuResolution,
        fps: Double
    ) -> some View {
        Button {
            capture.selectVideoFormat(
                width: resolution.width,
                height: resolution.height,
                frameRate: fps
            )
        } label: {
            if isFormatMenuSelectionActive(
                device: device,
                width: resolution.width,
                height: resolution.height,
                fps: fps
            ) {
                Label(formatMenuRowTitle(fps: fps), systemImage: "checkmark")
            } else {
                Text(formatMenuRowTitle(fps: fps))
            }
        }
    }

    private func isFormatMenuSelectionActive(
        device: AVCaptureDevice,
        width: Int,
        height: Int,
        fps: Double
    ) -> Bool {
        guard let eff = CaptureFormatSelector.effectiveFormatForDisplay(
            device: device,
            preferences: capture.formatPreferences
        ) else {
            return false
        }
        return eff.width == width
            && eff.height == height
            && abs(eff.frameRate - fps) < 0.51
    }

    private func formatMenuRowTitle(fps: Double) -> String {
        "\(Int(round(fps))) fps"
    }

    private func platformMenuOrder<Value>(_ values: [Value]) -> [Value] {
        #if os(iOS)
        values.reversed()
        #else
        values
        #endif
    }

    private var isConnecting: Bool {
        capture.state == .requestingPermission
    }
}

// MARK: - Pill chrome

private struct ConnectPanelPillLabel: View {
    let value: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .contentShape(Capsule())
    }
}

private struct CaptureDeviceCompatibilityIssueView: View {
    @Environment(\.dismiss) private var dismiss
    let issue: CaptureDeviceCompatibilityIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.title)
                Text("Capture Card Compatibility")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 16)

            Text(
                "This capture card has known compatibility issues with \(issue.platform.rawValue).\n" +
                "Performance may be below the advertised resolution or frame rate settings."
            )
            .font(.system(size: 16))
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                Text("About Your Capture Card")
                    .font(.system(size: 16, weight: .semibold))

                Text(issue.summary)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 16))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 24)
            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .font(.system(size: 16))
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 630)
    }
}
