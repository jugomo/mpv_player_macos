import Combine
import Foundation

/// Igual patrón que PlaybackWindowSettingsManager/CacheSettingsManager/etc.:
/// ObservableObject persistido en UserDefaults, compartido entre SettingsView
/// y MPVLauncher. Controla qué subtítulos se le piden a yt-dlp para los
/// vídeos online (ver `MPVLauncher.applySessionSettings`); los archivos
/// locales no pasan por yt-dlp y no se ven afectados.
final class SubtitleSettingsManager: ObservableObject {
    static let shared = SubtitleSettingsManager()

    private static let enabledKey = "subtitlesEnabled"
    private static let languagesKey = "subtitleLanguages"
    static let defaultLanguages = "es, en"

    /// Por defecto `true`: poder elegir subtítulos desde la ventana de mpv.
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
    }

    /// Códigos de idioma separados por comas, tal cual los escribe el
    /// usuario (p.ej. "es, en"). Ver `ytdlpSubLangs` para cómo se traducen
    /// al formato de `--sub-langs` de yt-dlp.
    @Published var languages: String {
        didSet { UserDefaults.standard.set(languages, forKey: Self.languagesKey) }
    }

    /// Valor para `--sub-langs` de yt-dlp, o `nil` si no hay que pedir
    /// ninguno (desactivado o lista vacía). Cada código se convierte en la
    /// regex `código.*` para incluir también sus variantes regionales y
    /// automáticas (`es-419`, `en-orig`…), salvo que el usuario ya haya
    /// escrito una regex propia (contiene `*`).
    var ytdlpSubLangs: String? {
        guard enabled else { return nil }
        let codes = languages
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.contains("*") ? $0 : "\($0).*" }
        return codes.isEmpty ? nil : codes.joined(separator: ",")
    }

    private init() {
        if UserDefaults.standard.object(forKey: Self.enabledKey) == nil {
            enabled = true
        } else {
            enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        }
        languages = UserDefaults.standard.string(forKey: Self.languagesKey) ?? Self.defaultLanguages
    }
}
