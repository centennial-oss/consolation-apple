//
//  ConsolationApp.swift
//  Consolation
//
//  Created by James Ranson on 4/12/26.
//

import SwiftUI

#if os(macOS)
import AppKit

/// Single-window viewer: strip **Format**, disable window tabbing.
/// SwiftUI may rebuild `mainMenu`; observe and strip again.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Hides **View ▸ Show Tab Bar** / **Show All Tabs** for the whole app (single-window viewer).
        NSWindow.allowsAutomaticWindowTabbing = false
    }
}
#endif

@main
struct ConsolationApp: App {
    @State private var captureSession = CaptureSessionManager()
    @State private var previewTransformMenuRevision = 0

    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #elseif os(iOS)
    @UIApplicationDelegateAdaptor(IOSAppOrientationDelegate.self) var iosOrientationDelegate
    #endif

    init() {
        AppIdentifier.logBundleIdentifier()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(capture: captureSession)
        }
        #if os(iOS)
        .windowResizability(.contentMinSize)
        #endif
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
        .commands {
            ConsolationCommands(
                capture: captureSession,
                previewTransformMenuRevision: previewTransformMenuRevision
            ) {
                previewTransformMenuRevision += 1
            }
        }
    }
}
