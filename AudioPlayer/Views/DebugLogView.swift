import SwiftUI

/// Журнал отладки: просмотр, отправка и очистка.
struct DebugLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text.isEmpty ? "Журнал пуст" : text)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
            .navigationTitle("Журнал отладки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ShareLink(item: AppLogger.shared.fileURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Отправить журнал")
                    Button(role: .destructive) {
                        AppLogger.shared.clear()
                        text = ""
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Очистить журнал")
                }
            }
            .onAppear {
                text = AppLogger.shared.readAll()
            }
        }
    }
}
