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

    /// true — при запуске продолжать воспроизведение с места остановки.
    static var startContinues: Bool {
        (UserDefaults.standard.string(forKey: SettingsKeys.startMode) ?? "continue") != "idle"
    }
}
