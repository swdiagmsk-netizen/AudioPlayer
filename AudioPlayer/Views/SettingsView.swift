import SwiftUI

/// Настройки: главная страница — 6 разделов кнопками, внизу «Память» и версия.
struct SettingsView: View {
    let container: AppContainer

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @AppStorage(SettingsKeys.appLanguage) private var language = "en"
    @AppStorage(SettingsKeys.themeMode) private var themeMode = "auto"
    @AppStorage(SettingsKeys.skin) private var skin = "classic"
    @AppStorage(SettingsKeys.visualizer) private var visualizer = VisualizerKind.bars.rawValue
    @AppStorage(SettingsKeys.normalize) private var normalize = true
    @AppStorage(SettingsKeys.fadeEnd) private var fadeEnd = false
    @AppStorage(SettingsKeys.haptics) private var haptics = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    sectionLink(tr("Язык"), value: LanguageOption.name(for: language), icon: "character.bubble", tint: Color(hex: "#2F9BFF")) {
                        LanguageSettingsView()
                    }
                    sectionLink(tr("Внешний вид"), value: appearanceSummary, icon: "circle.lefthalf.filled", tint: Color(hex: "#8B5CF6")) {
                        AppearanceSettingsView()
                    }
                    sectionLink(tr("Звук и воспроизведение"), value: soundSummary, icon: "music.note", tint: Color(hex: "#FF8A1F")) {
                        SoundSettingsView(container: container)
                    }
                    sectionLink(tr("Библиотека и плейлисты"), value: tr("Плейлисты, ★ и ♥, дубликаты, счётчик"), icon: "books.vertical", tint: Color(hex: "#22C55E")) {
                        LibrarySettingsView(container: container)
                    }
                    sectionLink(tr("Помощь"), value: tr("Инструкция, письмо разработчику, друзьям"), icon: "questionmark.circle", tint: Color(hex: "#14B8A6")) {
                        HelpSettingsView()
                    }
                    sectionLink(tr("О приложении"), value: tr("Версия, форматы, кэш обложек"), icon: "info.circle", tint: Color(hex: "#5C6470")) {
                        AboutSettingsView(container: container)
                    }
                }

                Section(tr("Память")) {
                    StorageInfoView()
                }

                Section {
                    Text("PlayMyDisk \(AppInfo.versionText)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(tr("Настройки"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Готово")) {
                        Haptics.tap()
                        dismiss()
                    }
                }
            }
        }
        .tint(palette.accent)
    }

    private var appearanceSummary: String {
        let theme = ["auto": tr("Авто"), "light": tr("Светлая"), "dark": tr("Тёмная")][themeMode] ?? tr("Авто")
        let skinName = SkinOption.name(for: skin)
        let viz = (VisualizerKind(rawValue: visualizer) ?? .bars).title
        return "\(theme) · \(skinName) · \(viz)"
    }

    private var soundSummary: String {
        func onOff(_ value: Bool) -> String { value ? tr("вкл") : tr("выкл") }
        return tr("Нормализация %@ · затухание %@ · вибрация %@", "\(onOff(normalize))", "\(onOff(fadeEnd))", "\(onOff(haptics))")
    }

    private func sectionLink<Destination: View>(
        _ title: String,
        value: String,
        icon: String,
        tint: Color,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
                .onAppear { Haptics.select() }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(tint))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Версия приложения.
enum AppInfo {
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return tr("%@ (сборка %@)", "\(version)", "\(build)")
    }

    static let developerEmail = "swdiag.msk@gmail.com"
    static let downloadPage = URL(string: "https://github.com/swdiagmsk-netizen/AudioPlayer/releases/latest")!
}
