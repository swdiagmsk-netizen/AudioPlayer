import SwiftUI

/// Языки интерфейса.
enum LanguageOption {
    /// Название языка на нём самом и подпись на текущем языке интерфейса
    /// (подпись скрывается, если совпадает с названием).
    static var all: [(code: String, name: String, note: String)] {
        let list: [(String, String, String)] = [
            ("en", "English", tr("английский")),
            ("ru", "Русский", tr("Русский")),
            ("zh-Hant", "繁體中文", tr("китайский традиционный")),
            ("ja", "日本語", tr("японский")),
            ("es", "Español", tr("испанский")),
            ("de", "Deutsch", tr("немецкий")),
            ("fr", "Français", tr("французский")),
            ("pt", "Português", tr("португальский")),
            ("hi", "हिन्दी", tr("хинди")),
            ("ar", "العربية", tr("арабский")),
            ("bn", "বাংলা", tr("бенгальский")),
            ("id", "Bahasa Indonesia", tr("индонезийский"))
        ]
        return list.map { code, name, note in
            (code, name, note.lowercased() == name.lowercased() ? "" : note)
        }
    }

    static func name(for code: String) -> String {
        all.first { $0.code == code }?.name ?? "English"
    }

    /// Язык приложения задаётся независимо от языка iPhone и применяется сразу.
    static func apply(_ code: String) {
        AppLanguage.apply(code)
    }
}

/// Скины.
enum SkinOption {
    static var all: [(id: String, name: String, description: String)] { [
        ("classic", tr("Классика"), tr("ЖК-дисплей, визуализатор, компактный список")),
        ("modern", "Minimalist Modern", tr("Размытая обложка, спектр вокруг обложки")),
        ("retro", tr("Retro Cassette / Винил"), tr("Катушки кассеты или пластинка, стрелочные приборы")),
        ("car", "Car Mode", tr("Крупные кнопки и шрифт"))
    ] }

    static func name(for id: String) -> String {
        all.first { $0.id == id }?.name ?? tr("Классика")
    }
}

/// Палитра из 24 цветов (для акцента и линий визуализатора).
enum ColorPalette {
    static let colors: [String] = [
        "#FF3B30", "#FF6B3D", "#FF8A1F", "#FFB020", "#FFD23F", "#E8F542", "#A3E635", "#6CFF7E",
        "#22C55E", "#10B981", "#14B8A6", "#38E8FF", "#0EA5E9", "#2F9BFF", "#3B5BFF", "#6366F1",
        "#8B5CF6", "#A855F7", "#D946EF", "#FF4FD8", "#EC4899", "#F43F5E", "#A1A1AA", "#F5F5F5"
    ]
}

// MARK: - Язык

struct LanguageSettingsView: View {
    @AppStorage(SettingsKeys.appLanguage) private var language = "en"

    var body: some View {
        List {
            ForEach(LanguageOption.all, id: \.code) { option in
                Button {
                    guard option.code != language else { return }
                    Haptics.select()
                    // Интерфейс перерисуется сразу на новом языке
                    LanguageOption.apply(option.code)
                    language = option.code
                } label: {
                    HStack {
                        Text(option.name)
                            .foregroundStyle(.primary)
                        if !option.note.isEmpty {
                            Text(option.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if option.code == language {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .accessibilityAddTraits(option.code == language ? .isSelected : [])
            }
        }
        .navigationTitle(tr("Язык"))
        .safeAreaInset(edge: .bottom) {
            Text(tr("Запросы разрешений iOS и кнопка на экране блокировки сменят язык после перезапуска приложения."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding()
        }
    }
}

// MARK: - Внешний вид

struct AppearanceSettingsView: View {
    @AppStorage(SettingsKeys.themeMode) private var themeMode = "auto"
    @AppStorage(SettingsKeys.visualizer) private var visualizer = VisualizerKind.bars.rawValue
    @AppStorage(SettingsKeys.lineColorHex) private var lineColorHex = "#6CFF7E"
    @AppStorage(SettingsKeys.accentHex) private var accentHex = Palette.defaultAccentHex
    @AppStorage(SettingsKeys.skin) private var skin = "classic"
    @AppStorage(SettingsKeys.retroStyle) private var retroStyle = "cassette"
    @AppStorage(SettingsKeys.customBackgroundHex) private var backgroundHex = ""
    @AppStorage(SettingsKeys.customTextHex) private var textHex = ""

    @State private var showLinePalette = false
    @State private var showAccentPalette = false

    private let accentPresets = ["#FF8A1F", "#2F9BFF", "#22C55E", "#E5484D", "#8B5CF6"]
    private let linePresets = ["#6CFF7E", "#38E8FF", "#FF8A1F", "#FF4FD8", "#F5F5F5"]

    var body: some View {
        List {
            Section {
                Picker(tr("Тема"), selection: $themeMode.withHaptic()) {
                    Text(tr("Авто")).tag("auto")
                    Text(tr("Светлая")).tag("light")
                    Text(tr("Тёмная")).tag("dark")
                }
                .pickerStyle(.segmented)
            } header: {
                Text(tr("Тема оформления"))
            } footer: {
                Text(themeFooter)
            }

            Section(tr("Цвет акцента (кнопки)")) {
                colorRow(title: tr("Акцент"), presets: accentPresets, hex: $accentHex, showPalette: $showAccentPalette)
            }

            Section(tr("Скин плеера")) {
                ForEach(SkinOption.all, id: \.id) { option in
                    Button {
                        Haptics.select()
                        skin = option.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.name).foregroundStyle(.primary)
                                Text(option.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if option.id == skin {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .accessibilityAddTraits(option.id == skin ? .isSelected : [])
                }
                // Визуализатор есть только у скина «Классика» — выбор вида показываем под ним
                if skin == "classic" {
                    Picker(tr("Визуализатор"), selection: $visualizer.withHaptic()) {
                        ForEach(VisualizerKind.allCases, id: \.rawValue) { kind in
                            Text(kind.title).tag(kind.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    if visualizer == VisualizerKind.lines.rawValue {
                        colorRow(title: tr("Цвет линий"), presets: linePresets, hex: $lineColorHex, showPalette: $showLinePalette)
                    }
                }
                if skin == "retro" {
                    Picker(tr("Вид ретро"), selection: $retroStyle.withHaptic()) {
                        Text(tr("Кассета")).tag("cassette")
                        Text(tr("Винил")).tag("vinyl")
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section(tr("Свои цвета")) {
                ColorPicker(tr("Фон"), selection: hexBinding($backgroundHex, fallback: "#101215"), supportsOpacity: false)
                ColorPicker(tr("Текст"), selection: hexBinding($textHex, fallback: "#ECEEF1"), supportsOpacity: false)
                Button(tr("Сбросить на стандартную тему")) {
                    Haptics.tap()
                    accentHex = Palette.defaultAccentHex
                    lineColorHex = "#6CFF7E"
                    backgroundHex = ""
                    textHex = ""
                    skin = "classic"
                    visualizer = VisualizerKind.bars.rawValue
                }
            }
        }
        .navigationTitle(tr("Внешний вид"))
    }

    private var themeFooter: String {
        switch themeMode {
        case "light": return tr("Всегда светлая.")
        case "dark": return tr("Всегда тёмная.")
        default: return tr("Следует за настройкой iPhone: днём светлая, ночью тёмная.")
        }
    }

    /// Ряд: 5 готовых цветов + кнопка палитры; под ним — палитра на 24 цвета и «Любой цвет…».
    @ViewBuilder
    private func colorRow(title: String, presets: [String], hex: Binding<String>, showPalette: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            ForEach(presets, id: \.self) { value in
                swatch(value, selected: hex.wrappedValue.uppercased() == value.uppercased(), size: 32) {
                    Haptics.select()
                    hex.wrappedValue = value
                }
            }
            Button {
                Haptics.select()
                showPalette.wrappedValue.toggle()
            } label: {
                Circle()
                    .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("Палитра: %@", "\(title)"))
        }
        if showPalette.wrappedValue {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                ForEach(ColorPalette.colors, id: \.self) { value in
                    swatch(value, selected: hex.wrappedValue.uppercased() == value.uppercased(), size: 30) {
                        Haptics.select()
                        hex.wrappedValue = value
                    }
                }
            }
            ColorPicker(tr("Любой цвет…"), selection: hexBinding(hex, fallback: "#FF8A1F"), supportsOpacity: false)
        }
    }

    private func swatch(_ value: String, selected: Bool, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(Color(hex: value))
                .frame(width: size, height: size)
                .overlay(Circle().stroke(selected ? Color.primary : Color.clear, lineWidth: 3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("Цвет %@", "\(value)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func hexBinding(_ hex: Binding<String>, fallback: String) -> Binding<Color> {
        Binding(
            get: { Color(hex: hex.wrappedValue.isEmpty ? fallback : hex.wrappedValue) },
            set: { hex.wrappedValue = $0.hexString }
        )
    }
}
