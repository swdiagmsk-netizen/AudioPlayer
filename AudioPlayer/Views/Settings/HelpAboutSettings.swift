import SwiftUI
import MessageUI
import UIKit

// MARK: - Помощь

struct HelpSettingsView: View {
    @Environment(\.openURL) private var openURL
    @State private var showMail = false
    @State private var copiedNotice = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    HelpGuideView()
                        .onAppear { Haptics.select() }
                } label: {
                    row(tr("Как пользоваться"), subtitle: tr("Инструкция и описание всех функций"), icon: "book")
                }

                Button {
                    Haptics.tap()
                    writeToDeveloper()
                } label: {
                    row(tr("Написать разработчику"), subtitle: tr("Письмо на %@", "\(AppInfo.developerEmail)"), icon: "envelope")
                }
                .foregroundStyle(.primary)

                ShareLink(
                    item: AppInfo.downloadPage,
                    subject: Text("PlayMyDisk"),
                    message: Text(tr("PlayMyDisk — оффлайн-плеер для iPhone. Для установки нужен компьютер с программой Sideloadly, инструкция на странице по ссылке."))
                ) {
                    row(tr("Предложить друзьям"), subtitle: tr("Ссылка на страницу с приложением и инструкцией"), icon: "person.2")
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle(tr("Помощь"))
        .sheet(isPresented: $showMail) {
            MailComposeView(
                recipient: AppInfo.developerEmail,
                subject: tr("PlayMyDisk — обратная связь"),
                body: mailBody
            )
            .ignoresSafeArea()
        }
        .alert(tr("Почта не настроена"), isPresented: $copiedNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(tr("Адрес %@ скопирован. Вставьте его в любое почтовое приложение.", "\(AppInfo.developerEmail)"))
        }
    }

    private var mailBody: String {
        let device = UIDevice.current
        return "\n\n\n—\nPlayMyDisk \(AppInfo.versionText)\n\(device.systemName) \(device.systemVersion)\n\(device.model)"
    }

    /// Встроенное окно письма; если почта не настроена — mailto:, иначе копируем адрес.
    private func writeToDeveloper() {
        if MFMailComposeViewController.canSendMail() {
            showMail = true
            return
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = AppInfo.developerEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: tr("PlayMyDisk — обратная связь")),
            URLQueryItem(name: "body", value: mailBody)
        ]
        guard let url = components.url else {
            copyAddress()
            return
        }
        openURL(url) { accepted in
            if !accepted {
                copyAddress()
            }
        }
    }

    private func copyAddress() {
        UIPasteboard.general.string = AppInfo.developerEmail
        copiedNotice = true
    }

    private func row(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Окно письма (MFMailComposeViewController) для SwiftUI.
struct MailComposeView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    var attachment: (data: Data, mimeType: String, fileName: String)? = nil

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> MailCoordinator {
        MailCoordinator(onFinish: { dismiss() })
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(recipient.isEmpty ? [] : [recipient])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        if let attachment {
            controller.addAttachmentData(attachment.data, mimeType: attachment.mimeType, fileName: attachment.fileName)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
}

@MainActor
final class MailCoordinator: NSObject, @preconcurrency MFMailComposeViewControllerDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func mailComposeController(
        _ controller: MFMailComposeViewController,
        didFinishWith result: MFMailComposeResult,
        error: Error?
    ) {
        if let error {
            AppLogger.shared.log("mail", "Ошибка отправки письма: \(error.localizedDescription)")
        }
        onFinish()
    }
}

/// Встроенная инструкция с описанием функций.
struct HelpGuideView: View {
    private let sections: [(title: String, text: String)] = [
        (tr("Как добавить музыку"),
         tr("• Кнопка «+» на панели плеера — выбор файлов из «Файлов», iCloud Drive, Google Drive, Яндекс.Диска и других облаков. Можно выбрать сразу много файлов.\n• Приложение «Файлы» → «На iPhone» → папка PlayMyDisk — копируйте музыку прямо туда.\n• В любом приложении: «Поделиться» → «Открыть в PlayMyDisk».\n• Потяните список вниз, чтобы обновить библиотеку.")),
        (tr("Панель плеера"),
         tr("• Play/Пауза — большая кнопка в центре.\n• ⟲ и ⟳ — перемотка на 15 секунд (шаг меняется в настройках).\n• ⏮ — если прошло больше 3 секунд, трек начнётся сначала; иначе — предыдущий трек.\n• Рандом — «честное» перемешивание: трек не повторится, пока не сыграют все остальные.\n• Повтор: выкл → весь список → один трек.\n• Скорость — нажатие переключает 1x → 1.5x → 2x → 3x → 4x, удержание — полный список.\n• Нажатие на дисплей меняет вид визуализатора.")),
        (tr("Списки и поиск"),
         tr("• Вкладки: ★ — самые прослушиваемые, ♥ «Супер!» — отмеченные сердечком, «Все треки», «Папки» и ваши плейлисты.\n• Поиск: введите номер строки или часть названия — список прокрутится к найденному и подсветит его. Кнопки ▲ ▼ — к другим совпадениям, «Готово» или «Ввод» — спрятать клавиатуру.\n• «Перемешать список» меняет порядок строк, «А–Я» возвращает алфавитный (трек 2 перед треком 10).\n• Значок «Выбрать» — выбор нескольких треков: добавить в плейлист, убрать, удалить.")),
        (tr("Действия с треком"),
         tr("• ♥ в строке — отметить «Супер!».\n• ⚙ в строке — меню: «Супер!», поделиться файлом, найти в интернете, добавить в плейлист, убрать из плейлиста, удалить с устройства.\n• Свайп влево по строке — убрать или удалить.\n• Удаление с устройства всегда спрашивает подтверждение.")),
        (tr("Плейлисты"),
         tr("• «+» в ряду вкладок — новый плейлист.\n• Долгое нажатие на вкладку — переименовать или удалить; вкладки можно перетаскивать.\n• Порядок плейлистов и сортировка по алфавиту — в «Настройки → Библиотека и плейлисты».")),
        (tr("Аудиокниги"),
         tr("• Аудиокнигой считаются файлы .m4b и файлы длиннее 20 минут (порог меняется в настройках), а также всё в папке, помеченной «Аудиокниги» (долгое нажатие на папку).\n• Место прослушивания запоминается; при возобновлении — небольшой откат назад.\n• Закладки: нажмите значок закладки — она встанет на текущей секунде; удерживайте — откроется список.\n• Если в книге есть главы — появится кнопка со списком глав.")),
        (tr("Звук"),
         tr("• Эквалайзер: 10 полос, готовые и свои пресеты.\n• Выравнивание громкости — треки разной громкости звучат ровно.\n• Таймер сна: 15–60 минут, до конца трека или своё время, с плавным затуханием.")),
        (tr("Экран блокировки"),
         tr("На экране блокировки и в Пункте управления — название, обложка, перемотка и кнопки. По бокам от Паузы — перемотка или переход между треками (выбор в настройках).")),
        (tr("Защищённые файлы"),
         tr("Файлы .m4p (iTunes Store) и .aa/.aax (Audible) защищены DRM. Их можно добавить, но воспроизвести нельзя: слушайте их в приложениях «Музыка» или Audible.")),
        (tr("Обновление приложения"),
         tr("С бесплатным Apple ID приложение работает 7 дней. Переустановите его через Sideloadly поверх — не удаляя с телефона, иначе пропадут музыка и настройки."))
    ]

    var body: some View {
        List {
            ForEach(sections, id: \.title) { section in
                DisclosureGroup(section.title) {
                    Text(section.text)
                        .font(.subheadline)
                        .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(tr("Как пользоваться"))
    }
}

// MARK: - О приложении

struct AboutSettingsView: View {
    let container: AppContainer

    @State private var cacheSize: Int64 = 0
    @State private var showLog = false
    @State private var showFormats = false

    var body: some View {
        List {
            Section {
                LabeledContent(tr("Версия"), value: AppInfo.versionText)
                Button(tr("Поддерживаемые форматы")) {
                    Haptics.select()
                    showFormats = true
                }
                Button {
                    Haptics.tap()
                    ArtworkCache.clear()
                    cacheSize = 0
                    Task {
                        await container.library.restoreMissingArtwork()
                        cacheSize = await Task.detached { ArtworkCache.totalSize() }.value
                    }
                } label: {
                    LabeledContent(tr("Очистить кэш обложек"), value: ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))
                }
                Button(tr("Журнал отладки")) {
                    Haptics.select()
                    showLog = true
                }
            }
        }
        .navigationTitle(tr("О приложении"))
        .task {
            cacheSize = await Task.detached { ArtworkCache.totalSize() }.value
        }
        .sheet(isPresented: $showLog) {
            DebugLogView()
        }
        .alert(tr("Поддерживаемые форматы"), isPresented: $showFormats) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(tr("MP3, AAC, M4A (в т.ч. ALAC), M4B, M4R, FLAC, WAV, AIFF, AIF, AIFC, CAF (в т.ч. ALAC).\n\nЗащищённые DRM файлы .m4p (iTunes Store) и .aa/.aax (Audible) добавить можно, но воспроизвести нельзя — это ограничение их защиты. Их можно слушать в приложениях «Музыка» и Audible."))
        }
    }
}

// MARK: - Память

/// Сколько занимает плеер и сколько занято и свободно на iPhone.
struct StorageInfoView: View {
    @State private var appBytes: Int64?
    @State private var totalBytes: Int64?
    @State private var freeBytes: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("PlayMyDisk (музыка и данные)"))
                Spacer()
                Text(appBytes.map(gb) ?? "…")
                    .foregroundStyle(.secondary)
            }
            if let total = totalBytes, let free = freeBytes, total > 0 {
                let used = total - free
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * CGFloat(Double(appBytes ?? 0) / Double(total)))
                        Rectangle()
                            .fill(Color.secondary.opacity(0.6))
                            .frame(width: geo.size.width * CGFloat(Double(max(0, used - (appBytes ?? 0))) / Double(total)))
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 10)
                .background(Color.secondary.opacity(0.2))
                .clipShape(Capsule())
                .accessibilityHidden(true)
                HStack {
                    Text(tr("iPhone: занято %@ из %@", "\(gb(used))", "\(gb(total))"))
                    Spacer()
                    Text(tr("свободно %@", "\(gb(free))"))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .task {
            let result = await Task.detached(priority: .utility) { StorageInfo.measure() }.value
            appBytes = result.app
            totalBytes = result.total
            freeBytes = result.free
        }
    }

    /// Гигабайты с одним знаком после запятой (как в настройках iPhone, 1 ГБ = 10⁹ байт).
    private func gb(_ bytes: Int64) -> String {
        tr("%@ ГБ", String(format: "%.1f", Double(bytes) / 1_000_000_000))
    }
}

enum StorageInfo {
    struct Result: Sendable {
        let app: Int64
        let total: Int64?
        let free: Int64?
    }

    static func measure() -> Result {
        let fm = FileManager.default
        var app: Int64 = 0
        let folders: [URL] = [
            fm.urls(for: .documentDirectory, in: .userDomainMask)[0],
            fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
            fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        ]
        for folder in folders {
            app += directorySize(folder)
        }
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        let total = values?.volumeTotalCapacity.map { Int64($0) }
        let free = values?.volumeAvailableCapacityForImportantUsage
        return Result(app: app, total: total, free: free)
    }

    private static func directorySize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        while let item = enumerator.nextObject() as? URL {
            guard let values = try? item.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }
}
