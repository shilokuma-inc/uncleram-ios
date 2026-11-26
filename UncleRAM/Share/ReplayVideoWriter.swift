import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo

/// リプレイ動画の音。効果音（`UncleRAM/Sounds/*.m4a`）を、出来事の時刻に合わせて 1 本の音（モノラル、44.1kHz）に重ねる
nonisolated enum ReplayAudioMixer {
    static let sampleRate = 44_100.0

    enum Failure: Error {
        case missingSound(SoundEffect)
    }

    /// - Returns: 動画の長さ分の音（-1〜1）
    static func mix(cues: [ReplaySoundCue], duration: Double, bundle: Bundle = .main) throws -> [Float] {
        var output = [Float](repeating: 0, count: Int((duration * sampleRate).rounded(.up)))
        var sources: [SoundEffect: [Float]] = [:]
        for cue in cues {
            if sources[cue.effect] == nil {
                sources[cue.effect] = try decode(cue.effect, bundle: bundle)
            }
            guard let source = sources[cue.effect], !source.isEmpty else {
                continue
            }
            add(cue, source: source, to: &output)
        }
        for index in output.indices {
            output[index] = min(1, max(-1, output[index]))
        }
        return output
    }

    /// 効果音をモノラル・44.1kHz の値に読み込む（AAC の頭の遅れと終わりの余りは AVAudioFile が取り除く）
    static func decode(_ effect: SoundEffect, bundle: Bundle = .main) throws -> [Float] {
        guard let url = bundle.url(forResource: effect.rawValue, withExtension: "m4a") else {
            throw Failure.missingSound(effect)
        }
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            return []
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else {
            return []
        }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        guard format.sampleRate != sampleRate, format.sampleRate > 0 else {
            return samples
        }
        // 44.1kHz でないときは、いちばん近い値で詰め直す（同梱の音はどれも 44.1kHz）
        let ratio = format.sampleRate / sampleRate
        let count = Int(Double(samples.count) / ratio)
        return (0..<count).map { samples[min(samples.count - 1, Int(Double($0) * ratio))] }
    }

    private static func add(_ cue: ReplaySoundCue, source: [Float], to output: inout [Float]) {
        let start = Int((cue.start * sampleRate).rounded())
        let end: Int = if let stop = cue.stop {
            Int(((stop + cue.fadeOut) * sampleRate).rounded())
        } else {
            start + source.count
        }
        guard start < output.count else {
            return
        }
        let base = cue.level * cue.effect.mixLevel
        for index in max(0, start)..<min(end, output.count) {
            let time = Double(index) / sampleRate
            let offset = index - start
            // ループの音（プロペラ）は、止めるまで頭から繰り返す
            let sample = source[offset % source.count]
            output[index] += sample * base * gain(of: cue, at: time)
        }
    }

    /// フェードと、途中で大きさを変える分の倍率
    private static func gain(of cue: ReplaySoundCue, at time: Double) -> Float {
        var gain = 1.0
        if cue.fadeIn > 0 {
            gain *= min(1, max(0, (time - cue.start) / cue.fadeIn))
        }
        if let change = cue.levelChange, time > change.time, cue.level > 0 {
            let progress = change.duration > 0 ? min(1, (time - change.time) / change.duration) : 1
            let target = Double(change.level / cue.level)
            gain *= 1 + (target - 1) * progress
        }
        if let stop = cue.stop, time > stop {
            gain *= cue.fadeOut > 0 ? max(0, 1 - (time - stop) / cue.fadeOut) : 0
        }
        return Float(gain)
    }
}

/// 1 コマの絵（ImageRenderer で描いたもの）。描いたあとは変えないので、書き出しの係へ渡せる
nonisolated struct ReplayFrameImage: @unchecked Sendable {
    let cgImage: CGImage
}

/// リプレイ動画を AVAssetWriter で書き出す（H.264 の 1080 × 1920・30fps と、AAC の音）。
///
/// 絵は 1 コマずつ受け取って、すぐに書いて手放す（全部のコマをメモリに持たない）。音は先に重ねておき、
/// 絵と交互になるよう、絵の時刻より少し先まで書く（AVAssetWriter は、片方だけが先に進みすぎると待つため）
actor ReplayVideoEncoder {
    enum Failure: Error {
        case cannotCreateWriter
        case cannotAppend
        case failed(String)
    }

    static let width = 1_080
    static let height = 1_920
    /// 絵の時刻より先に書いておく音の長さ（秒）
    static let audioLead = 0.5
    /// 音を 1 回に書く長さ（フレーム数。約 0.09 秒）
    static let audioChunk = 4_096
    /// 書き手が受け取れるようになるのを待つ上限。越えたら止める（進み具合が止まったままにならないように）
    static let waitLimit = Duration.seconds(10)

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput
    private let audioFormat: CMAudioFormatDescription
    private let audio: [Float]
    private var audioCursor = 0
    private let framesPerSecond: Int32
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    init(url: URL, audio: [Float], framesPerSecond: Int = ReplayTimeline.framesPerSecond) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        // 投稿先が頭から読めるよう、目次（moov）を前に置く
        writer.shouldOptimizeForNetworkUse = true
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: Self.videoSettings(framesPerSecond: framesPerSecond))
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Self.width,
            kCVPixelBufferHeightKey as String: Self.height,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: ReplayAudioMixer.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000
        ])
        audioInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
            throw Failure.cannotCreateWriter
        }
        writer.add(videoInput)
        writer.add(audioInput)
        guard let audioFormat = Self.makeAudioFormat(), writer.startWriting() else {
            throw Failure.failed(writer.error?.localizedDescription ?? "startWriting")
        }
        writer.startSession(atSourceTime: .zero)
        self.writer = writer
        self.videoInput = videoInput
        self.adaptor = adaptor
        self.audioInput = audioInput
        self.audioFormat = audioFormat
        self.audio = audio
        self.framesPerSecond = Int32(framesPerSecond)
    }

    /// H.264（High）、6Mbps。色は BT.709 の印を付ける
    private static func videoSettings(framesPerSecond: Int) -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                // コマの並べ替え（B フレーム）をしない。符号化の係が先のコマを溜めないので、手元に持つ絵が少なくて済む
                AVVideoAllowFrameReorderingKey: false,
                AVVideoExpectedSourceFrameRateKey: framesPerSecond,
                AVVideoMaxKeyFrameIntervalKey: framesPerSecond * 2
            ]
        ]
    }

    /// 重ねた音の形（モノラル・44.1kHz・32 ビットの浮動小数）
    private static func makeAudioFormat() -> CMAudioFormatDescription? {
        var description = AudioStreamBasicDescription(
            mSampleRate: ReplayAudioMixer.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &description,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &format
        )
        return format
    }

    /// `index` 番目のコマを書く
    func append(_ image: ReplayFrameImage, at index: Int) async throws {
        let time = CMTime(value: CMTimeValue(index), timescale: framesPerSecond)
        let deadline = ContinuousClock.now + Self.waitLimit
        while true {
            try checkStatus()
            guard ContinuousClock.now < deadline else {
                throw Failure.failed("timed out waiting for the video input")
            }
            try appendAudio(until: time.seconds + Self.audioLead)
            if videoInput.isReadyForMoreMediaData {
                break
            }
            // 絵を受け取れないのは、音がもっと先まで要るとき（書き手は自分の区切りで交互に並べる）。音を 1 回分先に書いて、もう一度見る
            if try !appendAudioChunk() {
                try await Task.sleep(for: .milliseconds(2))
            }
        }
        guard let pool = adaptor.pixelBufferPool else {
            throw Failure.cannotAppend
        }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        guard let buffer else {
            throw Failure.cannotAppend
        }
        draw(image.cgImage, into: buffer)
        guard adaptor.append(buffer, withPresentationTime: time) else {
            throw Failure.failed(writer.error?.localizedDescription ?? "append")
        }
    }

    /// 残りの音を書いて、`frameCount` コマの長さで閉じる
    func finish(frameCount: Int) async throws {
        videoInput.markAsFinished()
        let deadline = ContinuousClock.now + Self.waitLimit
        while audioCursor < audio.count {
            try checkStatus()
            guard ContinuousClock.now < deadline else {
                throw Failure.failed("timed out waiting for the audio input")
            }
            try appendAudio(until: .infinity)
            if audioCursor < audio.count {
                try await Task.sleep(for: .milliseconds(2))
            }
        }
        audioInput.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frameCount), timescale: framesPerSecond))
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
        guard writer.status == .completed else {
            throw Failure.failed(writer.error?.localizedDescription ?? "finishWriting")
        }
    }

    /// 書きかけで止める（書きかけのファイルは、呼んだ側が消す）
    func cancel() {
        if writer.status == .writing {
            writer.cancelWriting()
        }
    }

    private func checkStatus() throws {
        if writer.status == .failed || writer.status == .cancelled {
            throw Failure.failed(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)")
        }
    }

    /// 音を `seconds` まで、書ける分だけ書く
    private func appendAudio(until seconds: Double) throws {
        let limit = seconds.isFinite ? min(audio.count, Int(seconds * ReplayAudioMixer.sampleRate)) : audio.count
        while audioCursor < limit, try appendAudioChunk() {}
    }

    /// 音を 1 回分（`audioChunk`）書く。書き終えている・今は受け取れないときは false
    private func appendAudioChunk() throws -> Bool {
        guard audioCursor < audio.count, audioInput.isReadyForMoreMediaData else {
            return false
        }
        let count = min(Self.audioChunk, audio.count - audioCursor)
        guard let sample = makeAudioSample(from: audioCursor, count: count), audioInput.append(sample) else {
            throw Failure.failed(writer.error?.localizedDescription ?? "append audio")
        }
        audioCursor += count
        return true
    }

    private func makeAudioSample(from start: Int, count: Int) -> CMSampleBuffer? {
        let length = count * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: length,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: length,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &block
        )
        guard let block else {
            return nil
        }
        let status = audio.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else {
                return -1
            }
            return CMBlockBufferReplaceDataBytes(
                with: base + start * MemoryLayout<Float>.size,
                blockBuffer: block,
                offsetIntoDestination: 0,
                dataLength: length
            )
        }
        guard status == noErr else {
            return nil
        }
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: audioFormat,
            sampleCount: count,
            presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(ReplayAudioMixer.sampleRate)),
            packetDescriptions: nil,
            sampleBufferOut: &sample
        )
        return sample
    }

    private func draw(_ image: CGImage, into buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: Self.width, height: Self.height))
    }
}
