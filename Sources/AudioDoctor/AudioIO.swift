import AVFoundation
import Foundation

enum AudioIO {
    static func loadChannels(url: URL) throws -> (channels: [[Float]], sampleRate: Float, sourceFormat: AVAudioFormat) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "AudioDoctor", code: 1, userInfo: [NSLocalizedDescriptionKey: "音频文件为空或无法读取"])
        }
        try file.read(into: buffer)
        guard let channelData = buffer.floatChannelData else {
            throw NSError(domain: "AudioDoctor", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法读取音频采样数据"])
        }
        var channels: [[Float]] = []
        for channel in 0..<Int(format.channelCount) {
            let pointer = channelData[channel]
            channels.append(Array(UnsafeBufferPointer(start: pointer, count: Int(buffer.frameLength))))
        }
        return (channels, Float(format.sampleRate), format)
    }

    static func write(channels: [[Float]], sampleRate: Float, url: URL, bitDepth: Int) throws {
        let channelCount = max(1, channels.count)
        let format: AVAudioFormat?
        if channelCount > 2 {
            // CoreAudio requires a channel layout beyond stereo. Keep 5.1 in the
            // WAV/ITU order used by AudioProcessor, and mark AmbiX as ACN/SN3D.
            let layoutTag: AudioChannelLayoutTag
            switch channelCount {
            case 4: layoutTag = kAudioChannelLayoutTag_HOA_ACN_SN3D | 4
            case 6: layoutTag = kAudioChannelLayoutTag_MPEG_5_1_A
            default: layoutTag = kAudioChannelLayoutTag_DiscreteInOrder | AudioChannelLayoutTag(channelCount)
            }
            format = AVAudioChannelLayout(layoutTag: layoutTag).flatMap {
                AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), interleaved: false, channelLayout: $0)
            }
        } else {
            format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(sampleRate),
                channels: AVAudioChannelCount(channelCount),
                interleaved: false
            )
        }
        guard let format else {
            throw NSError(domain: "AudioDoctor", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法创建输出音频格式"])
        }
        let frameCount = channels.map(\.count).min() ?? 0
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            throw NSError(domain: "AudioDoctor", code: 4, userInfo: [NSLocalizedDescriptionKey: "没有可写入的音频数据"])
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        for channel in 0..<channelCount {
            if let destination = buffer.floatChannelData?[channel], channels.indices.contains(channel) {
                let samples = Array(channels[channel].prefix(frameCount))
                samples.withUnsafeBufferPointer { source in
                    if let base = source.baseAddress {
                        destination.update(from: base, count: samples.count)
                    }
                }
            }
        }
        var settings: [String: Any] = [
            AVFormatIDKey: url.pathExtension.lowercased() == "aiff" || url.pathExtension.lowercased() == "aif" ? kAudioFormatLinearPCM : kAudioFormatLinearPCM,
            AVSampleRateKey: Double(sampleRate),
            AVNumberOfChannelsKey: channelCount,
            AVLinearPCMBitDepthKey: bitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: url.pathExtension.lowercased() == "aiff" || url.pathExtension.lowercased() == "aif"
        ]
        if channelCount > 2 {
            if let layoutPointer = format.channelLayout?.layout {
                settings[AVChannelLayoutKey] = Data(
                    bytes: layoutPointer,
                    count: MemoryLayout<AudioChannelLayout>.size
                )
            }
        }
        try? FileManager.default.removeItem(at: url)
        let output = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try output.write(from: buffer)
    }
}
