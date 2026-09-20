//
//  CaptureMediaPermissionEducation.swift
//  Consolation
//

import AVFoundation
import Foundation
import SwiftUI

/// Which idle-state media notice to show. Uses `authorizationStatus` only — never `requestAccess`.
enum CaptureMediaPermissionNotice: Equatable {
    case none
    case notDetermined
    case deniedOrRestricted

    static func current() -> Self {
        let video = AVCaptureDevice.authorizationStatus(for: .video)
        let audio = AVCaptureDevice.authorizationStatus(for: .audio)
        if isDeniedOrRestricted(video) || isDeniedOrRestricted(audio) {
            return .deniedOrRestricted
        }
        if video == .notDetermined || audio == .notDetermined {
            return .notDetermined
        }
        return .none
    }

    private static func isDeniedOrRestricted(_ status: AVAuthorizationStatus) -> Bool {
        status == .denied || status == .restricted
    }
}

struct CaptureMediaPermissionEducationNotice: View {
    let notice: CaptureMediaPermissionNotice

    var body: some View {
        Group {
            switch notice {
            case .none:
                EmptyView()
            case .notDetermined:
                #if os(macOS)
                permissionText(
                    "You will be asked to allow Camera and Microphone access, which\n" +
                    "is required because macOS treats Capture Cards as Webcams.",
                    color: Color.white.opacity(0.75)
                )
                #else
                permissionText(
                    "You will be asked to allow Camera and Microphone access, which\n" +
                    "is required because iPad treats Capture Cards as Webcams.",
                    color: Color.white.opacity(0.75)
                )
                #endif
                StartupDivider()
            case .deniedOrRestricted:
                #if os(macOS)
                permissionText(
                    "Camera or Mic access for Consolation is disabled in Settings. Enable both under "
                        + "Privacy & Security so your capture device can be used, then restart the app.",
                    color: .red
                )
                #else
                permissionText(
                    "Camera or Mic access for Consolation is off in Settings. Enable both under "
                        + "Privacy & Security so your capture device can be used.",
                    color: .red
                )
                #endif
                StartupDivider()
            }
        }
    }

    private func permissionText(_ message: String, color: Color = .secondary) -> some View {
        Text(message)
            .font(.system(size: 15))
            .foregroundStyle(color)
            .lineSpacing(4)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}
