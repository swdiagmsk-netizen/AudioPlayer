import Foundation

/// Язык интерфейса выбирается внутри приложения, независимо от языка iPhone.
/// Ключи переводов — русские строки (исходный язык разработки).
enum AppLanguage {
    static let supported = ["en", "ru", "zh-Hant", "ja", "es", "de", "fr", "pt", "hi", "ar", "bn", "id"]

    /// Языки с письмом справа налево.
    static var isRightToLeft: Bool { code == "ar" }

    /// Код выбранного языка. По умолчанию — английский.
    static var code: String {
        let saved = UserDefaults.standard.string(forKey: SettingsKeys.appLanguage) ?? "en"
        return supported.contains(saved) ? saved : "en"
    }

    static var locale: Locale { Locale(identifier: code) }

    /// Папка переводов выбранного языка внутри приложения (en.lproj и т.п.).
    static var bundle: Bundle? {
        guard code != "ru", let path = Bundle.main.path(forResource: code, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    /// Первый запуск: язык как у iPhone, если на него есть перевод, иначе английский.
    /// Системные надписи (запросы разрешений, кнопка на экране блокировки) берут язык из AppleLanguages.
    static func prepareOnLaunch() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: SettingsKeys.appLanguage) == nil else { return }
        let phone = Locale.preferredLanguages.first ?? "en"
        let chosen = match(phone)
        defaults.set(chosen, forKey: SettingsKeys.appLanguage)
        if chosen == "en" && !phone.lowercased().hasPrefix("en") {
            // Языка iPhone нет среди переводов — системные надписи тоже на английском
            defaults.set(["en"], forKey: "AppleLanguages")
        }
    }

    /// Подбирает перевод под язык iPhone, например «ru-RU» → «ru», «zh-Hant-TW» → «zh-Hant», «pt-BR» → «pt».
    static func match(_ identifier: String) -> String {
        let language = Locale.Language(identifier: identifier)
        guard let code = language.languageCode?.identifier.lowercased() else { return "en" }
        if code == "zh" {
            // Есть только традиционный китайский (Тайвань, Гонконг, Макао)
            if language.script?.identifier == "Hant" { return "zh-Hant" }
            if let region = language.region?.identifier, ["TW", "HK", "MO"].contains(region) { return "zh-Hant" }
            return "en"
        }
        return supported.contains(code) ? code : "en"
    }

    /// Смена языка: интерфейс — сразу, системные надписи — после перезапуска.
    static func apply(_ newCode: String) {
        let defaults = UserDefaults.standard
        defaults.set(newCode, forKey: SettingsKeys.appLanguage)
        defaults.set([newCode], forKey: "AppleLanguages")
    }
}

/// Перевод строки интерфейса. `key` — русский текст, `%@` — места подстановки `args`.
/// Если перевода нет, показывается русский текст.
func tr(_ key: String, _ args: String...) -> String {
    let format = AppLanguage.bundle?.localizedString(forKey: key, value: key, table: nil) ?? key
    guard !args.isEmpty else { return format }
    return String(format: format, locale: AppLanguage.locale, arguments: args.map { $0 as CVarArg })
}
