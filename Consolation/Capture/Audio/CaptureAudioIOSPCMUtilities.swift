//
//  CaptureAudioIOSPCMUtilities.swift
//  Consolation
//

#if os(iOS)
import AVFoundation
import AudioToolbox
import Foundation
import AVFAudio

enum CaptureAudioIOSPCMUtilities {
    nonisolated static func normalizedFloatFormat(source: AVAudioFormat) -> AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: source.sampleRate,
            channels: source.channelCount,
            interleaved: false
        )!
    }

    nonisolated static func makePlaybackBuffer(
        sampleBuffer: CMSampleBuffer,
        frameCount: CMItemCount,
        sourceFormat: AVAudioFormat,
        playFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else { return nil }
        sourceBuffer.frameLength = AVAudioFrameCount(frameCount)

        let copyStatus = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: sourceBuffer.mutableAudioBufferList
        )
        guard copyStatus == noErr else { return nil }

        if formatsMatchForDirectUse(sourceFormat, playFormat) {
            return sourceBuffer
        }

        guard let out = AVAudioPCMBuffer(
            pcmFormat: playFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else { return nil }
        out.frameLength = AVAudioFrameCount(frameCount)

        guard let converter = AVAudioConverter(from: sourceFormat, to: playFormat) else { return nil }
        var error: NSError?
        var fedSource = false
        converter.convert(to: out, error: &error) { _, outStatus in
            if fedSource {
                outStatus.pointee = .noDataNow
                return nil
            }
            fedSource = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }
        return error == nil ? out : nil
    }

    nonisolated static func formatsArePlaybackCompatible(
        _ lhs: AVAudioFormat?,
        _ rhs: AVAudioFormat
    ) -> Bool {
        guard let lhs else { return false }
        return formatsMatchForDirectUse(lhs, rhs)
    }

    nonisolated private static func formatsMatchForDirectUse(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.commonFormat == rhs.commonFormat
            && lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.isInterleaved == rhs.isInterleaved
    }
}
#endif
