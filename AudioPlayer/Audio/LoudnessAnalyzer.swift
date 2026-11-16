import Foundation
import AVFoundation

/// Измерение интегральной громкости трека по ITU-R BS.1770 (LUFS).
///
/// Порядок: K-взвешивание (полочный фильтр + фильтр высоких частот) →
/// среднеквадратичное по блокам 400 мс с перекрытием 75% →
/// абсолютный гейт −70 LUFS → относительный гейт −10 LU → итоговая громкость.
/// Работает синхронно — вызывать только из фоновой задачи.
enum LoudnessAnalyzer {
    /// Цель выравнивания, LUFS.
    static let targetLUFS: Double = -16
    /// Ограничение поправки, дБ.
    static let maxGainDB: Double = 12

    /// Поправка громкости в дБ для трека с громкостью `lufs`.
    static func gainDB(forLUFS lufs: Double) -> Float {
        Float(min(max(targetLUFS - lufs, -maxGainDB), maxGainDB))
    }

    /// Громкость файла в LUFS или nil, если файл не читается или слишком тихий.
    static func measure(url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let channels = Int(format.channelCount)
        guard sampleRate > 0, channels > 0, format.commonFormat == .pcmFormatFloat32 else { return nil }

        // Подблоки по 100 мс: блок 400 мс = 4 подблока, шаг 100 мс = перекрытие 75%
        let subBlockFrames = max(1, Int(sampleRate * 0.1))
        let chunkFrames = AVAudioFrameCount(subBlockFrames * 10)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else { return nil }

        var filters = (0..<channels).map { _ in KWeightingFilter(sampleRate: sampleRate) }
        // Учитываем до 5 каналов; веса BS.1770: L, R, C = 1.0, тыловые = 1.41 (для простоты все = 1.0)
        var subBlockSums: [Double] = []
        var currentSum = [Double](repeating: 0, count: channels)
        var currentCount = 0

        while file.framePosition < file.length {
            do {
                try file.read(into: buffer, frameCount: chunkFrames)
            } catch {
                break
            }
            let frames = Int(buffer.frameLength)
            if frames == 0 { break }
            guard let data = buffer.floatChannelData else { break }

            var offset = 0
            while offset < frames {
                let take = min(subBlockFrames - currentCount, frames - offset)
                for ch in 0..<channels {
                    let samples = data[ch]
                    var sum = 0.0
                    for i in offset..<(offset + take) {
                        let y = filters[ch].process(Double(samples[i]))
                        sum += y * y
                    }
                    currentSum[ch] += sum
                }
                currentCount += take
                offset += take
                if currentCount == subBlockFrames {
                    let meanSquare = currentSum.reduce(0, +) / Double(subBlockFrames)
                    subBlockSums.append(meanSquare)
                    currentSum = [Double](repeating: 0, count: channels)
                    currentCount = 0
                }
            }
        }

        guard subBlockSums.count >= 4 else { return nil }

        // Блоки 400 мс
        var blocks: [Double] = []
        blocks.reserveCapacity(subBlockSums.count)
        for start in 0...(subBlockSums.count - 4) {
            let z = (subBlockSums[start] + subBlockSums[start + 1] + subBlockSums[start + 2] + subBlockSums[start + 3]) / 4
            blocks.append(z)
        }

        func loudness(_ z: Double) -> Double {
            -0.691 + 10 * log10(max(z, 1e-12))
        }

        // Абсолютный гейт
        let absGated = blocks.filter { loudness($0) > -70 }
        guard !absGated.isEmpty else { return nil }
        let absMean = absGated.reduce(0, +) / Double(absGated.count)
        // Относительный гейт
        let relativeThreshold = loudness(absMean) - 10
        let relGated = absGated.filter { loudness($0) > relativeThreshold }
        guard !relGated.isEmpty else { return nil }
        let mean = relGated.reduce(0, +) / Double(relGated.count)
        return loudness(mean)
    }
}

/// K-взвешивание: два биквадратных фильтра (формулы RBJ, параметры BS.1770).
private struct KWeightingFilter {
    private var shelf: Biquad
    private var highPass: Biquad

    init(sampleRate: Double) {
        shelf = Biquad.highShelf(sampleRate: sampleRate, frequency: 1681.97, gainDB: 3.9998, q: 0.7072)
        highPass = Biquad.highPass(sampleRate: sampleRate, frequency: 38.135, q: 0.5003)
    }

    mutating func process(_ x: Double) -> Double {
        highPass.process(shelf.process(x))
    }
}

private struct Biquad {
    var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        return y
    }

    static func highShelf(sampleRate: Double, frequency: Double, gainDB: Double, q: Double) -> Biquad {
        let a = pow(10, gainDB / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let cosW = cos(w0)
        let alpha = sin(w0) / (2 * q)
        let sqrtA2alpha = 2 * sqrt(a) * alpha
        let b0 = a * ((a + 1) + (a - 1) * cosW + sqrtA2alpha)
        let b1 = -2 * a * ((a - 1) + (a + 1) * cosW)
        let b2 = a * ((a + 1) + (a - 1) * cosW - sqrtA2alpha)
        let a0 = (a + 1) - (a - 1) * cosW + sqrtA2alpha
        let a1 = 2 * ((a - 1) - (a + 1) * cosW)
        let a2 = (a + 1) - (a - 1) * cosW - sqrtA2alpha
        return Biquad(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    static func highPass(sampleRate: Double, frequency: Double, q: Double) -> Biquad {
        let w0 = 2 * Double.pi * frequency / sampleRate
        let cosW = cos(w0)
        let alpha = sin(w0) / (2 * q)
        let b0 = (1 + cosW) / 2
        let b1 = -(1 + cosW)
        let b2 = (1 + cosW) / 2
        let a0 = 1 + alpha
        let a1 = -2 * cosW
        let a2 = 1 - alpha
        return Biquad(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }
}
