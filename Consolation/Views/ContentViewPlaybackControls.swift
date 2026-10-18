//
//  ContentViewPlaybackControls.swift
//  Consolation
//

import SwiftUI

extension ContentView {
    var playbackControls: some View {
        Group {
            #if os(iOS)
            HStack {
                Spacer(minLength: 0)
                playbackControlsBar
                Spacer(minLength: 0)
            }
            #else
            playbackControlsBar
            #endif
        }
        .padding(.bottom, playbackControlsBottomPadding)
        #if os(macOS)
        .offset(playbackControlsCurrentOffset)
        .onHover { isHovering in
            isPlaybackControlsHoverActive = isHovering
            if isHovering {
                cancelHoverHideTask()
                revealTransientChromeIfNeeded()
            } else {
                resetHoverTimer()
            }
        }
        #endif
    }

    /// Shared toolbar contents; macOS may offset/drag the whole bar, iOS keeps it fixed bottom-center.
    private var playbackControlsBar: some View {
        HStack(spacing: 12) {
            PlaybackToolbarIconButton(
                systemName: "power",
                accessibilityLabel: "Stop Capturing",
                iconColor: .red,
                hoverTint: .white,
                action: { capture.stopWatching() }
            )

            PlaybackToolbarDivider()

            HStack(spacing: 2) {
                PlaybackToolbarIconButton(
                    systemName: capture.isAudioMuted ? "speaker.slash.fill" : "speaker.fill",
                    accessibilityLabel: capture.isAudioMuted ? "Unmute audio" : "Mute audio",
                    iconColor: capture.isAudioMuted ? .accentColor : .white,
                    action: { capture.setAudioMuted(!capture.isAudioMuted) }
                )
                ZStack {
                    if !capture.isAudioMuted {
                        VStack(spacing: 20) {
                            Color.black.opacity(0.35)
                        }
                        .cornerRadius(14)
                        .allowsHitTesting(false)
                    }
                    Slider(
                        value: Binding(
                            get: { capture.volumeLevel },
                            set: { capture.setVolumeLevel($0) }
                        ),
                        in: 0...1,
                        onEditingChanged: handleSliderEditingChanged(_:)
                    )
                    .labelsHidden()
                    .frame(width: 120)
                    .tint(.white)
                    .disabled(capture.isAudioMuted)

                    if capture.isAudioMuted {
                        VStack(spacing: 20) {
                            Color.black.opacity(0.35)
                        }
                        .cornerRadius(14)
                        .allowsHitTesting(false)
                    }
                }
                .frame(width: 140)
                .frame(maxHeight: 28)
            }

            PlaybackToolbarDivider()

            HStack(spacing: 4) {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24)
                    .allowsHitTesting(false)
                ZStack {
                    VStack(spacing: 20) {
                        Color.black.opacity(0.35)
                    }
                    .cornerRadius(14)
                    .allowsHitTesting(false)
                    Slider(
                        value: $previewZoomLevel,
                        in: 0...100,
                        onEditingChanged: handleSliderEditingChanged(_:)
                    )
                    .labelsHidden()
                    .frame(width: 120)
                    .tint(.white)
                }
                .frame(width: 140)
                .frame(maxHeight: 28)
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24)
                    .allowsHitTesting(false)
            }
            .frame(width: 200)
            .frame(maxHeight: 28)

            #if os(macOS)
            PlaybackToolbarDivider()

            PlaybackToolbarIconButton(
                systemName: isFullscreenActive
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                accessibilityLabel: "Full Screen",
                iconColor: isFullscreenActive ? .accentColor : .white,
                action: { window?.toggleFullScreen(nil) }
            )
            #elseif os(iOS)
            PlaybackToolbarDivider()

            PlaybackToolbarMenu(
                systemName: "gearshape.fill",
                accessibilityLabel: "Settings",
                iconColor: .white,
                isPresented: $isPlaybackSettingsMenuPresented,
                onPresentedChanged: handlePlaybackSettingsMenuPresentedChanged(_:)
            ) {
                IPadSettingsMenuContent(
                    capture: capture,
                    selectedVideoDeviceUniqueID: capture.selectedVideoDeviceUniqueID
                )
            }
            .equatable()
            #endif
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        #if os(macOS)
        .background { playbackControlsDragSurface }
        #endif
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 42, style: .continuous))
        .shadow(radius: 8)
        .panelLiquidGlass(cornerRadius: 42)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { setPlaybackControlsSize(proxy.size) }
                    .onChange(of: proxy.size) { _, size in setPlaybackControlsSize(size) }
            }
        }
    }

    #if os(macOS)
    /// Drag handle for moving the bar: the gaps, padding and dividers between controls. It sits behind the
    /// controls rather than on the bar itself, so a drag that starts on a slider or button never moves the bar.
    private var playbackControlsDragSurface: some View {
        Color.clear
            .contentShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
            .gesture(playbackControlsDragGesture)
    }
    #endif

    var playbackControlsInteractionGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isPlaybackControlsInteractionActive else { return }
                isPlaybackControlsInteractionActive = true
                cancelHoverHideTask()
                revealTransientChromeIfNeeded()
            }
            .onEnded { _ in
                isPlaybackControlsInteractionActive = false
                resetHoverTimer()
            }
    }

    func handleSliderEditingChanged(_ isEditing: Bool) {
        if isEditing {
            guard !isPlaybackControlsInteractionActive else { return }
            isPlaybackControlsInteractionActive = true
            cancelHoverHideTask()
            revealTransientChromeIfNeeded()
            return
        }

        isPlaybackControlsInteractionActive = false
        resetHoverTimer()
    }

    #if os(iOS)
    func handlePlaybackSettingsMenuPresentedChanged(_ isPresented: Bool) {
        if isPresented {
            cancelHoverHideTask()
            revealTransientChromeIfNeeded()
        } else {
            resetHoverTimer()
        }
    }
    #endif

    #if os(macOS)
    var isFullscreenActive: Bool {
        window?.styleMask.contains(.fullScreen) ?? false
    }
    #endif

}

/// Hover is tracked on the circular container. The SF Symbol does not hit-test, so moving over the
/// glyph does not steal tracking from the background circle (plain `NSImageView` hover otherwise clears it).
struct PlaybackToolbarIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var iconColor: Color = .primary
    /// Hover fill uses `hoverTint.opacity(0.16)` so alpha matches other toolbar icons.
    var hoverTint: Color = Color.white
    /// Hit target and icon size; glyph uses half this point size (matches 36 → 18 on the playback bar).
    var dimension: CGFloat = 42
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    private var iconPointSize: CGFloat { dimension * 0.5 }

    var body: some View {
        Button(action: action) {
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
        .accessibilityLabel(accessibilityLabel)
    }
}

struct PlaybackToolbarDivider: View {
    var body: some View {
        Divider()
            .frame(height: 32)
    }
}
