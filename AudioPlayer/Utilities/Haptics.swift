import SwiftUI
import UIKit

/// Тактильный отклик. Работает, только если в настройках включена «Вибрация»:
/// Play/Пауза и любые действия в меню и настройках.
@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let selection = UISelectionFeedbackGenerator()

    /// Нажатие кнопки (Play/Пауза, пункты меню).
    static func tap() {
        guard AppSettings.hapticsEnabled else { return }
        light.impactOccurred()
    }

    /// Выбор пункта, переключатель, флажок, переход между разделами.
    static func select() {
        guard AppSettings.hapticsEnabled else { return }
        selection.selectionChanged()
    }
}

extension Binding {
    /// Тот же Binding, но при каждом изменении — тактильный отклик.
    @MainActor
    func withHaptic() -> Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: { newValue in
                wrappedValue = newValue
                Haptics.select()
            }
        )
    }
}
