// 効果音を、取ってきた元の音（Freesound の CC0）から編集して書き出す。`Tools/sounds/make_sounds.py` から呼ぶ。
//
//   swiftc -O Tools/sounds/edit.swift -o /tmp/edit_sounds
//   /tmp/edit_sounds <出力のフォルダ> <名前>=<元の音のパス> …
//
// 出力は 44.1kHz・モノラルの float の CAF（afconvert で AAC にする前の形）。
// どの音も同じ作り方になるよう、切り出す位置・フェード・音量は、ここにすべて数値で書く（耳で決めた値）。
// 元の音はハッシュを固定して取ってくるので、同じ数値なら同じ音になる。

import AVFoundation
import Foundation

let sampleRate = 44_100.0

struct Sound {
    var samples: [Float]

    var duration: Double {
        Double(samples.count) / sampleRate
    }

    static func silence(_ seconds: Double) -> Self {
        Self(samples: [Float](repeating: 0, count: frames(seconds)))
    }

    static func frames(_ seconds: Double) -> Int {
        Int((seconds * sampleRate).rounded())
    }

    /// 読み込んで、モノラル（左右の平均）・44.1kHz にする
    static func load(_ path: String) -> Self {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        } catch {
            fatalError("読み込めません: \(path) \(error)")
        }
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            fatalError("読み込めません: \(path)")
        }
        do {
            try file.read(into: buffer)
        } catch {
            fatalError("読み込めません: \(path) \(error)")
        }
        guard let channels = buffer.floatChannelData else {
            fatalError("float で読めません: \(path)")
        }
        let count = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        var mono = [Float](repeating: 0, count: count)
        for channel in 0..<channelCount {
            for frame in 0..<count {
                mono[frame] += channels[channel][frame] / Float(channelCount)
            }
        }
        return Self(samples: resample(mono, from: format.sampleRate))
    }

    /// サンプリング周波数を 44.1kHz にそろえる（AVAudioConverter）
    private static func resample(_ samples: [Float], from rate: Double) -> [Float] {
        guard rate != sampleRate else {
            return samples
        }
        guard let input = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let output = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let converter = AVAudioConverter(from: input, to: output),
              let source = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: AVAudioFrameCount(samples.count)),
              let destination = AVAudioPCMBuffer(
                  pcmFormat: output,
                  frameCapacity: AVAudioFrameCount(Double(samples.count) * sampleRate / rate) + 4_096
              ) else {
            fatalError("サンプリング周波数を変えられません")
        }
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        source.frameLength = source.frameCapacity
        samples.withUnsafeBufferPointer { pointer in
            source.floatChannelData?[0].update(from: pointer.baseAddress!, count: samples.count)
        }
        var delivered = false
        var error: NSError?
        converter.convert(to: destination, error: &error) { _, status in
            if delivered {
                status.pointee = .endOfStream
                return nil
            }
            delivered = true
            status.pointee = .haveData
            return source
        }
        if let error {
            fatalError("サンプリング周波数を変えられません: \(error)")
        }
        guard let channel = destination.floatChannelData?[0] else {
            fatalError("サンプリング周波数を変えられません")
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(destination.frameLength)))
    }

    func slice(_ start: Double, _ end: Double) -> Self {
        let lower = max(0, Self.frames(start))
        let upper = min(samples.count, Self.frames(end))
        return Self(samples: Array(samples[lower..<upper]))
    }

    /// 頭と終わりを、余弦の形でなめらかに出し入れする
    func faded(in fadeIn: Double = 0.005, out fadeOut: Double = 0.005) -> Self {
        var result = samples
        let inFrames = min(result.count, Self.frames(fadeIn))
        for frame in 0..<inFrames {
            result[frame] *= Float(0.5 - 0.5 * cos(Double.pi * Double(frame) / Double(inFrames)))
        }
        let outFrames = min(result.count, Self.frames(fadeOut))
        for frame in 0..<outFrames {
            let index = result.count - 1 - frame
            result[index] *= Float(0.5 - 0.5 * cos(Double.pi * Double(frame) / Double(outFrames)))
        }
        return Self(samples: result)
    }

    func gained(_ decibels: Double) -> Self {
        let factor = Float(pow(10, decibels / 20))
        return Self(samples: samples.map { $0 * factor })
    }

    /// `other` を `offset` 秒の位置に重ねる（足りなければ伸ばす）
    func mixing(_ other: Self, at offset: Double) -> Self {
        let start = Self.frames(offset)
        var result = samples
        if result.count < start + other.samples.count {
            result += [Float](repeating: 0, count: start + other.samples.count - result.count)
        }
        for (index, value) in other.samples.enumerated() {
            result[start + index] += value
        }
        return Self(samples: result)
    }

    var peakDecibels: Double {
        20 * log10(Double(samples.map(abs).max() ?? 0) + 1e-12)
    }

    var rmsDecibels: Double {
        let power = samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(samples.count, 1))
        return 10 * log10(power + 1e-12)
    }

    /// 最大値をそろえる
    func normalized(peak: Double) -> Self {
        gained(peak - peakDecibels)
    }

    /// 平均の大きさ（RMS）をそろえる。最大値が `ceiling` を越えるときは、越えないところまでにする
    func normalized(rms: Double, ceiling: Double) -> Self {
        let gain = min(rms - rmsDecibels, ceiling - peakDecibels)
        return gained(gain)
    }

    /// 2 次の IIR フィルター（RBJ の Audio EQ Cookbook の式）
    func filtered(_ biquad: Biquad) -> Self {
        var result = samples
        var (x1, x2, y1, y2) = (0.0, 0.0, 0.0, 0.0)
        for index in result.indices {
            let input = Double(result[index])
            let output = biquad.b0 * input + biquad.b1 * x1 + biquad.b2 * x2 - biquad.a1 * y1 - biquad.a2 * y2
            (x2, x1, y2, y1) = (x1, input, y1, output)
            result[index] = Float(output)
        }
        return Self(samples: result)
    }

    /// 軽く歪ませて倍音を足す（低い音しか無い元の音を、iPhone の小さなスピーカーでも聞こえるようにする）
    func saturated(drive: Double) -> Self {
        let scale = tanh(drive)
        return Self(samples: samples.map { Float(tanh(drive * Double($0)) / scale) })
    }

    /// 切れ目なくループできる形にする。`length` 秒の後ろの続き（`crossfade` 秒）を、頭に重ねて混ぜる。
    /// ループの長さは `length` の前後 `search` 秒のうち、頭と継ぎ目の波形がいちばん似ている長さにする
    func loop(length: Double, search: Double, crossfade: Double) -> Self {
        let fadeFrames = Self.frames(crossfade)
        let candidates = (Self.frames(length - search)...Self.frames(length + search))
        let best = candidates.max { lhs, rhs in
            similarity(at: lhs, frames: fadeFrames) < similarity(at: rhs, frames: fadeFrames)
        } ?? Self.frames(length)
        guard best + fadeFrames <= samples.count else {
            fatalError("ループにするには短すぎます")
        }
        var result = Array(samples[0..<best])
        for frame in 0..<fadeFrames {
            // 大きさが変わらないよう、二乗の和が 1 になる重み（equal power）で混ぜる
            let position = Double(frame) / Double(fadeFrames)
            let head = Float(sin(position * Double.pi / 2))
            let tail = Float(cos(position * Double.pi / 2))
            result[frame] = samples[frame] * head + samples[best + frame] * tail
        }
        return Self(samples: result)
    }

    private func similarity(at offset: Int, frames: Int) -> Double {
        guard offset + frames <= samples.count else {
            return -.infinity
        }
        var dot = 0.0
        var power = 0.0
        for frame in 0..<frames {
            dot += Double(samples[frame]) * Double(samples[offset + frame])
            power += Double(samples[offset + frame]) * Double(samples[offset + frame])
        }
        return dot / (sqrt(power) + 1e-12)
    }

    func write(_ path: String) {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            fatalError("書き出せません: \(path)")
        }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { pointer in
            buffer.floatChannelData?[0].update(from: pointer.baseAddress!, count: samples.count)
        }
        do {
            let file = try AVAudioFile(forWriting: URL(fileURLWithPath: path), settings: format.settings)
            try file.write(from: buffer)
        } catch {
            fatalError("書き出せません: \(path) \(error)")
        }
        let name = (path as NSString).lastPathComponent
        print(String(format: "%@: %.2f 秒, 最大 %.1f dB, RMS %.1f dB", name, duration, peakDecibels, rmsDecibels))
    }
}

struct Biquad {
    let b0: Double
    let b1: Double
    let b2: Double
    let a1: Double
    let a2: Double

    private init(b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double) {
        self.b0 = b0 / a0
        self.b1 = b1 / a0
        self.b2 = b2 / a0
        self.a1 = a1 / a0
        self.a2 = a2 / a0
    }

    static func highPass(_ frequency: Double, quality: Double = 0.707) -> Self {
        let omega = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(omega) / (2 * quality)
        let cosine = cos(omega)
        return Self(b0: (1 + cosine) / 2, b1: -(1 + cosine), b2: (1 + cosine) / 2, a0: 1 + alpha, a1: -2 * cosine, a2: 1 - alpha)
    }

    static func peaking(_ frequency: Double, gain decibels: Double, quality: Double) -> Self {
        let amplitude = pow(10, decibels / 40)
        let omega = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(omega) / (2 * quality)
        let cosine = cos(omega)
        return Self(
            b0: 1 + alpha * amplitude,
            b1: -2 * cosine,
            b2: 1 - alpha * amplitude,
            a0: 1 + alpha / amplitude,
            a1: -2 * cosine,
            a2: 1 - alpha / amplitude
        )
    }
}

// MARK: - 音ごとの作り方

/// 回収飛行船のプロペラ（ループ）。近づく音量の変化は、アプリが鳴らしながら付ける（SoundEffects）
func propeller(_ source: Sound) -> Sound {
    source.slice(1.0, 7.5)
        .filtered(.highPass(110))
        .filtered(.peaking(420, gain: 9, quality: 0.8))
        .filtered(.peaking(1_400, gain: 4, quality: 1.0))
        .normalized(peak: -6)
        .saturated(drive: 1.8)
        .loop(length: 5.0, search: 0.1, crossfade: 0.4)
        .normalized(rms: -18, ceiling: -1)
}

/// 納品: 判子を押して、すぐにタイプライターのベルが鳴る
func delivered(stamp: Sound, bell: Sound) -> Sound {
    let thump = stamp.slice(0.035, 0.30).faded(in: 0.002, out: 0.06).normalized(peak: -1)
    let ring = bell.slice(0.0, 0.89).faded(in: 0.002, out: 0.3).normalized(peak: -1).gained(-5)
    return thump.mixing(ring, at: 0.14).normalized(peak: -1)
}

/// 回収: 飛行船の汽笛
func whistle(_ source: Sound) -> Sound {
    source.slice(0.3, 3.19)
        .filtered(.highPass(150))
        .faded(in: 0.12, out: 0.5)
        .normalized(rms: -16, ceiling: -1)
}

/// リザルト: 明細書を印字する（タイプライターの打鍵を拾って、速めに打ち直す）
func receipt(_ source: Sound) -> Sound {
    // 元の音で、打鍵が始まる位置（秒）。どれも次の打鍵まで 70ms 以上あいている
    let onsets = [1.146, 1.798, 1.962, 2.412, 2.674, 3.060, 3.606, 3.758, 4.912, 5.092, 7.354, 7.586]
    let strokes = onsets.map { source.slice($0 - 0.003, $0 + 0.095).faded(in: 0.001, out: 0.03).normalized(peak: -1) }
    // (まとまりの始まる秒, 打鍵の間隔)。3 つのまとまりで、1 行ずつ打つように並べる
    let groups: [(start: Double, intervals: [Double])] = [
        (0.00, [0, 0.085, 0.165, 0.255, 0.335, 0.42]),
        (0.62, [0, 0.08, 0.17, 0.245, 0.33]),
        (1.10, [0, 0.09, 0.175, 0.26])
    ]
    let levels = [0.0, -2.5, -1.0, -3.0, -1.5, -0.5, -2.0]
    var result = Sound.silence(0)
    var count = 0
    for group in groups {
        for interval in group.intervals {
            let stroke = strokes[(count * 5) % strokes.count].gained(levels[count % levels.count])
            result = result.mixing(stroke, at: group.start + interval)
            count += 1
        }
    }
    return result.mixing(.silence(0.05), at: result.duration).normalized(peak: -1)
}

// MARK: - 実行

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    fatalError("使い方: edit <出力のフォルダ> <名前>=<元の音のパス> …")
}
let output = arguments[1]
var sources: [String: Sound] = [:]
for argument in arguments.dropFirst(2) {
    let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
    guard parts.count == 2 else {
        fatalError("<名前>=<パス> の形で渡してください: \(argument)")
    }
    sources[parts[0]] = Sound.load(parts[1])
}

func source(_ name: String) -> Sound {
    guard let sound = sources[name] else {
        fatalError("元の音がありません: \(name)")
    }
    return sound
}

propeller(source("propeller")).write("\(output)/propeller.caf")
delivered(stamp: source("stamp"), bell: source("bell")).write("\(output)/delivered.caf")
whistle(source("whistle")).write("\(output)/whistle.caf")
receipt(source("typewriter")).write("\(output)/receipt.caf")
