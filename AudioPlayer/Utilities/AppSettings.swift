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

    /// true — при запуске продолжать воспроизведение с места остановки.
    static var startContinues: Bool {
        (UserDefaults.standard.string(forKey: SettingsKeys.startMode) ?? "continue") != "idle"
    }
}
