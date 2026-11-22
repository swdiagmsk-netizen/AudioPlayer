import AVFoundation
import CoreMotion
import Observation
import SwiftUI
import UIKit

/// Раздел «Сервис».
struct ServiceSettingsView: View {
    let container: AppContainer

    var body: some View {
        List {
            Section {
                NavigationLink {
                    WaterEjectView(playback: container.playback)
                        .onAppear { Haptics.select() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "drop.triangle")
                            .foregroundStyle(Color(hex: "#0EA5E9"))
                            .frame(width: 28)
                        Text(tr("Вытолкнуть воду из динамика"))
                    }
                }
            } header: {
                Text(tr("Динамик"))
            } footer: {
                Text(tr("Низкий звук в течение 30 секунд помогает вытолкнуть воду из решётки динамика. Частоту можно выбрать: 150, 165, 200 Гц или плавно 150–200 Гц."))
            }
        }
        .navigationTitle(tr("Сервис"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Выталкивание воды: отсчёт 10…0, пока человек читает подсказку; звук включается,
/// как только телефон перевёрнут экраном вниз (по датчику), или кнопкой.
@MainActor
@Observable
final class WaterEjectController {
    enum Phase: Equatable {
        /// Отсчёт: сколько секунд осталось.
        case countdown(Int)
        /// Отсчёт закончился, ждём переворота.
        case waitingFlip
        /// Звук идёт: сколько секунд осталось.
        case playing(Int)
        case done
    }

    /// Варианты звука. 165 Гц — как у Apple Watch и большинства таких программ (по умолчанию);
    /// 150 и 200 Гц — тоже частые; «плавно» — проход 150 → 200 → 150 Гц, как у fixspeaker.com.
    static let modes = ["150", "165", "200", "sweep"]
    static let sweepLow: Double = 150
    static let sweepHigh: Double = 200
    /// Один проход вверх и вниз при плавном режиме, секунд.
    static let sweepPeriod: Double = 15
    static let countdownSeconds = 10

    private(set) var phase: Phase = .countdown(WaterEjectController.countdownSeconds)
    /// Наушники или колонка подключены — звук не включаем.
    private(set) var externalOutput = false
    /// Текущая громкость iPhone, 0…1.
    private(set) var volume: Float = AVAudioSession.sharedInstance().outputVolume
    /// Длительность — фиксированная.
    let duration = 30
    /// Выбранный вариант звука, запоминается.
    var mode: String = UserDefaults.standard.string(forKey: SettingsKeys.waterEjectMode) ?? "165" {
        didSet { UserDefaults.standard.set(mode, forKey: SettingsKeys.waterEjectMode) }
    }

    /// Подпись варианта: «165» или «150–200».
    static func label(for mode: String) -> String {
        mode == "sweep" ? "\(Int(sweepLow))–\(Int(sweepHigh))" : mode
    }

    private let playback: PlaybackController
    @ObservationIgnored private let tone = ToneGenerator()
    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private let speech = AVSpeechSynthesizer()
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var resumeMusic = false
    @ObservationIgnored private var startedByFlip = false
    @ObservationIgnored private var faceDownSamples = 0
    @ObservationIgnored private var faceUpSamples = 0

    init(playback: PlaybackController) {
        self.playback = playback
    }

    // MARK: - Жизненный цикл экрана

    func appear() {
        UIApplication.shared.isIdleTimerDisabled = true
        resumeMusic = playback.isPlaying
        if resumeMusic {
            playback.pause()
        }
        playback.restoreAudioSession()
        startMotion()
        startCountdown()
    }

    func disappear() {
        ticker?.cancel()
        tone.stop()
        motion.stopAccelerometerUpdates()
        UIApplication.shared.isIdleTimerDisabled = false
        if resumeMusic {
            resumeMusic = false
            playback.play()
        }
    }

    // MARK: - Действия

    func playNow() {
        startTone(byFlip: false)
    }

    func stop() {
        guard case .playing = phase else { return }
        finish()
    }

    func again() {
        startCountdown()
    }

    // MARK: - Внутреннее

    private func startCountdown() {
        ticker?.cancel()
        phase = .countdown(Self.countdownSeconds)
        refreshOutput()
        ticker = Task { [weak self] in
            for remaining in stride(from: Self.countdownSeconds - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, case .countdown = self.phase else { return }
                self.refreshOutput()
                self.phase = remaining > 0 ? .countdown(remaining) : .waitingFlip
            }
        }
    }

    private func startTone(byFlip: Bool) {
        switch phase {
        case .countdown, .waitingFlip:
            break
        default:
            return
        }
        refreshOutput()
        guard !externalOutput else { return }
        do {
            if mode == "sweep" {
                try tone.start(frequency: Self.sweepLow)
                tone.setSweep(from: Self.sweepLow, to: Self.sweepHigh, period: Self.sweepPeriod)
            } else {
                try tone.start(frequency: Double(mode) ?? 165)
            }
        } catch {
            AppLogger.shared.log("water", "Не удалось включить тон: \(error.localizedDescription)")
            return
        }
        AppLogger.shared.log("water", "Тон \(Self.label(for: mode)) Гц, \(duration) с, по перевороту: \(byFlip)")
        Haptics.tap()
        startedByFlip = byFlip
        faceUpSamples = 0
        ticker?.cancel()
        phase = .playing(duration)
        let total = duration
        ticker = Task { [weak self] in
            for remaining in stride(from: total - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, case .playing = self.phase else { return }
                self.refreshOutput()
                // Подключили наушники во время звука — сразу выключаем
                if self.externalOutput {
                    self.finish()
                    return
                }
                if remaining == 0 {
                    self.finish()
                    self.announceDone()
                    return
                }
                self.phase = .playing(remaining)
            }
        }
    }

    private func finish() {
        ticker?.cancel()
        tone.stop()
        phase = .done
        Haptics.tap()
    }

    /// Голосом «Готово!» на языке интерфейса, низким мужским голосом.
    private func announceDone() {
        let (text, language) = Self.doneSpeech()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.maleVoice(for: language)
        // Ниже обычного — «бас». Допустимо 0.5…2.0
        utterance.pitchMultiplier = 0.6
        utterance.volume = 1
        speech.stopSpeaking(at: .immediate)
        speech.speak(utterance)
    }

    /// Фраза и язык голоса. Если голоса для языка нет в iPhone — по-английски.
    private static func doneSpeech() -> (String, String) {
        let languages = ["en": "en-US", "ru": "ru-RU", "zh-Hant": "zh-TW", "ja": "ja-JP", "es": "es-ES",
                         "de": "de-DE", "fr": "fr-FR", "pt": "pt-BR", "hi": "hi-IN", "ar": "ar-SA",
                         "bn": "bn-IN", "id": "id-ID"]
        let language = languages[AppLanguage.code] ?? "en-US"
        let prefix = String(language.prefix(2))
        let hasVoice = AVSpeechSynthesisVoice.speechVoices().contains { $0.language.hasPrefix(prefix) }
        if hasVoice {
            return (tr("Готово!"), language)
        }
        return ("Well done!", "en-US")
    }

    /// Мужской голос для языка, если есть; лучше — улучшенного качества.
    private static func maleVoice(for language: String) -> AVSpeechSynthesisVoice? {
        let prefix = String(language.prefix(2))
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(prefix) }
        let male = voices.filter { $0.gender == .male }
        // VERIFY: какие мужские голоса есть на конкретном iPhone (часть скачивается в Настройках)
        if let best = male.max(by: { $0.quality.rawValue < $1.quality.rawValue }) {
            return best
        }
        return AVSpeechSynthesisVoice(language: language) ?? voices.first
    }

    /// Наушники/колонка и громкость.
    private func refreshOutput() {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        externalOutput = outputs.contains { $0.portType != .builtInSpeaker && $0.portType != .builtInReceiver }
        volume = session.outputVolume
    }

    /// Датчик положения: z ≈ +1 — экраном вниз, z ≈ −1 — экраном вверх.
    private func startMotion() {
        guard motion.isAccelerometerAvailable, !motion.isAccelerometerActive else { return }
        motion.accelerometerUpdateInterval = 0.1
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let z = data?.acceleration.z else { return }
            MainActor.assumeIsolated {
                self?.handleTilt(z: z)
            }
        }
    }

    private func handleTilt(z: Double) {
        switch phase {
        case .countdown, .waitingFlip:
            // Полсекунды экраном вниз — перевернул, включаем
            faceDownSamples = z > 0.8 ? faceDownSamples + 1 : 0
            if faceDownSamples >= 5 {
                faceDownSamples = 0
                startTone(byFlip: true)
            }
        case .playing:
            // Перевернул обратно экраном вверх — останавливаем
            guard startedByFlip else { return }
            faceUpSamples = z < -0.3 ? faceUpSamples + 1 : 0
            if faceUpSamples >= 5 {
                finish()
            }
        case .done:
            break
        }
    }
}

struct WaterEjectView: View {
    @State private var controller: WaterEjectController

    init(playback: PlaybackController) {
        _controller = State(initialValue: WaterEjectController(playback: playback))
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    bigNumber
                    statusText
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            if controller.externalOutput {
                Section {
                    Label(tr("Отключите наушники и Bluetooth-колонку — звук должен идти только через динамик iPhone."), systemImage: "headphones")
                        .foregroundStyle(.orange)
                }
            }

            switch controller.phase {
            case .countdown, .waitingFlip:
                Section {
                    Text(tr("1. Снимите чехол и отключите наушники или Bluetooth-колонку."))
                    Text(tr("2. Прибавьте громкость кнопками сбоку до максимума."))
                    Text(tr("3. Переверните iPhone экраном вниз над полотенцем — звук включится сам."))
                    Text(tr("Громкость: %@", "\(Int((controller.volume * 100).rounded()))%"))
                        .foregroundStyle(controller.volume < 0.8 ? Color.orange : Color.secondary)
                }
                Section {
                    Picker(tr("Частота"), selection: $controller.mode) {
                        ForEach(WaterEjectController.modes, id: \.self) { mode in
                            Text(tr("%@ Гц", WaterEjectController.label(for: mode))).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Button(tr("Включить без переворота")) {
                        Haptics.tap()
                        controller.playNow()
                    }
                    .disabled(controller.externalOutput)
                }
            case .playing:
                Section {
                    Text(tr("Переверните телефон обратно или нажмите «Стоп», чтобы остановить."))
                    Button(tr("Стоп"), role: .destructive) {
                        controller.stop()
                    }
                }
            case .done:
                Section {
                    Text(tr("Если звук всё ещё глухой — повторите или дайте телефону просохнуть: постучите им о ладонь разъёмом вниз и оставьте в сухом месте с притоком воздуха. Apple не советует сушить iPhone в рисе."))
                    Button(tr("Ещё раз")) {
                        Haptics.tap()
                        controller.again()
                    }
                }
            }
        }
        .navigationTitle(tr("Вытолкнуть воду из динамика"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { controller.appear() }
        .onDisappear { controller.disappear() }
    }

    @ViewBuilder
    private var bigNumber: some View {
        switch controller.phase {
        case .countdown(let remaining):
            Text("\(remaining)")
                .font(.system(size: 120, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(countdownColor(remaining))
                .contentTransition(.numericText(countsDown: true))
                .animation(.easeInOut(duration: 0.3), value: remaining)
        case .waitingFlip:
            Text(tr("Переверни телефон экраном вниз!"))
                .font(.system(size: 40, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(countdownColor(0))
        case .playing(let remaining):
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color(hex: "#0EA5E9"))
                .symbolEffect(.variableColor.iterative, options: .repeating)
            Text(tr("%@ с", "\(remaining)"))
                .font(.system(size: 64, weight: .black, design: .rounded))
                .monospacedDigit()
            Text(tr("%@ Гц", WaterEjectController.label(for: controller.mode)))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color(hex: "#22C55E"))
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch controller.phase {
        case .countdown:
            Text(tr("Переверните телефон экраном вниз — звук включится сам"))
                .font(.headline)
                .multilineTextAlignment(.center)
        case .waitingFlip:
            EmptyView()
        case .playing:
            Text(tr("Выталкиваю воду…"))
                .font(.headline)
        case .done:
            Text(tr("Готово"))
                .font(.headline)
        }
    }

    /// 10 — зелёный, 0 — красный, между ними — плавный переход с каждой цифрой.
    private func countdownColor(_ remaining: Int) -> Color {
        let t = Double(max(0, min(WaterEjectController.countdownSeconds, remaining))) / Double(WaterEjectController.countdownSeconds)
        let green = (r: 0.13, g: 0.77, b: 0.37)
        let red = (r: 0.90, g: 0.28, b: 0.30)
        return Color(
            red: red.r + (green.r - red.r) * t,
            green: red.g + (green.g - red.g) * t,
            blue: red.b + (green.b - red.b) * t
        )
    }
}
