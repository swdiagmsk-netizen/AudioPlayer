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
                            Text("Обложка").font(.headline)
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Text("Выбрать фото")
                            }
                            Button("Удалить", role: .destructive) {
                                Haptics.select()
                                artworkChange = .remove
                                previewImage = nil
                            }
                            .disabled(previewImage == nil)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Section("Файл") {
                    HStack {
                        TextField("Имя файла", text: $baseName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text("." + fileExtension)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    field("Название", $tags.title)
                    field("Исполнитель", $tags.artist)
                    field("Альбом", $tags.album)
                    field("Исполнитель альбома", $tags.albumArtist)
                    field("Жанр", $tags.genre)
                    field("Год", $tags.year, keyboard: .numberPad)
                    field("Номер трека", $tags.trackNumber, keyboard: .numberPad)
                    field("Композитор", $tags.composer)
                    field("Комментарий", $tags.comment)
                } header: {
                    Text("Теги")
                } footer: {
                    if !writesToFile {
                        Text("Для формата \(fileExtension.uppercased()) теги сохраняются в приложении, в файл не записываются.")
                    }
                }

                Section("Сведения") {
                    LabeledContent("Формат", value: track.formatName)
                    LabeledContent("Битрейт / частота", value: technicalLine)
                    LabeledContent("Длительность", value: TimeText.format(track.duration))
                    LabeledContent("Размер", value: ByteCountFormatter.string(fromByteCount: track.fileSize, countStyle: .file))
                    LabeledContent("Папка", value: track.folderPath.isEmpty ? "Музыка" : "Музыка › " + track.folderPath.replacingOccurrences(of: "/", with: " › "))
                    LabeledContent("Прослушиваний", value: "\(track.playCount)")
                }
            }
            .disabled(isSaving)
            .overlay {
                if isSaving {
                    ProgressView("Сохранение…")
                        .padding(20)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
                }
            }
            .navigationTitle("Теги файла")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
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
            .alert("Не удалось сохранить", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
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
            .accessibilityLabel("Обложка отсутствует")
        }
    }

    private func field(_ title: String, _ value: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        LabeledContent(title) {
            TextField(title, text: value, prompt: Text("не указан"))
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboard)
        }
    }

    private var technicalLine: String {
        var parts: [String] = []
        if track.bitrateKbps > 0 { parts.append("\(track.bitrateKbps) кбит/с") }
        if track.sampleRate > 0 { parts.append(String(format: "%.1f кГц", track.sampleRate / 1000)) }
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
            errorText = "Не удалось загрузить фото"
            return
        }
        let jpeg = await Task.detached(priority: .userInitiated) {
            ArtworkCache.jpegData(from: data, maxPixel: 1000)
        }.value
        guard let jpeg, let image = UIImage(data: jpeg) else {
            errorText = "Не удалось прочитать фото"
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
                errorText = "Не удалось переименовать файл: имя пустое, содержит «/» или такой файл уже есть."
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
            onDone("Теги сохранены в файл")
        case .appOnly:
            onDone("Сохранено в приложении, в файл не записывается")
        case .failed(let reason):
            onDone("В файл записать не удалось (\(reason)). Сохранено в приложении.")
        }
        dismiss()
    }
}
