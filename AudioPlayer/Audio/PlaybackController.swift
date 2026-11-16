import Foundation
import Observation

/// Управление воспроизведением: очередь, переходы, экран блокировки,
/// прерывания и сохранение состояния между запусками.
///
/// Очередь здесь простая (список ID и номер). На этапе 3 её заменит
/// QueueAndPlaylistManager с True Shuffle и Repeat.
@MainActor
@Observable
final class PlaybackController {
    /// Текущий трек.
    private(set) var currentTrack: TrackRecord?
    /// Очередь — стабильные ID треков.
    private(set) var queue: [UUID] = []
    /// Номер текущего трека в очереди (-1 — ничего не выбрано).
    private(set) var index: Int = -1
    /// Сообщение для пользователя (например, «файл защищён»). Интерфейс показывает и сбрасывает.
    var message: String?

    /// Аудиодвижок (интерфейс читает из него время, длительность, скорость).
    let engine = AudioEngineManager()

    @ObservationIgnored private let library: LibraryAndBookmarkManager
    @ObservationIgnored private let session = AudioSessionController()
    @ObservationIgnored private let nowPlaying = NowPlayingController()
    @ObservationIgnored private var lastSaveTime: Date = .distantPast
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var isSetUp = false

    init(library: LibraryAndBookmarkManager) {
        self.library = library
    }

    /// Подключение к системе. Вызывать один раз после создания.
    func setUp() {
        guard !isSetUp else { return }
        isSetUp = true

        engine.onFinished = { [weak self] in
            self?.trackDidFinish()
        }
        engine.onTick = { [weak self] in
            self?.periodicSave()
        }

        session.onInterruptionBegan = { [weak self] in
            guard let self else { return }
            self.resumeAfterInterruption = self.engine.isPlaying
            self.pause()
        }
        session.onInterruptionEnded = { [weak self] shouldResume in
            guard let self else { return }
            if shouldResume && self.resumeAfterInterruption {
                self.play()
            }
            self.resumeAfterInterruption = false
        }
        session.onOldDeviceUnavailable = { [weak self] in
            self?.pause()
        }
        session.onMediaServicesReset = { [weak self] in
            guard let self else { return }
            self.engine.rebuildAfterMediaServicesReset()
            self.session.activate(spokenAudio: false)
            self.refreshNowPlaying()
        }
        session.startObserving()
        nowPlaying.installCommands(target: self)
    }

    // MARK: - Основные действия

    var isPlaying: Bool { engine.isPlaying }

    /// Запускает список треков с заданного номера.
    func play(queue uids: [UUID], startAt startIndex: Int) {
        guard !uids.isEmpty, startIndex >= 0, startIndex < uids.count else { return }
        queue = uids
        _ = loadTrack(at: startIndex, startAt: 0, autoplay: true, direction: 1)
    }

    func play() {
        guard engine.isLoaded else {
            // Ничего не загружено — пробуем начать текущую очередь
            if index >= 0 {
                _ = loadTrack(at: index, startAt: engine.currentTime, autoplay: true, direction: 1)
            }
            return
        }
        session.activate(spokenAudio: false)
        do {
            try engine.play()
        } catch {
            AppLogger.shared.log("audio", "Не удалось начать воспроизведение: \(error.localizedDescription)")
            message = "Не удалось начать воспроизведение"
        }
        nowPlaying.updatePlayback(elapsed: engine.currentTime, rate: engine.rate, isPlaying: engine.isPlaying)
        saveState()
    }

    func pause() {
        engine.pause()
        nowPlaying.updatePlayback(elapsed: engine.currentTime, rate: engine.rate, isPlaying: false)
        saveState()
    }

    func togglePlayPause() {
        if engine.isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// Следующий трек (в конце очереди — остановка; повтор появится на этапе 3).
    func next() {
        guard !queue.isEmpty else { return }
        let target = index + 1
        guard target < queue.count else {
            engine.stop()
            engine.seek(to: 0)
            refreshNowPlaying()
            saveState()
            return
        }
        _ = loadTrack(at: target, startAt: 0, autoplay: true, direction: 1)
    }

    /// Если прошло больше 3 секунд — в начало трека, иначе — предыдущий трек.
    func previous() {
        guard !queue.isEmpty else { return }
        if engine.computeCurrentTime() > 3 || index <= 0 {
            seek(to: 0)
            return
        }
        _ = loadTrack(at: index - 1, startAt: 0, autoplay: true, direction: -1)
    }

    func seek(to seconds: Double) {
        engine.seek(to: seconds)
        nowPlaying.updatePlayback(elapsed: engine.currentTime, rate: engine.rate, isPlaying: engine.isPlaying)
        saveState()
    }

    func skipForward() {
        seek(to: engine.computeCurrentTime() + Double(AppSettings.skipInterval))
    }

    func skipBackward() {
        seek(to: engine.computeCurrentTime() - Double(AppSettings.skipInterval))
    }

    func setRate(_ rate: Float) {
        engine.setRate(rate)
        nowPlaying.updatePlayback(elapsed: engine.computeCurrentTime(), rate: engine.rate, isPlaying: engine.isPlaying)
        saveState()
    }

    /// Применить изменённые настройки экрана блокировки (шаг перемотки, режим кнопок).
    func applyLockScreenSettings() {
        nowPlaying.applyButtonMode()
    }

    // MARK: - Загрузка трека

    /// Загружает трек из очереди. Неиграбельные (DRM, битые) пропускает в направлении `direction`.
    /// Возвращает true, если удалось загрузить.
    @discardableResult
    private func loadTrack(at startIndex: Int, startAt position: Double, autoplay: Bool, direction: Int) -> Bool {
        var candidate = startIndex
        var skippedNames: [String] = []
        while candidate >= 0 && candidate < queue.count {
            guard let track = library.track(withUID: queue[candidate]) else {
                candidate += direction
                continue
            }
            if track.isProtected || !track.isPlayable {
                skippedNames.append(track.fileName)
                candidate += direction
                continue
            }
            do {
                session.activate(spokenAudio: false)
                try engine.load(url: track.fileURL, startAt: position)
                index = candidate
                currentTrack = track
                if autoplay {
                    try engine.play()
                }
                if !skippedNames.isEmpty {
                    message = skippedMessage(skippedNames)
                }
                refreshNowPlaying()
                saveState()
                return true
            } catch {
                AppLogger.shared.log("audio", "Не удалось открыть \(track.fileName): \(error.localizedDescription)")
                skippedNames.append(track.fileName)
                candidate += direction
            }
        }
        if !skippedNames.isEmpty {
            message = skippedMessage(skippedNames)
        }
        return false
    }

    private func skippedMessage(_ names: [String]) -> String {
        if names.count == 1 {
            return "Пропущен файл, который нельзя воспроизвести: \(names[0])"
        }
        return "Пропущено файлов, которые нельзя воспроизвести: \(names.count)"
    }

    private func trackDidFinish() {
        let target = index + 1
        if target < queue.count {
            _ = loadTrack(at: target, startAt: 0, autoplay: true, direction: 1)
        } else {
            // Конец очереди: возвращаемся в начало последнего трека и стоим
            engine.seek(to: 0)
            refreshNowPlaying()
            saveState()
        }
    }

    private func refreshNowPlaying() {
        guard let track = currentTrack else {
            nowPlaying.clear()
            return
        }
        nowPlaying.update(
            track: track,
            duration: engine.duration,
            elapsed: engine.computeCurrentTime(),
            rate: engine.rate,
            isPlaying: engine.isPlaying
        )
    }

    // MARK: - Сохранение и восстановление

    /// Сохраняет состояние (очередь, трек, позицию, скорость).
    func saveState() {
        guard !queue.isEmpty, index >= 0 else { return }
        let state = SavedPlaybackState(
            queue: queue,
            index: index,
            position: engine.computeCurrentTime(),
            rate: engine.rate,
            wasPlaying: engine.isPlaying,
            contextKey: nil
        )
        PlaybackStateStore.save(state)
        lastSaveTime = Date()
    }

    /// Раз в 5 секунд во время воспроизведения.
    private func periodicSave() {
        if Date().timeIntervalSince(lastSaveTime) >= 5 {
            saveState()
        }
    }

    /// Восстановление после запуска. Вызывать после первого сканирования библиотеки.
    func restoreOnLaunch() {
        guard currentTrack == nil, let saved = PlaybackStateStore.load() else { return }
        // Оставляем в очереди только треки, которые всё ещё есть в библиотеке
        let existing = saved.queue.filter { library.track(withUID: $0) != nil }
        guard !existing.isEmpty else { return }
        // Если сохранённый трек на месте — продолжаем с его позиции, иначе с начала первого
        var restoredIndex = 0
        var position: Double = 0
        if saved.index >= 0, saved.index < saved.queue.count,
           let newIndex = existing.firstIndex(of: saved.queue[saved.index]) {
            restoredIndex = newIndex
            position = saved.position
        }
        queue = existing
        engine.setRate(saved.rate)
        let autoplay = AppSettings.startContinues
        if loadTrack(at: restoredIndex, startAt: position, autoplay: autoplay, direction: 1) {
            AppLogger.shared.log("state", "Восстановлено: трек \(restoredIndex + 1) из \(existing.count), позиция \(Int(position)) с, автозапуск: \(autoplay)")
        }
    }
}
