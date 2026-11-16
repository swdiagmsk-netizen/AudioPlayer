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
