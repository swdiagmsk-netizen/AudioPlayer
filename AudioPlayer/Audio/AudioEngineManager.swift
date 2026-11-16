import AVFoundation
import AudioToolbox
import Observation

/// Аудиодвижок на AVAudioEngine.
///
/// Граф узлов:
///   AVAudioPlayerNode → AVAudioUnitTimePitch → AVAudioUnitEQ (10 полос)
///   → AVAudioUnitEffect (Apple DynamicsProcessor) → mainMixerNode → выход
///
/// Все узлы до микшера подключаются в формате текущего файла (частота и каналы).
/// Если у следующего файла формат другой — граф переподключается.
///
/// Время воспроизведения:
///   currentTime = (кадр начала сегмента + кадр плеера) / частота файла.
///   Кадры плеера считаются в частоте файла, скорость TimePitch на них не влияет.
///
/// «Поколение» (generation): каждый новый запуск сегмента увеличивает счётчик.
/// Колбэк окончания старого сегмента (после перемотки или смены трека)
/// видит устаревшее поколение и ничего не делает.
@MainActor
@Observable
final class AudioEngineManager {
    // MARK: Состояние для интерфейса

    private(set) var isPlaying: Bool = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var rate: Float = 1
    private(set) var isLoaded: Bool = false

    // MARK: Колбэки для PlaybackController

    /// Трек доиграл до конца.
    @ObservationIgnored var onFinished: (() -> Void)?
    /// Вызывается ~10 раз в секунду во время воспроизведения.
    @ObservationIgnored var onTick: (() -> Void)?

    // MARK: Узлы

    @ObservationIgnored private(set) var engine = AVAudioEngine()
    @ObservationIgnored private(set) var playerNode = AVAudioPlayerNode()
    @ObservationIgnored private(set) var timePitch = AVAudioUnitTimePitch()
    @ObservationIgnored private(set) var eq = AVAudioUnitEQ(numberOfBands: 10)
    @ObservationIgnored private(set) var dynamics = AudioEngineManager.makeDynamicsProcessor()

    /// Частоты полос эквалайзера, Гц.
    static let eqFrequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    // MARK: Внутреннее

    @ObservationIgnored private var file: AVAudioFile?
    @ObservationIgnored private var fileURL: URL?
    @ObservationIgnored private var sampleRate: Double = 44_100
    @ObservationIgnored private var totalFrames: AVAudioFramePosition = 0
    @ObservationIgnored private var segmentStartFrame: AVAudioFramePosition = 0
    @ObservationIgnored private var generation: Int = 0
    @ObservationIgnored private var connectedFormat: AVAudioFormat?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var configObserver: NSObjectProtocol?

    init() {
        buildGraph()
    }

    // MARK: - Граф

    /// Создаёт узлы заново (нужно и при первом запуске, и после сброса медиасервисов iOS).
    private func buildGraph() {
        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        timePitch = AVAudioUnitTimePitch()
        eq = AVAudioUnitEQ(numberOfBands: 10)
        dynamics = Self.makeDynamicsProcessor()
        connectedFormat = nil

        timePitch.pitch = 0
        timePitch.rate = rate
        configureEQ()
        // Нормализация и эквалайзер настраиваются на этапе 5; пока — без обработки
        eq.bypass = true
        dynamics.bypass = true

        engine.attach(playerNode)
        engine.attach(timePitch)
        engine.attach(eq)
        engine.attach(dynamics)

        observeConfigurationChange()
    }

    /// Apple DynamicsProcessor: готового класса AVAudioUnit для него нет,
    /// поэтому создаём общий AVAudioUnitEffect по описанию компонента.
    private static func makeDynamicsProcessor() -> AVAudioUnitEffect {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return AVAudioUnitEffect(audioComponentDescription: description)
    }

    /// 10 полос: крайние — полочные фильтры, остальные — параметрические.
    private func configureEQ() {
        for (index, band) in eq.bands.enumerated() {
            guard index < Self.eqFrequencies.count else { break }
            band.frequency = Self.eqFrequencies[index]
            if index == 0 {
                band.filterType = .lowShelf
            } else if index == Self.eqFrequencies.count - 1 {
                band.filterType = .highShelf
            } else {
                band.filterType = .parametric
                band.bandwidth = 1.0
            }
            band.gain = 0
            band.bypass = false
        }
        eq.globalGain = 0
    }

    /// Подключает цепочку в формате файла.
    private func connectChain(format: AVAudioFormat) {
        if engine.isRunning {
            engine.stop()
        }
        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(timePitch)
        engine.disconnectNodeOutput(eq)
        engine.disconnectNodeOutput(dynamics)

        engine.connect(playerNode, to: timePitch, format: format)
        engine.connect(timePitch, to: eq, format: format)
        engine.connect(eq, to: dynamics, format: format)
        engine.connect(dynamics, to: engine.mainMixerNode, format: format)
        engine.prepare()
        connectedFormat = format
    }

    private func startEngineIfNeeded() throws {
        if !engine.isRunning {
            try engine.start()
        }
    }

    // MARK: - Загрузка и воспроизведение

    /// Открывает файл и ставит его на позицию `startAt` (без запуска воспроизведения).
    func load(url: URL, startAt: Double) throws {
        stopTicking()
        generation += 1
        playerNode.stop()
        isPlaying = false

        let newFile = try AVAudioFile(forReading: url)
        let format = newFile.processingFormat
        if connectedFormat == nil || connectedFormat != format {
            connectChain(format: format)
        }

        file = newFile
        fileURL = url
        sampleRate = format.sampleRate
        totalFrames = newFile.length
        duration = sampleRate > 0 ? Double(totalFrames) / sampleRate : 0
        isLoaded = true

        scheduleSegment(fromSeconds: startAt)
    }

    /// Ставит в очередь плеера кусок файла от заданной секунды до конца.
    private func scheduleSegment(fromSeconds seconds: Double) {
        guard let file else { return }
        generation += 1
        let currentGeneration = generation
        playerNode.stop()

        var start = AVAudioFramePosition((max(0, seconds) * sampleRate).rounded(.down))
        if start >= totalFrames {
            start = max(0, totalFrames - 1)
        }
        segmentStartFrame = start
        currentTime = sampleRate > 0 ? Double(start) / sampleRate : 0

        let remaining = totalFrames - start
        guard remaining > 0 else { return }

        // Колбэк приходит с аудиопотока: замыкание явно @Sendable (не привязано
        // к главному актору), а в главный актор переходим через Task.
        playerNode.scheduleSegment(
            file,
            startingFrame: start,
            frameCount: AVAudioFrameCount(remaining),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { @Sendable [weak self] _ in
            Task { @MainActor in
                self?.segmentDidFinish(generation: currentGeneration)
            }
        }
    }

    func play() throws {
        guard isLoaded else { return }
        try startEngineIfNeeded()
        playerNode.play()
        isPlaying = true
        startTicking()
    }

    func pause() {
        guard isLoaded else { return }
        currentTime = computeCurrentTime()
        playerNode.pause()
        isPlaying = false
        stopTicking()
    }

    /// Полная остановка (позиция сохраняется в currentTime).
    func stop() {
        currentTime = computeCurrentTime()
        generation += 1
        playerNode.stop()
        isPlaying = false
        stopTicking()
    }

    /// Перемотка на секунду `seconds`.
    func seek(to seconds: Double) {
        guard isLoaded else { return }
        let wasPlaying = isPlaying
        let target = min(max(0, seconds), max(0, duration - 0.05))
        scheduleSegment(fromSeconds: target)
        if wasPlaying {
            do {
                try startEngineIfNeeded()
                playerNode.play()
            } catch {
                isPlaying = false
                stopTicking()
                AppLogger.shared.log("audio", "Не удалось продолжить после перемотки: \(error.localizedDescription)")
            }
        }
    }

    /// Перемотка относительно текущей позиции.
    func skip(by delta: Double) {
        seek(to: computeCurrentTime() + delta)
    }

    /// Скорость 0.5–4x с сохранением высоты тона.
    func setRate(_ newRate: Float) {
        let clamped = min(max(newRate, 0.5), 4.0)
        rate = clamped
        timePitch.rate = clamped
    }

    /// Текущее время с учётом того, что плеер играет прямо сейчас.
    func computeCurrentTime() -> Double {
        guard isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              sampleRate > 0 else {
            return currentTime
        }
        let seconds = Double(segmentStartFrame + playerTime.sampleTime) / sampleRate
        return min(max(0, seconds), duration)
    }

    // MARK: - Окончание и таймер

    private func segmentDidFinish(generation finishedGeneration: Int) {
        guard finishedGeneration == generation else { return }
        isPlaying = false
        currentTime = duration
        stopTicking()
        onFinished?()
    }

    private func startTicking() {
        stopTicking()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.currentTime = self.computeCurrentTime()
                self.onTick?()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    // MARK: - Системные события

    /// iOS сменила аудиоконфигурацию (подключили Bluetooth, сменилась частота и т.п.):
    /// движок остановлен — переподключаем граф и продолжаем с той же позиции.
    private func observeConfigurationChange() {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleConfigurationChange()
            }
        }
    }

    private func handleConfigurationChange() {
        AppLogger.shared.log("audio", "Изменилась аудиоконфигурация — перезапуск движка")
        let wasPlaying = isPlaying
        let position = computeCurrentTime()
        guard let file else { return }
        connectChain(format: file.processingFormat)
        isPlaying = false
        stopTicking()
        scheduleSegment(fromSeconds: position)
        if wasPlaying {
            do {
                try play()
            } catch {
                AppLogger.shared.log("audio", "Не удалось перезапустить движок: \(error.localizedDescription)")
            }
        }
    }

    /// Сброс медиасервисов iOS: старый движок непригоден, создаём граф заново
    /// и открываем тот же файл на той же позиции.
    func rebuildAfterMediaServicesReset() {
        AppLogger.shared.log("audio", "Сброс медиасервисов — пересоздание графа")
        let wasPlaying = isPlaying
        let position = computeCurrentTime()
        let url = fileURL
        stopTicking()
        isPlaying = false
        isLoaded = false
        file = nil
        buildGraph()
        guard let url else { return }
        do {
            try load(url: url, startAt: position)
            if wasPlaying {
                try play()
            }
        } catch {
            AppLogger.shared.log("audio", "Не удалось восстановить воспроизведение: \(error.localizedDescription)")
        }
    }
}
