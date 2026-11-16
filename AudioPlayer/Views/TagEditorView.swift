import SwiftUI
import PhotosUI

/// Редактор тегов и имени файла.
/// MP3, M4A/M4B/M4R и FLAC — теги записываются в сам файл;
/// WAV/AIFF/CAF/AAC — хранятся только в приложении.
struct TagEditorView: View {
    let container: AppContainer
    let track: TrackRecord
    let onDone: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var tags = TagValues()
    @State private var baseName = ""
    @State private var artworkChange: ArtworkChange = .keep
    @State private var previewImage: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var isSaving = false
    @State private var errorText: String?

    private var fileExtension: String { (track.fileName as NSString).pathExtension }
    private var writesToFile: Bool { TagWriter.canWrite(extension: fileExtension) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        artworkView
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(tr("Обложка")).font(.headline)
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Text(tr("Выбрать фото"))
                            }
                            Button(tr("Удалить"), role: .destructive) {
                                Haptics.select()
                                artworkChange = .remove
                                previewImage = nil
                            }
                            .disabled(previewImage == nil)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Section(tr("Файл")) {
                    HStack {
                        TextField(tr("Имя файла"), text: $baseName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text("." + fileExtension)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    field(tr("Название"), $tags.title)
                    field(tr("Исполнитель"), $tags.artist)
                    field(tr("Альбом"), $tags.album)
                    field(tr("Исполнитель альбома"), $tags.albumArtist)
                    field(tr("Жанр"), $tags.genre)
                    field(tr("Год"), $tags.year, keyboard: .numberPad)
                    field(tr("Номер трека"), $tags.trackNumber, keyboard: .numberPad)
                    field(tr("Композитор"), $tags.composer)
                    field(tr("Комментарий"), $tags.comment)
                } header: {
                    Text(tr("Теги"))
                } footer: {
                    if !writesToFile {
                        Text(tr("Для формата %@ теги сохраняются в приложении, в файл не записываются.", "\(fileExtension.uppercased())"))
                    }
                }

                Section(tr("Сведения")) {
                    LabeledContent(tr("Формат"), value: track.formatName)
                    LabeledContent(tr("Битрейт / частота"), value: technicalLine)
                    LabeledContent(tr("Длительность"), value: TimeText.format(track.duration))
                    LabeledContent(tr("Размер"), value: ByteCountFormatter.string(fromByteCount: track.fileSize, countStyle: .file))
                    LabeledContent(tr("Папка"), value: track.folderPath.isEmpty ? tr("Музыка") : tr("Музыка › ") + track.folderPath.replacingOccurrences(of: "/", with: " › "))
                    LabeledContent(tr("Прослушиваний"), value: "\(track.playCount)")
                }
            }
            .disabled(isSaving)
            .overlay {
                if isSaving {
                    ProgressView(tr("Сохранение…"))
                        .padding(20)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
                }
            }
            .navigationTitle(tr("Теги файла"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Отмена")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Сохранить")) {
                        Haptics.tap()
                        Task { await save() }
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear(perform: load)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await loadPhoto(item) }
            }
            .alert(tr("Не удалось сохранить"), isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    // MARK: - Части

    @ViewBuilder
    private var artworkView: some View {
        if let previewImage {
            Image(uiImage: previewImage).resizable().scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(palette.button)
                Image(systemName: "music.note")
                    .font(.system(size: 34))
                    .foregroundStyle(palette.secondaryText)
            }
            .accessibilityLabel(tr("Обложка отсутствует"))
        }
    }

    private func field(_ title: String, _ value: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        LabeledContent(title) {
            TextField(title, text: value, prompt: Text(tr("не указан")))
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboard)
        }
    }

    private var technicalLine: String {
        var parts: [String] = []
        if track.bitrateKbps > 0 { parts.append(tr("%@ кбит/с", "\(track.bitrateKbps)")) }
        if track.sampleRate > 0 { parts.append(tr("%@ кГц", String(format: "%.1f", track.sampleRate / 1000))) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    // MARK: - Загрузка и сохранение

    private func load() {
        tags = TagValues(
            title: track.title,
            artist: track.artist,
            album: track.album,
            albumArtist: track.albumArtist,
            genre: track.genre,
            year: track.year,
            trackNumber: track.trackNumber,
            composer: track.composer,
            comment: track.comment
        )
        baseName = (track.fileName as NSString).deletingPathExtension
        previewImage = artworkImage(for: track)
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            errorText = tr("Не удалось загрузить фото")
            return
        }
        let jpeg = await Task.detached(priority: .userInitiated) {
            ArtworkCache.jpegData(from: data, maxPixel: 1000)
        }.value
        guard let jpeg, let image = UIImage(data: jpeg) else {
            errorText = tr("Не удалось прочитать фото")
            return
        }
        artworkChange = .replace(jpeg)
        previewImage = image
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let library = container.library

        // 1. Имя файла
        let newBase = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if newBase != (track.fileName as NSString).deletingPathExtension {
            guard !newBase.isEmpty, library.renameFile(of: track, toBaseName: newBase) else {
                errorText = tr("Не удалось переименовать файл: имя пустое, содержит «/» или такой файл уже есть.")
                return
            }
        }

        // 2. Теги в файл (в фоне — файл может быть большим)
        let url = track.fileURL
        let values = tags
        let change = artworkChange
        let result = await TagWriter.write(values, artwork: change, to: url)

        // 3. База и обложка
        library.applyTags(values, to: track)
        switch change {
        case .keep: break
        case .replace(let jpeg): library.setArtwork(jpeg, for: track)
        case .remove: library.setArtwork(nil, for: track)
        }

        switch result {
        case .writtenToFile:
            onDone(tr("Теги сохранены в файл"))
        case .appOnly:
            onDone(tr("Сохранено в приложении, в файл не записывается"))
        case .failed(let reason):
            onDone(tr("В файл записать не удалось (%@). Сохранено в приложении.", "\(reason)"))
        }
        dismiss()
    }
}
