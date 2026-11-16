import SwiftUI

/// Настройки. Сейчас — тема и основные пункты; полный экран
/// со всеми разделами по макету появится на этапе 6.
struct SettingsView: View {
    let container: AppContainer

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.themeMode) private var themeMode = "auto"
    @AppStorage(SettingsKeys.showHeart) private var showHeart = true
    @AppStorage(SettingsKeys.showPlayCount) private var showPlayCount = true
    @AppStorage(SettingsKeys.showHitTab) private var showHitTab = true
    @AppStorage(SettingsKeys.showSuperTab) private var showSuperTab = true
    @State private var showLog = false
    @AppStorage(SettingsKeys.normalize) private var normalize = true
    @AppStorage(SettingsKeys.fadeEnd) private var fadeEnd = false
    @AppStorage(SettingsKeys.fadeEndSeconds) private var fadeEndSeconds = 5
    @AppStorage(SettingsKeys.rememberAudiobookPosition) private var rememberBooks = true
    @AppStorage(SettingsKeys.audiobookThresholdMinutes) private var bookThreshold = 20
    @AppStorage(SettingsKeys.resumeRewindSeconds) private var rewindSeconds = 3

    var body: some View {
        NavigationStack {
            Form {
                Section("Внешний вид") {
                    Picker("Тема", selection: $themeMode) {
                        Text("Авто").tag("auto")
                        Text("Светлая").tag("light")
                        Text("Тёмная").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }
                Section("Звук и воспроизведение") {
                    Toggle("Выравнивание громкости", isOn: $normalize)
                        .onChange(of: normalize) { _, _ in
                            container.playback.applyNormalizationSetting()
                        }
                    Toggle("Плавное затухание в конце трека", isOn: $fadeEnd)
                    if fadeEnd {
                        Stepper("Длительность затухания: \(fadeEndSeconds) с", value: $fadeEndSeconds, in: 1...10)
                    }
                }
                Section("Аудиокниги") {
                    Toggle("Запоминать позицию", isOn: $rememberBooks)
                    Picker("Аудиокнига — файлы от", selection: $bookThreshold) {
                        Text("10 мин").tag(10)
                        Text("20 мин").tag(20)
                        Text("30 мин").tag(30)
                        Text("60 мин").tag(60)
                    }
                    Picker("Откат при возобновлении", selection: $rewindSeconds) {
                        Text("0 с").tag(0)
                        Text("3 с").tag(3)
                        Text("5 с").tag(5)
                        Text("10 с").tag(10)
                    }
                }
                Section("Библиотека") {
                    Toggle("Сердечко «Супер!» в строках", isOn: $showHeart)
                    Toggle("Счётчик прослушиваний", isOn: $showPlayCount)
                    Toggle("Показывать вкладку ★", isOn: $showHitTab)
                    Toggle("Показывать вкладку ♥", isOn: $showSuperTab)
                }
                Section("О приложении") {
                    Button("Журнал отладки") {
                        showLog = true
                    }
                    HStack {
                        Text("Версия")
                        Spacer()
                        Text(versionText)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showLog) {
                DebugLogView()
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (сборка \(build))"
    }
}
