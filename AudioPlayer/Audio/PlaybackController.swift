import Foundation
import Observation

/// Управление воспроизведением: очередь, переходы, повтор и «честный рандом»,
/// экран блокировки, прерывания, счётчик прослушиваний и сохранение состояния.
@MainActor
@Observable
final class PlaybackController {
    /// Текущий трек.
    private(set) var currentTrack: TrackRecord?
    /// Очередь (список в порядке показа + режимы).
    private(set) var queue = PlaybackQueue()
    /// Ключ списка, из которого идёт воспроизведение (см. ListID.key).
    private(set) var contextKey: String?
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

    // Счётчик прослушиваний: сколько секунд трека реально прозвучало за этот запуск
    @ObservationIgnored private var listenedSeconds: Double = 0
    @ObservationIgnored private var lastTickPosition: Double?
    @ObservationIgnored private var countedThisRun = false

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
            self?.tick()
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

    // MARK: - Состояние для интерфейса

    var isPlaying: Bool { engine.isPlaying }
    var repeatMode: RepeatMode { queue.repeatMode }
    var shuffleOn: Bool { queue.shuffleOn }

    // MARK: - Запуск списка

    /// Запускает список с заданного трека. `contextKey` — ключ списка (ListID.key).
    func play(items: [UUID], startUID: UUID, contextKey: String?) {
        guard !items.isEmpty else { return }
        self.contextKey = contextKey
        queue.set(items: items, current: startUID)
        loadSkippingUnplayable(first: queue.currentUID, position: 0, autoplay: true, forward: true)
    }

    /// Список на экране изменился (добавили, удалили, пересортировали) —
    /// очередь подстраивается, текущий трек продолжает играть.
    func syncQueue(items: [UUID], contextKey: String?) {
        guard contextKey == self.contextKey, !queue.isEmpty else { return }
        queue.updateItems(items)
        saveState()
    }

    // MARK: - Кнопки

    func play() {
        guard engine.isLoaded else {
            if let uid = queue.currentUID {
                loadSkippingUnplayable(first: uid, position: 0, autoplay: true, forward: true)
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
        lastTickPosition = nil
        nowPlaying.updatePlayback(elapsed: engine.currentTime, rate: engine.rate, isPlaying: engine.isPlaying)
        saveState()
    }

    func pause() {
        engine.pause()
        lastTickPosition = nil
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

    /// Кнопка «Следующий»: переключает трек даже при «повторе одного».
    func next() {
        guard !queue.isEmpty else { return }
        let wasPlaying = engine.isPlaying
        if let uid = queue.advance(auto: false) {
            loadSkippingUnplayable(first: uid, position: 0, autoplay: wasPlaying || currentTrack != nil, forward: true)
        } else {
            stopAtEnd()
        }
    }

    /// Кнопка «Предыдущий»: если прошло больше 3 секунд — в начало трека, иначе — предыдущий.
    func previous() {
        guard !queue.isEmpty else { return }
        if engine.computeCurrentTime() > 3 {
            seek(to: 0)
            return
        }
        if let uid = queue.goBack() {
            loadSkippingUnplayable(first: uid, position: 0, autoplay: true, forward: false)
        } else {
            seek(to: 0)
        }
    }

    func seek(to seconds: Double) {
        engine.seek(to: seconds)
        lastTickPosition = nil
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

    /// Кнопка «Честный рандом».
    func toggleShuffle() {
        queue.setShuffle(!queue.shuffleOn)
        saveState()
    }

    /// Кнопка повтора: Off → All → One → Off.
    func cycleRepeat() {
        queue.repeatMode = queue.repeatMode.next
        saveState()
    }

    /// Применить изменённые настройки экрана блокировки (шаг перемотки, режим кнопок).
    func applyLockScreenSettings() {
        nowPlaying.applyButtonMode()
    }

    /// Трек удалён с устройства: если он играл — переходим к следующему.
    func handleDeleted(uid: UUID) {
        guard currentTrack?.uid == uid else { return }
        let wasPlaying = engine.isPlaying
        engine.stop()
        currentTrack = nil
        if let nextUID = queue.advance(auto: false), nextUID != uid {
            loadSkippingUnplayable(first: nextUID, position: 0, autoplay: wasPlaying, forward: true)
        } else {
            nowPlaying.clear()
        }
    }

    // MARK: - Загрузка трека

    /// Загружает трек; неиграбельные (DRM, битые, удалённые) пропускает,
    /// двигаясь по очереди вперёд или назад.
    @discardableResult
    private func loadSkippingUnplayable(first: UUID?, position: Double, autoplay: Bool, forward: Bool) -> Bool {
        var candidate = first
        var skipped: [String] = []
        var attempts = 0
        let limit = queue.items.count + 1

        while let uid = candidate, attempts < limit {
            attempts += 1
            let startPosition = attempts == 1 ? position : 0
            if tryLoad(uid: uid, position: startPosition, autoplay: autoplay, skipped: &skipped) {
                if !skipped.isEmpty {
                    message = skippedMessage(skipped)
                }
                return true
            }
            candidate = forward ? queue.advance(auto: false) : queue.goBack()
        }

        if !skipped.isEmpty {
            message = skippedMessage(skipped)
        }
        return false
    }

    private func tryLoad(uid: UUID, position: Double, autoplay: Bool, skipped: inout [String]) -> Bool {
        guard let track = library.track(withUID: uid) else { return false }
        if track.isProtected || !track.isPlayable {
            skipped.append(track.fileName)
            return false
        }
        do {
            session.activate(spokenAudio: false)
            try engine.load(url: track.fileURL, startAt: position)
            currentTrack = track
            listenedSeconds = 0
            lastTickPosition = nil
            countedThisRun = false
            if autoplay {
                try engine.play()
            }
            refreshNowPlaying()
            saveState()
            return true
        } catch {
            AppLogger.shared.log("audio", "Не удалось открыть \(track.fileName): \(error.localizedDescription)")
            skipped.append(track.fileName)
            return false
        }
    }

    private func skippedMessage(_ names: [String]) -> String {
        if names.count == 1 {
            return "Пропущен файл, который нельзя воспроизвести: \(names[0])"
        }
        return "Пропущено файлов, которые нельзя воспроизвести: \(names.count)"
    }

    /// Трек доиграл сам: учитываются «повтор одного», «повтор всех» и рандом.
    private func trackDidFinish() {
        if let uid = queue.advance(auto: true) {
            loadSkippingUnplayable(first: uid, position: 0, autoplay: true, forward: true)
        } else {
            stopAtEnd()
        }
    }

    /// Список закончился: встаём в начало текущего трека на паузе.
    private func stopAtEnd() {
        engine.stop()
        engine.seek(to: 0)
        lastTickPosition = nil
        refreshNowPlaying()
        saveState()
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

    // MARK: - Счётчик прослушиваний

    /// Вызывается ~10 раз в секунду во время воспроизведения.
    /// Прослушивание засчитывается, когда за один запуск трека прозвучала половина
    /// его длительности. Перемотка не считается: большие скачки позиции игнорируются.
    private func tick() {
        let position = engine.currentTime
        if let last = lastTickPosition {
            let delta = position - last
            if delta > 0, delta < 1.5 {
                listenedSeconds += delta
            }
        }
        lastTickPosition = position

        if !countedThisRun, let track = currentTrack, engine.duration > 0,
           listenedSeconds >= engine.duration / 2 {
            countedThisRun = true
            track.playCount += 1
            track.lastPlayedAt = Date()
            library.saveContext("playCount")
        }

        if Date().timeIntervalSince(lastSaveTime) >= 5 {
            saveState()
        }
    }

    // MARK: - Сохранение и восстановление

    /// Сохраняет очередь, режимы, позицию и скорость.
    func saveState() {
        guard !queue.isEmpty, queue.currentUID != nil else { return }
        let state = SavedPlaybackState(
            queue: queue,
            position: engine.computeCurrentTime(),
            rate: engine.rate,
            wasPlaying: engine.isPlaying,
            contextKey: contextKey
        )
        PlaybackStateStore.save(state)
        lastSaveTime = Date()
    }

    /// Восстановление после запуска. Вызывать после первого сканирования библиотеки.
    /// В режиме «Продолжить» музыка играет с сохранённой секунды,
    /// в режиме «Ничего не воспроизводить» — трек открыт, но стоит на паузе.
    func restoreOnLaunch() {
        guard currentTrack == nil, let saved = PlaybackStateStore.load() else { return }
        var restored = saved.queue
        let existing = restored.items.filter { library.track(withUID: $0) != nil }
        guard !existing.isEmpty else { return }

        var position = saved.position
        if let current = restored.currentUID, existing.contains(current) {
            restored.updateItems(existing)
        } else {
            // Сохранённого трека больше нет — начинаем с первого в списке
            restored.set(items: existing, current: nil)
            position = 0
        }
        queue = restored
        contextKey = saved.contextKey
        engine.setRate(saved.rate)

        let autoplay = AppSettings.startContinues && saved.wasPlaying
        if loadSkippingUnplayable(first: queue.currentUID, position: position, autoplay: autoplay, forward: true) {
            AppLogger.shared.log("state", "Восстановлено воспроизведение: позиция \(Int(position)) с, автозапуск: \(autoplay)")
        }
    }
}
