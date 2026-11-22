import AVFoundation

/// Генератор низкого непрерывного тона (синус) — для выталкивания воды из динамика.
/// Работает на собственном AVAudioEngine, основной плеер в это время на паузе.
@MainActor
final class ToneGenerator {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var state: SinePhase?
    private var sampleRate: Double = 48_000

    private(set) var isRunning = false

    func start(frequency: Double) throws {
        stop()
        let hardwareFormat = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = hardwareFormat.sampleRate > 0 ? hardwareFormat.sampleRate : 48_000
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        self.sampleRate = sampleRate
        let state = SinePhase()
        state.step = 2 * Double.pi * frequency / sampleRate
        self.state = state
        let node = Self.makeSineNode(state: state)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: mono)
        engine.mainMixerNode.outputVolume = 1
        try engine.start()
        source = node
        isRunning = true
    }

    /// Смена частоты на ходу — без щелчка, фаза продолжается.
    func setFrequency(_ frequency: Double) {
        state?.sweepPeriodFrames = 0
        state?.step = 2 * Double.pi * frequency / sampleRate
    }

    /// Плавный проход частот туда и обратно: low → high → low за `period` секунд.
    func setSweep(from low: Double, to high: Double, period: Double) {
        guard let state else { return }
        state.sweepLowStep = 2 * Double.pi * low / sampleRate
        state.sweepHighStep = 2 * Double.pi * high / sampleRate
        state.sweepFrame = 0
        state.sweepPeriodFrames = max(1, Int(period * sampleRate))
    }

    func stop() {
        if engine.isRunning {
            engine.stop()
        }
        if let source {
            engine.detach(source)
        }
        source = nil
        state = nil
        isRunning = false
    }

    /// Узел создаётся вне главного актора: его блок вызывается на аудиопотоке.
    nonisolated private static func makeSineNode(state: SinePhase) -> AVAudioSourceNode {
        AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            var phase = state.phase
            let period = state.sweepPeriodFrames
            let low = state.sweepLowStep
            let high = state.sweepHighStep
            var sweepFrame = state.sweepFrame
            let constantStep = state.step
            for frame in 0..<Int(frameCount) {
                // 0.9 — небольшой запас, чтобы не было перегруза
                let value = Float(sin(phase)) * 0.9
                var step = constantStep
                if period > 0 {
                    // Треугольник: первая половина периода вверх, вторая — вниз
                    let position = Double(sweepFrame % period) / Double(period)
                    let t = position < 0.5 ? position * 2 : 2 - position * 2
                    step = low + (high - low) * t
                    sweepFrame += 1
                }
                phase += step
                if phase >= 2 * Double.pi {
                    phase -= 2 * Double.pi
                }
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value
                }
            }
            state.phase = phase
            state.sweepFrame = sweepFrame
            return noErr
        }
    }
}

/// Фаза синуса (пишет аудиопоток) и шаг фазы (пишет главный поток при смене частоты).
/// Одно 64-битное значение на arm64 записывается целиком, поэтому блокировка не нужна.
private final class SinePhase: @unchecked Sendable {
    var phase: Double = 0
    var step: Double = 0
    // Плавный проход частот (0 — выключен)
    var sweepPeriodFrames = 0
    var sweepFrame = 0
    var sweepLowStep: Double = 0
    var sweepHighStep: Double = 0
}
