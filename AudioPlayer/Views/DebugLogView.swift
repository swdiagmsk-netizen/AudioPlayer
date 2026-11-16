import SwiftUI

/// Журнал отладки: просмотр, отправка и очистка.
struct DebugLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text.isEmpty ? tr("Журнал пуст") : text)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
            .navigationTitle(tr("Журнал отладки"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(tr("Закрыть")) {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ShareLink(item: AppLogger.shared.fileURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(tr("Отправить журнал"))
                    Button(role: .destructive) {
                        AppLogger.shared.clear()
                        text = ""
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(tr("Очистить журнал"))
                }
            }
            .onAppear {
                text = AppLogger.shared.readAll()
            }
        }
    }
}
