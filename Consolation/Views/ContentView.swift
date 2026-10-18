import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct ContentView: View {
    let capture: CaptureSessionManager
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @State var window: NSWindow?
    #endif
    @State var isUIHidden = false
    @State var hoverTask: Task<Void, Never>?
    @State var playbackControlsOffset = CGSize.zero
    @State var playbackControlsSize = CGSize.zero
    @State var previewSize = CGSize.zero
    @State private var isShowingAbout = false
    @State private var isShowingHelp = false
    @State var isPlaybackControlsInteractionActive = false
    @State var isPlaybackControlsHoverActive = false
    #if os(iOS)
    @State var isPlaybackSettingsMenuPresented = false
    #endif
    #if os(macOS)
    @State var isAppMenuTracking = false
    #endif
    @GestureState private var playbackControlsDragOffset = CGSize.zero
    @State var previewZoomLevel = 0.0
    @State var previewPanOffset = CGSize.zero
    @State var previewPanDragLastTranslation = CGSize.zero
    @AppStorage(CaptureVideoStatsUserDefaults.showStatsKey) var showVideoStats = false
    @AppStorage(CaptureVideoStatsUserDefaults.statsLocationKey) var videoStatsLocationRawValue =
        CaptureVideoStatsUserDefaults.defaultLocation
    @AppStorage(CaptureVideoStatsUserDefaults.disableLowFPSWarningKey) var disableLowFPSWarningOverlay = false
    @State var isShowingMaxFPSInfo = false
    #if os(macOS)
    @AppStorage(ViewerWindowUserDefaults.isAlwaysOnTopKey) var isViewerWindowAlwaysOnTop = false
    #endif
    #if DEBUG
    @State private var showDeviceDebug = false
    #endif
    var body: some View {
        GeometryReader { proxy in
            previewStack(in: proxy)
        }
        .frame(minWidth: 640, minHeight: 480)
        .background {
            #if os(macOS)
            WindowAccessor(window: $window)
            #endif
        }
        #if os(macOS)
        .onChange(of: window) { _, _ in
            updateAlwaysOnTopWindowLevel()
        }
        .onChange(of: isViewerWindowAlwaysOnTop) { _, _ in
            updateAlwaysOnTopWindowLevel()
        }
        #endif
        .onChange(of: capture.videoSize) { _, size in
            #if os(macOS)
            updateWindowAspectRatio(for: size)
            #endif
        }
        .onChange(of: capture.state) { oldState, state in
            PlaybackDisplayWakeLock.setActive(state == .running)
            if state != .running {
                cancelAutoHideChrome()
            }
            if oldState != .running, state == .running {
                #if os(macOS)
                loadSavedPlaybackControlsPosition()
                #endif
                resetHoverTimer()
            }
            #if os(macOS)
            if state == .running {
                updateWindowAspectRatio(for: capture.videoSize)
            } else {
                resetWindowAspectRatio()
            }
            #endif
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
            guard let exited = notification.object as? NSWindow,
                  let window,
                  exited === window,
                  capture.state == .running
            else { return }
            // Defer until after AppKit restores the window frame from the pre-full-screen session.
            DispatchQueue.main.async {
                updateWindowAspectRatio(for: capture.videoSize)
            }
        }
        #endif
        #if os(macOS)
        .onContinuousHover(coordinateSpace: .local) { _ in
            resetHoverTimer()
        }
        #endif
        #if os(iOS)
        .simultaneousGesture(
            TapGesture().onEnded {
                guard capture.state == .running else { return }
                // Defer so a tap that dismisses the settings popover runs after `isPlaybackSettingsMenuPresented`
                // updates; otherwise `resetHoverTimer()` can see the menu as still open and skip scheduling hide.
                DispatchQueue.main.async {
                    resetHoverTimer()
                }
            }
        )
        #endif
        .onAppear {
            PlaybackDisplayWakeLock.setActive(false)
            resetHoverTimer()
            capture.refreshMediaCaptureAuthorizationStatuses()
            loadPreviewZoomLevelForSelectedDevice()
        }
        .onDisappear {
            PlaybackDisplayWakeLock.setActive(false)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                capture.refreshMediaCaptureAuthorizationStatuses()
            }
        }
        .onChange(of: capture.selectedVideoDeviceUniqueID) { _, _ in
            loadPreviewZoomLevelForSelectedDevice()
        }
        .onChange(of: previewZoomLevel) { _, newValue in
            savePreviewZoomLevel(newValue)
            if newValue == 0 { previewPanOffset = .zero }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .playbackSizeCommand)) { notification in
            guard let scale = notification.object as? CGFloat else { return }
            resizeWindowToPlaybackScale(scale)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            isAppMenuTracking = true
            cancelHoverHideTask()
            revealTransientChromeIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            isAppMenuTracking = false
            resetHoverTimer()
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .showAboutCommand)) { _ in
            isShowingAbout = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showHelpCommand)) { _ in
            isShowingHelp = true
        }
        .sheet(isPresented: $isShowingAbout) {
            AboutConsolationView {
                isShowingAbout = false
            }
            #if os(macOS)
            .interactiveDismissDisabled()
            #endif
        }
        .sheet(isPresented: $isShowingHelp) {
            HelpConsolationView {
                isShowingHelp = false
            }
            #if os(macOS)
            .interactiveDismissDisabled()
            #endif
        }
        .sheet(isPresented: $isShowingMaxFPSInfo) { MaxFPSWarningInfoView() }
        .background {
            Button("") {
                if capture.state == .running {
                    capture.setAudioMuted(!capture.isAudioMuted)
                }
            }
            .keyboardShortcut("m", modifiers: [])
            .hidden()
        }
        #if os(macOS)
        .background {
            macOSHiddenPlaybackShortcuts
        }
        #endif
        #if DEBUG
        .sheet(isPresented: $showDeviceDebug) {
            CaptureDeviceDebugView()
        }
        .background {
            Button("") { showDeviceDebug = true }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .hidden()
        }
        #endif
    }
}
extension ContentView {
    @ViewBuilder
    fileprivate func previewStack(in proxy: GeometryProxy) -> some View {
        ZStack {
            viewerBackground

            // IMPT: Keep this preview view mounted even while idle. On macOS, `CaptureVideoPreview`
            // owns the `AVCaptureVideoPreviewLayer`; creating/attaching that layer only after
            // the session starts caused UVC capture devices to fall back to ~25 FPS. The stable
            // sequence is: preview layer exists, layer has the session, then the session starts.
            captureVideoPreview

            if shouldShowStatsOverlay, let statsLabel = videoStatsLabel {
                statsOverlay(statsLabel)
            }

            if shouldShowMaxFPSWarning, let label = maxFPSWarningLabel { maxFPSWarningOverlay(label) }

            if !isUIHidden {
                viewerChrome
                    .transition(.opacity)
            }
        }
        .onAppear { setPreviewSize(proxy.size) }
        .onChange(of: proxy.size) { _, size in setPreviewSize(size) }
    }

    @ViewBuilder
    var viewerBackground: some View {
        if capture.state == .running {
            Color.black
                .ignoresSafeArea()
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.55, green: 0.02, blue: 0.45),
                    Color(red: 0.28, green: 0.01, blue: 0.19),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    var viewerChrome: some View {
        VStack {
            Spacer()

            if statusRequiresInteraction {
                startScreen
            }

            Spacer()

            if capture.state == .running {
                playbackControls
            }
        }
    }

    var startScreen: some View {
        ContentViewStartScreen(
            capture: capture,
            showStatusLine: shouldShowStatusLine,
            isShowingAbout: $isShowingAbout,
            isShowingHelp: $isShowingHelp
        )
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
            .shadow(radius: 10)
            .panelLiquidGlass(cornerRadius: 16)
            .environment(\.colorScheme, .dark)
    }

    var statusRequiresInteraction: Bool {
        switch capture.state {
        case .running: return false
        default: return true
        }
    }

    var playbackControlsCurrentOffset: CGSize {
        clampedPlaybackControlsOffset(CGSize(
            width: playbackControlsOffset.width + playbackControlsDragOffset.width,
            height: playbackControlsOffset.height + playbackControlsDragOffset.height
        ))
    }

    var playbackControlsDragGesture: some Gesture {
        // Global space: the gesture lives inside the bar it moves, so a local translation would chase itself.
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .updating($playbackControlsDragOffset) { value, state, _ in
                state = value.translation
            }
            .onChanged { _ in
                guard !isPlaybackControlsInteractionActive else { return }
                isPlaybackControlsInteractionActive = true
                cancelHoverHideTask()
                revealTransientChromeIfNeeded()
            }
            .onEnded { value in
                playbackControlsOffset = clampedPlaybackControlsOffset(CGSize(
                    width: playbackControlsOffset.width + value.translation.width,
                    height: playbackControlsOffset.height + value.translation.height
                ))
                PlaybackControlsUserDefaults.savePosition(playbackControlsOffset)
                isPlaybackControlsInteractionActive = false
                resetHoverTimer()
            }
    }

    var playbackControlsBottomPadding: CGFloat { 24 }

    func setPreviewSize(_ size: CGSize) {
        guard previewSize != size else { return }
        previewSize = size
        clampPlaybackControlsToPreview()
    }

    func setPlaybackControlsSize(_ size: CGSize) {
        guard playbackControlsSize != size else { return }
        playbackControlsSize = size
        clampPlaybackControlsToPreview()
    }

    func clampPlaybackControlsToPreview() {
        playbackControlsOffset = clampedPlaybackControlsOffset(playbackControlsOffset)
    }

    func loadSavedPlaybackControlsPosition() {
        guard let position = PlaybackControlsUserDefaults.loadPosition() else {
            playbackControlsOffset = .zero
            return
        }

        playbackControlsOffset = clampedPlaybackControlsOffset(position)
    }

    func clampedPlaybackControlsOffset(_ offset: CGSize) -> CGSize {
        guard previewSize.width > 0,
              previewSize.height > 0,
              playbackControlsSize.width > 0,
              playbackControlsSize.height > 0
        else {
            return offset
        }

        let horizontalLimit = max(0, (previewSize.width - playbackControlsSize.width) / 2)
        let maximumY = playbackControlsBottomPadding
        let minimumY = min(0, playbackControlsSize.height + playbackControlsBottomPadding - previewSize.height)

        return CGSize(
            width: min(max(offset.width, -horizontalLimit), horizontalLimit),
            height: min(max(offset.height, minimumY), maximumY)
        )
    }

    /// **Space** / **K**: stop while running; start when idle (same rules as the Start Watching button).
    func handleSpaceOrKPlaybackShortcut() {
        if capture.state == .running {
            capture.stopWatching()
        } else if capture.canStartWatching, capture.state != .requestingPermission {
            Task { await capture.startWatching() }
        }
    }

}
