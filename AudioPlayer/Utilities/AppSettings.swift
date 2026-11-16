import Foundation

/// Ключи настроек (`@AppStorage` в интерфейсе и UserDefaults в логике используют одни и те же).
enum SettingsKeys {
    /// Шаг перемотки, секунды (1–600), по умолчанию 15.
    static let skipInterval = "settings.skipInterval"
    /// Кнопки на экране блокировки: "skip" (перемотка ±N) или "tracks" (пред./след. трек).
    static let lockScreenMode = "settings.lockScreenMode"
    /// Поведение при запуске: "continue" (продолжить) или "idle" (ничего не воспроизводить).
    static let startMode = "settings.startMode"
    /// Новые файлы добавлять в начало списка (иначе — в конец).
    static let insertAtStart = "settings.insertAtStart"
    /// Тема: "auto", "light", "dark".
    static let themeMode = "settings.themeMode"
    /// Цвет акцента, hex "#RRGGBB".
    static let accentHex = "settings.accentHex"
    /// Сердечко «Супер!» в строках списка.
    static let showHeart = "settings.showHeart"
    /// Счётчик прослушиваний в строках списка.
    static let showPlayCount = "settings.showPlayCount"
    /// Показывать вкладку ★.
    static let showHitTab = "settings.showHitTab"
    /// Показывать вкладку ♥.
    static let showSuperTab = "settings.showSuperTab"
    /// Запоминать последнюю открытую папку.
    static let rememberFolder = "settings.rememberFolder"
    /// Поисковик для «Найти в интернете»: "google", "yandex", "duckduckgo".
    static let searchEngine = "settings.searchEngine"
    /// Эквалайзер включён.
    static let eqEnabled = "settings.eq.enabled"
    /// Название выбранного пресета ("Ручная" — ручная настройка).
    static let eqPresetName = "settings.eq.preset"
    /// Усиления 10 полос, JSON-массив чисел.
    static let eqGains = "settings.eq.gains"
    /// Предусилитель, дБ.
    static let eqPreamp = "settings.eq.preamp"
    /// Выравнивание громкости.
    static let normalize = "settings.normalize"
    /// Плавное затухание в конце трека.
    static let fadeEnd = "settings.fadeEnd"
    /// Длительность затухания в конце трека, с (1–10).
    static let fadeEndSeconds = "settings.fadeEndSeconds"
    /// Затухание перед паузой по таймеру сна, с (0–60).
    static let sleepFadeSeconds = "settings.sleepFadeSeconds"
    /// Запоминать позицию в аудиокнигах.
    static let rememberAudiobookPosition = "settings.audiobook.remember"
    /// С какой длительности файл считается аудиокнигой, минуты.
    static let audiobookThresholdMinutes = "settings.audiobook.threshold"
    /// Откат при возобновлении аудиокниги, с.
    static let resumeRewindSeconds = "settings.audiobook.rewind"
    /// Скорость для музыки и для аудиокниг (хранятся отдельно).
    static let rateMusic = "state.rate.music"
    static let rateAudiobook = "state.rate.audiobook"
    /// Скин: "classic", "modern", "retro", "car".
    static let skin = "settings.skin"
    /// Вид ретро-скина: "cassette" или "vinyl".
    static let retroStyle = "settings.retroStyle"
    /// Визуализатор: "bars", "needles", "lines".
    static let visualizer = "settings.visualizer"
    /// Цвет тонких линий визуализатора, hex.
    static let lineColorHex = "settings.lineColorHex"
    /// Свой цвет фона и текста, hex ("" — стандартный).
    static let customBackgroundHex = "settings.customBackgroundHex"
    static let customTextHex = "settings.customTextHex"
    /// Вибрация (тактильный отклик).
    static let haptics = "settings.haptics"
    /// Разрешать дубликаты.
    static let allowDuplicates = "settings.allowDuplicates"
    /// Язык приложения: "en", "ru", "zh-Hant", "ja", "es", "de", "fr".
    static let appLanguage = "settings.appLanguage"
    /// Последняя открытая вкладка (ListID.key).
    static let lastListKey = "ui.lastListKey"
    /// Последняя открытая папка.
    static let lastFolder = "ui.lastFolder"
}

/// Чтение настроек из логики (не из SwiftUI) с безопасными значениями по умолчанию.
enum AppSettings {
    static var skipInterval: Int {
        let value = UserDefaults.standard.integer(forKey: SettingsKeys.skipInterval)
        if value <= 0 { return 15 }
        return min(value, 600)
    }

    /// true — на экране блокировки перемотка ±N, false — переход между треками.
    static var lockScreenUsesSkip: Bool {
        (UserDefaults.standard.string(forKey: SettingsKeys.lockScreenMode) ?? "skip") != "tracks"
    }

    /// true — новые файлы встают в начало списка при ручном порядке.
    static var insertNewAtStart: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.insertAtStart)
    }

    /// Адрес поиска в интернете по строке запроса.
    static func searchURL(for query: String) -> URL? {
        let engine = UserDefaults.standard.string(forKey: SettingsKeys.searchEngine) ?? "google"
        var components: URLComponents
        switch engine {
        case "yandex":
            components = URLComponents(string: "https://yandex.ru/search/")!
            components.queryItems = [URLQueryItem(name: "text", value: query)]
        case "duckduckgo":
            components = URLComponents(string: "https://duckduckgo.com/")!
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        default:
            components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        }
        return components.url
    }

    private static func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? value : UserDefaults.standard.bool(forKey: key)
    }

    private static func int(_ key: String, default value: Int) -> Int {
        UserDefaults.standard.object(forKey: key) == nil ? value : UserDefaults.standard.integer(forKey: key)
    }

    static var normalizeEnabled: Bool { bool(SettingsKeys.normalize, default: true) }
    static var fadeEndEnabled: Bool { bool(SettingsKeys.fadeEnd, default: false) }
    static var fadeEndSeconds: Int { min(max(int(SettingsKeys.fadeEndSeconds, default: 5), 1), 10) }
    static var sleepFadeSeconds: Int { min(max(int(SettingsKeys.sleepFadeSeconds, default: 15), 0), 60) }
    static var rememberAudiobookPosition: Bool { bool(SettingsKeys.rememberAudiobookPosition, default: true) }
    static var audiobookThresholdMinutes: Int { max(int(SettingsKeys.audiobookThresholdMinutes, default: 20), 1) }
    static var resumeRewindSeconds: Int { min(max(int(SettingsKeys.resumeRewindSeconds, default: 3), 0), 30) }

    /// Сохранённая скорость для музыки или аудиокниг.
    static func rate(audiobook: Bool) -> Float {
        let value = UserDefaults.standard.float(forKey: audiobook ? SettingsKeys.rateAudiobook : SettingsKeys.rateMusic)
        return value > 0 ? value : 1
    }

    static func setRate(_ rate: Float, audiobook: Bool) {
        UserDefaults.standard.set(rate, forKey: audiobook ? SettingsKeys.rateAudiobook : SettingsKeys.rateMusic)
    }

    static var hapticsEnabled: Bool { bool(SettingsKeys.haptics, default: false) }
    static var allowDuplicates: Bool { bool(SettingsKeys.allowDuplicates, default: true) }

    /// true — при запуске продолжать воспроизведение с места остановки.
    static var startContinues: Bool {
        (UserDefaults.standard.string(forKey: SettingsKeys.startMode) ?? "continue") != "idle"
    }
}
