import SwiftUI

/// Языки интерфейса.
enum LanguageOption {
    static let all: [(code: String, name: String, note: String)] = [
        ("en", "English", "по умолчанию"),
        ("ru", "Русский", ""),
        ("zh-Hant", "繁體中文", "китайский традиционный"),
        ("ja", "日本語", "японский"),
        ("es", "Español", "испанский"),
        ("de", "Deutsch", "немецкий"),
        ("fr", "Français", "французский")
    ]

    static func name(for code: String) -> String {
        all.first { $0.code == code }?.name ?? "English"
    }

    /// Язык приложения задаётся независимо от языка iPhone и применяется после перезапуска.
    static func apply(_ code: String) {
        UserDefaults.standard.set([code], forKey: "AppleLanguages")
    }
}

/// Скины.
enum SkinOption {
    static let all: [(id: String, name: String, description: String)] = [
        ("classic", "Классика", "ЖК-дисплей, визуализатор, компактный список"),
        ("modern", "Minimalist Modern", "Размытая обложка, спектр вокруг обложки"),
        ("retro", "Retro Cassette / Винил", "Катушки кассеты или пластинка, стрелочные приборы"),
        ("car", "Car Mode", "Крупные кнопки и шрифт")
    ]

    static func name(for id: String) -> String {
        all.first { $0.id == id }?.name ?? "Классика"
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
    @State private var showRestart = false

    var body: some View {
        List {
            ForEach(LanguageOption.all, id: \.code) { option in
                Button {
                    guard option.code != language else { return }
                    Haptics.select()
                    language = option.code
                    LanguageOption.apply(option.code)
                    showRestart = true
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
        .navigationTitle("Язык")
        .alert("Язык изменён", isPresented: $showRestart) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Закройте приложение (смахните его вверх в списке открытых) и откройте снова — интерфейс переключится.")
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
                Picker("Тема", selection: $themeMode.withHaptic()) {
                    Text("Авто").tag("auto")
                    Text("Светлая").tag("light")
                    Text("Тёмная").tag("dark")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Тема оформления")
            } footer: {
                Text(themeFooter)
            }

            Section("Визуализатор") {
                Picker("Вид", selection: $visualizer.withHaptic()) {
                    ForEach(VisualizerKind.allCases, id: \.rawValue) { kind in
                        Text(kind.title).tag(kind.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                if visualizer == VisualizerKind.lines.rawValue {
                    colorRow(title: "Цвет линий", presets: linePresets, hex: $lineColorHex, showPalette: $showLinePalette)
                }
            }

            Section("Цвет акцента (кнопки)") {
                colorRow(title: "Акцент", presets: accentPresets, hex: $accentHex, showPalette: $showAccentPalette)
            }

            Section("Скин плеера") {
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
                if skin == "retro" {
                    Picker("Вид ретро", selection: $retroStyle.withHaptic()) {
                        Text("Кассета").tag("cassette")
                        Text("Винил").tag("vinyl")
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section("Свои цвета") {
                ColorPicker("Фон", selection: hexBinding($backgroundHex, fallback: "#101215"), supportsOpacity: false)
                ColorPicker("Текст", selection: hexBinding($textHex, fallback: "#ECEEF1"), supportsOpacity: false)
                Button("Сбросить на стандартную тему") {
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
        .navigationTitle("Внешний вид")
    }

    private var themeFooter: String {
        switch themeMode {
        case "light": return "Всегда светлая."
        case "dark": return "Всегда тёмная."
        default: return "Следует за настройкой iPhone: днём светлая, ночью тёмная."
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
            .accessibilityLabel("Палитра: \(title)")
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
            ColorPicker("Любой цвет…", selection: hexBinding(hex, fallback: "#FF8A1F"), supportsOpacity: false)
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
        .accessibilityLabel("Цвет \(value)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func hexBinding(_ hex: Binding<String>, fallback: String) -> Binding<Color> {
        Binding(
            get: { Color(hex: hex.wrappedValue.isEmpty ? fallback : hex.wrappedValue) },
            set: { hex.wrappedValue = $0.hexString }
        )
    }
}
