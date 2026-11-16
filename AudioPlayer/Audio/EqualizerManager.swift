import Foundation
import SwiftData
import Observation

/// Пресет эквалайзера (встроенный или пользовательский).
struct EQPresetItem: Identifiable, Equatable {
    let id: String
    let name: String
    let gains: [Float]
    /// Пользовательский пресет (можно удалить).
    let isUser: Bool
}

/// Состояние эквалайзера: включён ли, пресет, 10 полос, предусилитель, свои пресеты.
/// Всё сохраняется автоматически и переживает перезапуск.
@MainActor
@Observable
final class EqualizerManager {
    static let manualName = "Ручная"

    /// Встроенные пресеты (дБ, от 32 Гц до 16 кГц).
    static let builtIn: [EQPresetItem] = [
        EQPresetItem(id: "flat", name: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], isUser: false),
        EQPresetItem(id: "rock", name: "Rock", gains: [5, 4, 3, 1, -1, -1, 1, 3, 4, 5], isUser: false),
        EQPresetItem(id: "pop", name: "Pop", gains: [-1, 1, 3, 4, 3, 1, -1, -1, 0, 1], isUser: false),
        EQPresetItem(id: "jazz", name: "Jazz", gains: [3, 2, 1, 2, -1, -1, 0, 1, 2, 3], isUser: false),
        EQPresetItem(id: "classical", name: "Classical", gains: [4, 3, 2, 1, -1, -1, 0, 2, 3, 4], isUser: false),
        EQPresetItem(id: "bass", name: "Bass Boost", gains: [7, 6, 5, 3, 1, 0, 0, 0, 0, 0], isUser: false),
        EQPresetItem(id: "vocal", name: "Vocal / Подкаст", gains: [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1], isUser: false)
    ]

    private(set) var isEnabled: Bool
    private(set) var presetName: String
    private(set) var gains: [Float]
    private(set) var preamp: Float
    private(set) var userPresets: [EQPresetItem] = []

    /// Вызывается при любом изменении — применить к движку.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: SettingsKeys.eqEnabled) == nil ? true : defaults.bool(forKey: SettingsKeys.eqEnabled)
        presetName = defaults.string(forKey: SettingsKeys.eqPresetName) ?? "Flat"
        preamp = defaults.float(forKey: SettingsKeys.eqPreamp)
        if let text = defaults.string(forKey: SettingsKeys.eqGains),
           let data = text.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([Float].self, from: data),
           decoded.count == 10 {
            gains = decoded
        } else {
            gains = Array(repeating: 0, count: 10)
        }
        reloadUserPresets()
    }

    var allPresets: [EQPresetItem] { Self.builtIn + userPresets }

    var currentPresetIsUser: Bool {
        userPresets.contains { $0.name == presetName }
    }

    // MARK: - Изменения

    func setEnabled(_ value: Bool) {
        isEnabled = value
        persist()
    }

    func select(_ preset: EQPresetItem) {
        presetName = preset.name
        gains = preset.gains
        persist()
    }

    /// Ручное движение ползунка: пресет становится «Ручная».
    func setGain(_ value: Float, band: Int) {
        guard gains.indices.contains(band) else { return }
        gains[band] = min(max(value, -12), 12)
        presetName = Self.manualName
        persist()
    }

    func setPreamp(_ value: Float) {
        preamp = min(max(value, -12), 6)
        persist()
    }

    func resetFlat() {
        presetName = "Flat"
        gains = Array(repeating: 0, count: 10)
        preamp = 0
        persist()
    }

    /// Сохраняет текущие ползунки как свой пресет.
    func saveCurrent(as name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let preset = EQPreset(name: clean, gains: gains)
        context.insert(preset)
        save()
        presetName = clean
        reloadUserPresets()
        persist()
    }

    /// Удаляет выбранный пользовательский пресет.
    func deleteCurrentUserPreset() {
        let all = (try? context.fetch(FetchDescriptor<EQPreset>())) ?? []
        for preset in all where preset.name == presetName {
            context.delete(preset)
        }
        save()
        reloadUserPresets()
        resetFlat()
    }

    // MARK: - Внутреннее

    private func reloadUserPresets() {
        let all = (try? context.fetch(FetchDescriptor<EQPreset>())) ?? []
        userPresets = all
            .sorted { $0.createdAt < $1.createdAt }
            .map { EQPresetItem(id: $0.uid.uuidString, name: $0.name, gains: $0.gains, isUser: true) }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(isEnabled, forKey: SettingsKeys.eqEnabled)
        defaults.set(presetName, forKey: SettingsKeys.eqPresetName)
        defaults.set(preamp, forKey: SettingsKeys.eqPreamp)
        if let data = try? JSONEncoder().encode(gains) {
            defaults.set(String(decoding: data, as: UTF8.self), forKey: SettingsKeys.eqGains)
        }
        onChange?()
    }

    private func save() {
        do {
            try context.save()
        } catch {
            AppLogger.shared.log("db", "Ошибка сохранения пресета: \(error.localizedDescription)")
        }
    }
}
