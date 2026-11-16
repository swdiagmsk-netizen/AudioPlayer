import Foundation
import Observation

/// Управление воспроизведением: очередь, переходы, повтор и «честный рандом»,
/// экран блокировки, прерывания, счётчик прослушиваний, аудиокниги и главы,
/// выравнивание громкости, затухание, таймер сна, сохранение состояния.
@MainActor
@Observable
final class PlaybackController {
    /// Текущий трек.
    private(set) var currentTrack: TrackRecord?
    /// Очередь (список в порядке показа + режимы).
    private(set) var queue = PlaybackQueue()
    /// Ключ списка, из которого идёт воспроизведение (см. ListID.key).
    private(set) var contextKey: String?
    /// Главы текущего трека (пусто — глав нет).
    private(set) var chapters: [ChapterInfo] = []
    /// Номер текущей главы в `chapters`.
    private(set) var currentChapterIndex: Int?
    /// Текущий трек — аудиокнига.
    private(set) var currentIsAudiobook = false
    /// Сообщение для пользователя (например, «файл защищён»). Интерфейс показывает и сбрасывает.
    var message: String?

    /// Аудиодвижок (интерфейс читает из него время, длительность, скорость).
    let engine = AudioEngineManager()
    /// Таймер сна.
    let sleepTimer = SleepTimer()
    /// Спектр для визуализатора.
    let spectrum = SpectrumAnalyzer()

    @ObservationIgnored private let library: LibraryAndBookmarkManager
    @ObservationIgnored private let session = AudioSessionController()
    @ObservationIgnored private let nowPlaying = NowPlayingController()
    @ObservationIgnored private var lastSaveTime: Date = .distantPast
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var isSetUp = false
    @ObservationIgnored private var loadToken = 0
    @ObservationIgnored private var analysisRunning = false

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
        sleepTimer.onFire = { [weak self] in
            guard let self else { return }
            self.pause()
            self.engine.setOutputVolume(1)
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
            self.session.activate(spokenAudio: self.currentIsAudiobook)
            self.refreshNowPlaying()
        }
        session.startObserving()
        nowPlaying.installCommands(target: self)
        engine.setSpectrumAnalyzer(spectrum)
    }

    /// Визуализатор нужен только когда приложение на экране (экономия батареи).
    func setVisualizerActive(_ active: Bool) {
        engine.setSpectrumAnalyzer(active ? spectrum : nil)
    }

    // MARK: - Состояние для интерфейса

    var isPlaying: Bool { engine.isPlaying }
    var repeatMode: RepeatMode { queue.repeatMode }
    var shuffleOn: Bool { queue.shuffleOn }

    var currentChapter: ChapterInfo? {
        guard let index = currentChapterIndex, chapters.indices.contains(index) else { return nil }
        return chapters[index]
    }

    // MARK: - Запуск списка

    /// Запускает список с заданного трека. `contextKey` — ключ списка (ListID.key).
    /// `position` — с какой секунды (nil — для аудиокниги с сохранённого места, иначе с начала).
    func play(items: [UUID], startUID: UUID, contextKey: String?, position: Double? = nil) {
        guard !items.isEmpty else { return }
        self.contextKey = contextKey
        queue.set(items: items, current: startUID)
        loadSkippingUnplayable(first: queue.currentUID, position: position, autoplay: true, forward: true)
    }

    /// Открыть трек на заданной секунде (закладка). Если трек в текущей очереди —
    /// очередь сохраняется, иначе играет только он.
    func playTrack(uid: UUID, at position: Double) {
        if currentTrack?.uid == uid {
            seek(to: position)
            if !engine.isPlaying { play() }
            return
        }
        if queue.items.contains(uid) {
            queue.set(items: queue.items, current: uid)
            loadSkippingUnplayable(first: uid, position: position, autoplay: true, forward: true)
        } else {
            play(items: [uid], startUID: uid, contextKey: nil, position: position)
        }
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
                loadSkippingUnplayable(first: uid, position: nil, autoplay: true, forward: true)
            }
            return
        }
        session.activate(spokenAudio: currentIsAudiobook)
        updateVolume()
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
        saveAudiobookPosition()
        saveState()
    }

    /// Возвращает аудиосессию в режим воспроизведения (после распознавания по микрофону).
    func restoreAudioSession() {
        session.activate(spokenAudio: currentIsAudiobook)
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
        if let uid = queue.advance(auto: false) {
            loadSkippingUnplayable(first: uid, position: nil, autoplay: true, forward: true)
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
            loadSkippingUnplayable(first: uid, position: nil, autoplay: true, forward: false)
        } else {
            seek(to: 0)
        }
    }

    func seek(to seconds: Double) {
        engine.seek(to: seconds)
        lastTickPosition = nil
        updateChapter()
        updateVolume()
        nowPlaying.updatePlayback(elapsed: engine.currentTime, rate: engine.rate, isPlaying: engine.isPlaying)
        saveState()
    }

    func skipForward() {
        seek(to: engine.computeCurrentTime() + Double(AppSettings.skipInterval))
    }

    func skipBackward() {
        seek(to: engine.computeCurrentTime() - Double(AppSettings.skipInterval))
    }

    /// Переход к главе.
    func goToChapter(_ chapter: ChapterInfo) {
        seek(to: chapter.start)
        if !engine.isPlaying { play() }
    }

    /// Скорость; запоминается отдельно для музыки и аудиокниг.
    func setRate(_ rate: Float) {
        engine.setRate(rate)
        AppSettings.setRate(engine.rate, audiobook: currentIsAudiobook)
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

    /// Применить изменённую настройку выравнивания громкости.
    func applyNormalizationSetting() {
        applyNormalization(for: currentTrack)
        if AppSettings.normalizeEnabled {
            analyzeLibraryLoudness()
        }
    }

    /// Трек удалён с устройства: если он играл — переходим к следующему.
    func handleDeleted(uid: UUID) {
        guard currentTrack?.uid == uid else { return }
        let wasPlaying = engine.isPlaying
        engine.stop()
        currentTrack = nil
        chapters = []
        currentChapterIndex = nil
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
    private func loadSkippingUnplayable(first: UUID?, position: Double?, autoplay: Bool, forward: Bool) -> Bool {
        var candidate = first
        var skipped: [String] = []
        var attempts = 0
        let limit = queue.items.count + 1

        while let uid = candidate, attempts < limit {
            attempts += 1
            let startPosition: Double? = attempts == 1 ? position : nil
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

    private func tryLoad(uid: UUID, position: Double?, autoplay: Bool, skipped: inout [String]) -> Bool {
        guard let track = library.track(withUID: uid) else { return false }
        if track.isProtected || !track.isPlayable {
            skipped.append(track.fileName)
            return false
        }
        // Уходя с аудиокниги, запоминаем место
        saveAudiobookPosition()

        let isBook = library.isAudiobook(track)
        let start = startPosition(for: track, isAudiobook: isBook, requested: position)
        do {
            session.activate(spokenAudio: isBook)
            try engine.load(url: track.fileURL, startAt: start)
            currentTrack = track
            currentIsAudiobook = isBook
            engine.setRate(AppSettings.rate(audiobook: isBook))
            engine.setOutputVolume(1)
            listenedSeconds = 0
            lastTickPosition = nil
            countedThisRun = false
            chapters = []
            currentChapterIndex = nil
            applyNormalization(for: track)
            loadChapters(for: track)
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

    /// С какой секунды начать. Аудиокнига без явной позиции — с сохранённого места
    /// минус откат (если книга не дослушана и настройка включена).
    private func startPosition(for track: TrackRecord, isAudiobook: Bool, requested: Double?) -> Double {
        if let requested { return requested }
        guard isAudiobook, AppSettings.rememberAudiobookPosition, !track.isFinished, track.lastPosition > 5 else {
            return 0
        }
        return max(0, track.lastPosition - Double(AppSettings.resumeRewindSeconds))
    }

    private func skippedMessage(_ names: [String]) -> String {
        if names.count == 1 {
            return "Пропущен файл, который нельзя воспроизвести: \(names[0])"
        }
        return "Пропущено файлов, которые нельзя воспроизвести: \(names.count)"
    }

    /// Трек доиграл сам: учитываются таймер сна, «повтор одного», «повтор всех» и рандом.
    private func trackDidFinish() {
        if let track = currentTrack, currentIsAudiobook {
            // Книга дослушана: в следующий раз — с начала
            track.isFinished = true
            track.lastPosition = 0
            library.saveContext("audiobookFinished")
        }
        if sleepTimer.trackDidFinish() {
            engine.setOutputVolume(1)
            stopAtEnd()
            return
        }
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
        engine.setOutputVolume(1)
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
            chapterTitle: currentChapter?.title,
            duration: engine.duration,
            elapsed: engine.computeCurrentTime(),
            rate: engine.rate,
            isPlaying: engine.isPlaying
        )
    }

    // MARK: - Главы

    private func loadChapters(for track: TrackRecord) {
        let uid = track.uid
        let url = track.fileURL
        Task { [weak self] in
            let loaded = await ChapterLoader.load(url: url)
            guard let self, self.currentTrack?.uid == uid else { return }
            self.chapters = loaded.count > 1 ? loaded : []
            self.updateChapter()
            self.refreshNowPlaying()
        }
    }

    private func updateChapter() {
        guard !chapters.isEmpty else {
            currentChapterIndex = nil
            return
        }
        let time = engine.computeCurrentTime()
        let index = chapters.lastIndex(where: { $0.start <= time + 0.25 }) ?? 0
        if index != currentChapterIndex {
            currentChapterIndex = index
            refreshNowPlaying()
        }
    }

    // MARK: - Громкость: нормализация и затухания

    private func applyNormalization(for track: TrackRecord?) {
        guard AppSettings.normalizeEnabled, let track else {
            engine.setNormalization(enabled: false, gainDB: 0)
            return
        }
        if let lufs = track.loudnessLUFS {
            engine.setNormalization(enabled: true, gainDB: LoudnessAnalyzer.gainDB(forLUFS: lufs))
            return
        }
        // Громкость ещё не измерена: пока без поправки (только лимитер), измеряем в фоне
        engine.setNormalization(enabled: true, gainDB: 0)
        let uid = track.uid
        let url = track.fileURL
        Task { [weak self] in
            let lufs = await Task.detached(priority: .utility) {
                LoudnessAnalyzer.measure(url: url)
            }.value
            guard let self, let lufs else { return }
            if let record = self.library.track(withUID: uid) {
                record.loudnessLUFS = lufs
                self.library.saveContext("loudness")
            }
            if self.currentTrack?.uid == uid, AppSettings.normalizeEnabled {
                self.engine.setNormalization(enabled: true, gainDB: LoudnessAnalyzer.gainDB(forLUFS: lufs))
            }
        }
    }

    /// Фоновое измерение громкости всей библиотеки — по одному файлу, с низким приоритетом.
    func analyzeLibraryLoudness() {
        guard AppSettings.normalizeEnabled, !analysisRunning else { return }
        analysisRunning = true
        Task { [weak self] in
            defer { self?.analysisRunning = false }
            while true {
                guard let self, AppSettings.normalizeEnabled else { return }
                guard let next = self.library.tracks.first(where: {
                    $0.loudnessLUFS == nil && $0.isPlayable && !$0.isProtected
                }) else { return }
                let uid = next.uid
                let url = next.fileURL
                let lufs = await Task.detached(priority: .background) {
                    LoudnessAnalyzer.measure(url: url)
                }.value
                if let record = self.library.track(withUID: uid) {
                    // Тишина или нечитаемый файл — без поправки (цель), чтобы не измерять снова
                    record.loudnessLUFS = lufs ?? LoudnessAnalyzer.targetLUFS
                    self.library.saveContext("loudness")
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    /// Итоговая громкость = минимум из затухания в конце трека и затухания таймера сна.
    private func updateVolume() {
        var factor: Float = 1
        let remainingInTrack = engine.duration - engine.computeCurrentTime()
        if AppSettings.fadeEndEnabled {
            let fade = Double(AppSettings.fadeEndSeconds)
            if remainingInTrack < fade, engine.duration > fade * 2 {
                factor = min(factor, Float(max(0, remainingInTrack / fade)))
            }
        }
        factor = min(factor, sleepTimer.fadeFactor())
        if sleepTimer.mode == .endOfTrack {
            let fade = Double(AppSettings.sleepFadeSeconds)
            if fade > 0, remainingInTrack < fade {
                factor = min(factor, Float(max(0, remainingInTrack / fade)))
            }
        }
        engine.setOutputVolume(factor)
    }

    // MARK: - Тик (~10 раз в секунду во время воспроизведения)

    /// Счётчик прослушиваний: +1, когда за один запуск трека прозвучала половина
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

        updateVolume()
        updateChapter()

        if Date().timeIntervalSince(lastSaveTime) >= 5 {
            saveAudiobookPosition()
            saveState()
        }
    }

    // MARK: - Сохранение и восстановление

    /// Место в аудиокниге. Последние 30 секунд — книга считается дослушанной.
    private func saveAudiobookPosition() {
        guard let track = currentTrack, currentIsAudiobook, AppSettings.rememberAudiobookPosition else { return }
        let position = engine.computeCurrentTime()
        let duration = engine.duration
        if duration > 0, duration - position <= 30 {
            track.isFinished = true
            track.lastPosition = 0
        } else {
            track.isFinished = false
            track.lastPosition = position
        }
        library.saveContext("audiobookPosition")
    }

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

    /// Сохранение при уходе в фон.
    func saveAll() {
        saveAudiobookPosition()
        saveState()
    }

    /// Восстановление после запуска. Вызывать после первого сканирования библиотеки.
    /// В режиме «Продолжить» музыка играет с сохранённой секунды (если играла при закрытии),
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

        let autoplay = AppSettings.startContinues && saved.wasPlaying
        if loadSkippingUnplayable(first: queue.currentUID, position: position, autoplay: autoplay, forward: true) {
            AppLogger.shared.log("state", "Восстановлено воспроизведение: позиция \(Int(position)) с, автозапуск: \(autoplay)")
        }
    }
}
