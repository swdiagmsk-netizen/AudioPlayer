import Foundation

// Файл оставлен с прежним именем, чтобы не удалять его из репозитория вручную.
// Временный плеер этапа 0 заменён на AudioEngineManager + PlaybackController.

/// Скорости воспроизведения.
enum PlaybackSpeed {
    /// Полный список (долгое нажатие на кнопку скорости).
    static let all: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 3, 4]
    /// Быстрый цикл по нажатию: 1 → 1.5 → 2 → 3 → 4 → 1.
    static let cycle: [Float] = [1, 1.5, 2, 3, 4]

    /// Следующая скорость для короткого нажатия.
    static func next(after current: Float) -> Float {
        if let index = cycle.firstIndex(where: { abs($0 - current) < 0.01 }) {
            return cycle[(index + 1) % cycle.count]
        }
        // Текущая скорость не из цикла (например, 0.75) — ближайшая большая из цикла
        return cycle.first(where: { $0 > current }) ?? cycle[0]
    }

    /// Подпись: "1x", "1.5x", "0.75x".
    static func label(_ rate: Float) -> String {
        if abs(rate - rate.rounded()) < 0.01 {
            return "\(Int(rate.rounded()))x"
        }
        var text = String(format: "%.2f", rate)
        while text.hasSuffix("0") { text.removeLast() }
        return text + "x"
    }
}
