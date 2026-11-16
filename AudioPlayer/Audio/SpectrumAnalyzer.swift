import Foundation
import AVFoundation
import Accelerate

/// Спектр и уровни каналов для визуализатора.
///
/// `process` вызывается с аудиопотока (tap на mainMixerNode), поэтому класс
/// потокобезопасен: результаты под замком, интерфейс читает их через `snapshot()`.
final class SpectrumAnalyzer: @unchecked Sendable {
    /// Полос спектра (тонкие линии — все 56, столбики — по 2 вместе).
    static let bandCount = 56

    struct Snapshot: Sendable {
        /// Уровни полос 0…1, от низких частот к высоким.
        var bands: [Float]
        /// Уровни левого и правого каналов 0…1 (для стрелочных приборов).
        var left: Float
        var right: Float
    }

    private let fftSize = 1024
    private let log2n: vDSP_Length = 10
    private let setup: FFTSetup?
    private var window: [Float]

    private let lock = NSLock()
    private var bands = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)
    private var left: Float = 0
    private var right: Float = 0

    init() {
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        if let setup {
            vDSP_destroy_fftsetup(setup)
        }
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(bands: bands, left: left, right: right)
    }

    /// Плавное затухание к нулю (пауза).
    func decay() {
        lock.lock()
        for i in bands.indices {
            bands[i] *= 0.8
        }
        left *= 0.8
        right *= 0.8
        lock.unlock()
    }

    /// Обработка блока звука. Вызывается с аудиопотока.
    func process(_ buffer: AVAudioPCMBuffer) {
        guard let setup, let data = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        let sampleRate = Float(buffer.format.sampleRate)
        guard frames > 0, channels > 0, sampleRate > 0 else { return }
        let n = min(frames, fftSize)

        // Уровни каналов (RMS → дБ → 0…1, шкала −40…0 дБ)
        var rmsL: Float = 0
        vDSP_rmsqv(data[0], 1, &rmsL, vDSP_Length(n))
        var rmsR = rmsL
        if channels > 1 {
            vDSP_rmsqv(data[1], 1, &rmsR, vDSP_Length(n))
        }
        let targetL = Self.levelFromRMS(rmsL)
        let targetR = Self.levelFromRMS(rmsR)

        // Моно-сигнал с окном Ханна
        var mono = [Float](repeating: 0, count: fftSize)
        for c in 0..<channels {
            let samples = data[c]
            for i in 0..<n {
                mono[i] += samples[i]
            }
        }
        let scale = 1 / Float(channels)
        for i in 0..<fftSize {
            mono[i] = mono[i] * scale * window[i]
        }

        // БПФ
        let half = fftSize / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                guard let realBase = realPtr.baseAddress, let imagBase = imagPtr.baseAddress else { return }
                var split = DSPSplitComplex(realp: realBase, imagp: imagBase)
                mono.withUnsafeBufferPointer { monoPtr in
                    guard let monoBase = monoPtr.baseAddress else { return }
                    monoBase.withMemoryRebound(to: DSPComplex.self, capacity: half) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }
        magnitudes[0] = 0

        // Полосы в логарифмической шкале 40 Гц … 16 кГц (или до половины частоты)
        let binHz = sampleRate / Float(fftSize)
        let fMin: Float = 40
        let fMax = min(16_000, sampleRate / 2 - binHz)
        var targets = [Float](repeating: 0, count: Self.bandCount)
        for band in 0..<Self.bandCount {
            let lo = fMin * pow(fMax / fMin, Float(band) / Float(Self.bandCount))
            let hi = fMin * pow(fMax / fMin, Float(band + 1) / Float(Self.bandCount))
            let first = max(1, Int(lo / binHz))
            let last = max(first, min(half - 1, Int(hi / binHz)))
            var peak: Float = 0
            for bin in first...last {
                peak = max(peak, magnitudes[bin])
            }
            // Амплитуда → дБ → 0…1 (шкала подобрана на слух/глаз: −65…−15 дБ)
            let amplitude = sqrt(peak) / Float(fftSize)
            let db = 20 * log10(max(amplitude, 1e-9))
            targets[band] = min(max((db + 65) / 50, 0), 1)
        }

        // Сглаживание: быстрый подъём, медленный спад; стрелки — с инерцией (~300 мс)
        lock.lock()
        for i in 0..<Self.bandCount {
            let old = bands[i]
            let target = targets[i]
            bands[i] = target > old ? old + (target - old) * 0.6 : old * 0.85 + target * 0.15
        }
        left += (targetL - left) * 0.25
        right += (targetR - right) * 0.25
        lock.unlock()
    }

    private static func levelFromRMS(_ rms: Float) -> Float {
        let db = 20 * log10(max(rms, 1e-6))
        return min(max((db + 40) / 40, 0), 1)
    }
}
