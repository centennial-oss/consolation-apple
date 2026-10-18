//
//  ContentViewStartScreen.swift
//  Consolation
//

import SwiftUI

struct ContentViewStartScreen: View {
    let capture: CaptureSessionManager
    let showStatusLine: Bool
    @Binding var isShowingAbout: Bool
    @Binding var isShowingHelp: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            startScreenContent
            headerUtilityButtons
                .padding(.trailing, 6)
                .padding(.bottom, 6)
        }
    }

    private var startScreenContent: some View {
        VStack {
            VStack(spacing: 16) {
                header
                StartupDivider()
                statusLine
                mediaPermissionNotice
                deviceControls
                startButton
            }
            .frame(minWidth: 560, maxWidth: 560)
        }
        .frame(minWidth: 560, maxWidth: 560)
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppIconImage()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(AppIdentifier.name)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)

                Text("v" + BuildInfo.version)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if showStatusLine {
            CaptureStatusLine(
                state: capture.state,
                hasUSBVideoCaptureDevice: !capture.usbCaptureDeviceEntries.isEmpty,
                usbVideoCaptureDeviceName: capture.primaryUSBVideoCaptureDisplayName,
                hasAnyVideoDevice: !capture.hasNoVideoDevices,
                statusMessage: capture.statusMessage
            )
        }
    }

    @ViewBuilder
    private var mediaPermissionNotice: some View {
        if capture.mediaPermissionNotice != .none, capture.state != .requestingPermission {
            CaptureMediaPermissionEducationNotice(notice: capture.mediaPermissionNotice)
        }
    }

    @ViewBuilder
    private var deviceControls: some View {
        if !capture.hasNoVideoDevices {
            ContentViewConnectPanel(capture: capture)
        }
    }

    private var startButton: some View {
        Group {
            StartupDivider()
            ContentViewStartWatchingButton(capture: capture)
        }
    }

    private var headerUtilityButtons: some View {
        HStack(spacing: 8) {
            ContentViewHeaderUtilityButton(title: "Help", systemImage: "questionmark.circle") {
                isShowingHelp = true
            }

            ContentViewHeaderUtilityButton(title: "About", systemImage: "info.circle") {
                isShowingAbout = true
            }
        }
    }
}

struct StartupDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.white.opacity(0.42))
    }
}
