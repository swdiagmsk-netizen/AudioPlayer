import SwiftUI
import UIKit

extension Color {
    /// Строка "#RRGGBB" для сохранения в настройках.
    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        func clamp(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }

    /// Цвет из строки "#RRGGBB" или "RRGGBB". Неверная строка — серый.
    init(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        var value: UInt64 = 0
        guard text.count == 6, Scanner(string: text).scanHexInt64(&value) else {
            self = .gray
            return
        }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}

/// Цвета интерфейса для светлой и тёмной темы (из согласованного макета).
struct Palette: Sendable {
    var background: Color
    var panel: Color
    var line: Color
    var text: Color
    var secondaryText: Color
    var button: Color
    var sliderTrack: Color
    /// Подсветка играющей строки.
    var rowCurrent: Color
    /// Подсветка найденной поиском строки.
    var rowFound: Color
    var accent: Color
    /// Цвет значков на кнопке цвета акцента.
    var onAccent: Color

    /// ЖК-дисплей — одинаковый в обеих темах.
    static let lcdBackground = Color(hex: "#070A08")
    static let lcdBorder = Color(hex: "#1E2A20")
    static let lcdText = Color(hex: "#6CFF7E")
    static let lcdDim = Color(hex: "#3FAF4F")

    static let defaultAccentHex = "#FF8A1F"
    static let heart = Color(hex: "#FF4D6D")
    static let danger = Color(hex: "#E5484D")

    /// Цвета с учётом своих цветов фона и текста из настроек ("" — стандартные).
    static func make(dark: Bool, accentHex: String, backgroundHex: String, textHex: String) -> Palette {
        var palette = make(dark: dark, accentHex: accentHex)
        if !backgroundHex.isEmpty {
            palette.background = Color(hex: backgroundHex)
        }
        if !textHex.isEmpty {
            palette.text = Color(hex: textHex)
        }
        return palette
    }

    static func make(dark: Bool, accentHex: String) -> Palette {
        let accent = Color(hex: accentHex)
        if dark {
            return Palette(
                background: Color(hex: "#101215"),
                panel: Color(hex: "#181B20"),
                line: Color(hex: "#2A2F36"),
                text: Color(hex: "#ECEEF1"),
                secondaryText: Color(hex: "#9BA3AE"),
                button: Color(hex: "#23272D"),
                sliderTrack: Color(hex: "#2E333A"),
                rowCurrent: Color(hex: "#2B2219"),
                rowFound: Color(hex: "#1D2A3A"),
                accent: accent,
                onAccent: Color(hex: "#1A0E00")
            )
        }
        return Palette(
            background: Color(hex: "#F2F3F5"),
            panel: Color(hex: "#FFFFFF"),
            line: Color(hex: "#DADDE2"),
            text: Color(hex: "#15181C"),
            secondaryText: Color(hex: "#5C6470"),
            button: Color(hex: "#E7E9ED"),
            sliderTrack: Color(hex: "#D5D9DF"),
            rowCurrent: Color(hex: "#FFEBD6"),
            rowFound: Color(hex: "#DCEBFF"),
            accent: accent,
            onAccent: Color(hex: "#1A0E00")
        )
    }
}

extension EnvironmentValues {
    /// Текущие цвета интерфейса.
    @Entry var palette: Palette = Palette.make(dark: true, accentHex: Palette.defaultAccentHex)
}

/// Кнопка, которая при нажатии темнеет и чуть «вдавливается» (кнопка Play).
struct PressDarkenStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.18 : 0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Форматирование времени: "3:05", "1:02:03".
enum TimeText {
    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
