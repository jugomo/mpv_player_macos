import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Pestaña de Ajustes que muestra el contenido del log de mpv
/// (`~/Library/Logs/MpvPlayerUI/mpv.log`, ver `MPVLauncher.logFileURL()`) y
/// permite recargarlo, exportarlo a un .txt o vaciarlo.
struct LogViewerView: View {
    /// El log puede crecer a varios MB/cientos de miles de líneas (nunca se
    /// rota, solo se vacía con el botón Borrar). Cargar y pintar eso entero
    /// con `Text`/`ScrollView` de SwiftUI (que no virtualiza el contenido)
    /// bloquea el hilo principal y cuelga la app, así que aquí solo se lee
    /// y se muestra la cola del archivo.
    private static let maxDisplayBytes = 1_000_000

    @ObservedObject private var loc = LocalizationManager.shared
    @State private var logText: String = ""
    @State private var totalBytes: Int = 0
    @State private var isTruncated = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(loc.t(.reloadButton), action: reloadLog)
                    .disabled(isLoading)
                Button(loc.t(.exportButton), action: exportLog)
                    .disabled(isLoading || totalBytes == 0)
                Button(loc.t(.clearButton)) { showClearConfirmation = true }
                    .disabled(isLoading || totalBytes == 0)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if isTruncated {
                Text(truncationNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Group {
                if logText.isEmpty && !isLoading {
                    VStack {
                        Spacer()
                        Text(loc.t(.emptyLogMessage))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                        Spacer()
                    }
                } else {
                    LogTextView(text: logText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(20)
        .onAppear(perform: reloadLog)
        .alert(loc.t(.clearLogConfirmTitle), isPresented: $showClearConfirmation) {
            Button(loc.t(.clearButton), role: .destructive, action: clearLog)
            Button(loc.t(.cancel), role: .cancel) {}
        } message: {
            Text(loc.t(.clearLogConfirmMessage))
        }
    }

    private var truncationNote: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let shown = formatter.string(fromByteCount: Int64(Self.maxDisplayBytes))
        let total = formatter.string(fromByteCount: Int64(totalBytes))
        return String(format: loc.t(.logTruncatedNoteFormat), shown, total)
    }

    private func reloadLog() {
        errorMessage = nil
        isLoading = true
        let url = MPVLauncher.logFileURL()
        let maxBytes = Self.maxDisplayBytes
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.readTail(of: url, maxBytes: maxBytes)
            DispatchQueue.main.async {
                logText = result.text
                totalBytes = result.totalBytes
                isTruncated = result.truncated
                isLoading = false
            }
        }
    }

    /// Lee como mucho los últimos `maxBytes` del archivo, buscando desde el
    /// final en vez de cargarlo entero para poder recortarlo después.
    private static func readTail(of url: URL, maxBytes: Int) -> (text: String, truncated: Bool, totalBytes: Int) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return ("", false, 0) }
        defer { try? handle.close() }
        guard let totalSize = try? handle.seekToEnd() else { return ("", false, 0) }
        let total = Int(totalSize)
        let readSize = min(total, maxBytes)
        guard readSize > 0 else { return ("", false, total) }
        let offset = UInt64(total - readSize)
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd() else {
            return ("", false, total)
        }
        var text = String(decoding: data, as: UTF8.self)
        let truncated = readSize < total
        if truncated, let newlineRange = text.range(of: "\n") {
            // El primer "renglón" leído puede estar cortado a mitad de
            // línea: se descarta para que la vista empiece en una línea
            // completa.
            text = String(text[newlineRange.upperBound...])
        }
        return (text, truncated, total)
    }

    private func exportLog() {
        errorMessage = nil
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "mpv.log.txt"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let source = MPVLauncher.logFileURL()
        // Exporta el archivo completo (no solo la cola mostrada en pantalla),
        // leyendo y escribiendo en background para no bloquear la UI con un
        // log grande.
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: source)
                try data.write(to: destination, options: .atomic)
            } catch {
                DispatchQueue.main.async {
                    errorMessage = loc.t(.exportLogFailedPrefix) + error.localizedDescription
                }
            }
        }
    }

    private func clearLog() {
        errorMessage = nil
        do {
            // Trunca en el sitio en vez de reemplazar el archivo: si mpv
            // está en marcha, su stdout/stderr comparten con la app la
            // posición de escritura en este mismo archivo (ver
            // `MPVLauncher.clearLogFile`), y sustituirlo lo dejaría escribiendo
            // para siempre en un inodo huérfano invisible.
            try MPVLauncher.clearLogFile()
            logText = ""
            totalBytes = 0
            isTruncated = false
        } catch {
            errorMessage = loc.t(.clearLogFailedPrefix) + error.localizedDescription
        }
    }
}

/// Envoltorio de `NSTextView` de solo lectura: a diferencia de `Text` dentro
/// de un `ScrollView`, `NSTextView` no necesita calcular el layout de todo
/// el contenido de golpe, por lo que sigue yendo fluido incluso con
/// cientos de miles de caracteres.
private struct LogTextView: NSViewRepresentable {
    var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.drawsBackground = false

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard textView.string != text else { return }
        textView.string = text
        textView.scrollToEndOfDocument(nil)
    }
}
