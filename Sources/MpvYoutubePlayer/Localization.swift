import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case es
    case en

    var id: String { rawValue }

    /// Cada idioma se muestra con su propio nombre (no traducido), como es
    /// habitual en selectores de idioma.
    var displayName: String {
        switch self {
        case .es: return "Español"
        case .en: return "English"
        }
    }
}

enum LKey {
    case appTitle, help, close, settings, quit, language
    case playlist, playTooltip, pasteFromClipboard, urlPlaceholder
    case pauseTooltip, previousTooltip, nextTooltip, stopTooltip
    case audioOnly, playButton
    case mpvNotInstalled, ytdlpNotInstalled, homebrewNotInstalledEither
    case openTerminalToInstallHomebrew, installWithHomebrew
    case aboutCredit, helpSectionTitle, helpBody
    case playlistTitle, importEllipsis, exportEllipsis, noVideosYet
    case doubleClickToPlay, qualityTooltip, copyUrlTooltip, removeFromPlaylistTooltip
    case exportFailedPrefix, importFailedPrefix
    case mpvNotInstalledError, installingPrefix, installationCompleted
    case homebrewNotInstalledErrorDescription
    case invalidURLError, mpvLaunchFailedPrefix
    case cacheSectionTitle, cacheDurationLabel
    case renderSectionTitle, renderQualityHint
    case audioOnlyWindowToggleLabel, audioOnlyWindowHint
    case closeWindowsOnPlayToggleLabel, closeWindowsOnPlayHint
    case fullscreenTooltip, volumeTooltip, vuMeterToggleTooltip, alwaysOnTopTooltip
    case playLinkLabel, playLinkTooltip
}

/// Sistema de idioma propio (en vez de `Localizable.strings`/`Bundle`) para
/// poder cambiarlo en caliente desde Ajustes sin tener que reiniciar la app:
/// SwiftUI solo vuelve a pintar las vistas que observan `LocalizationManager`
/// cuando `language` cambia. Sin `@MainActor`: los mensajes de error
/// (`LocalizedError.errorDescription`) de otros archivos lo leen desde
/// contextos no aislados al actor principal.
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    private static let defaultsKey = "appLanguage"

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey) }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: Self.defaultsKey),
           let lang = AppLanguage(rawValue: saved) {
            language = lang
        } else {
            let systemLanguageCode = Locale.current.language.languageCode?.identifier
            language = systemLanguageCode == "es" ? .es : .en
        }
    }

    func t(_ key: LKey) -> String {
        let pair = Self.translations[key] ?? (es: "", en: "")
        return language == .es ? pair.es : pair.en
    }

    private static let translations: [LKey: (es: String, en: String)] = [
        .appTitle: ("mpv YouTube Player", "mpv YouTube Player"),
        .help: ("Ayuda", "Help"),
        .close: ("Cerrar", "Close"),
        .settings: ("Ajustes", "Settings"),
        .quit: ("Salir", "Quit"),
        .language: ("Idioma", "Language"),

        .playlist: ("Playlist", "Playlist"),
        .playTooltip: ("Reproducir", "Play"),
        .pauseTooltip: ("Pausar", "Pause"),
        .previousTooltip: ("Anterior", "Previous"),
        .nextTooltip: ("Siguiente", "Next"),
        .stopTooltip: ("Detener", "Stop"),
        .pasteFromClipboard: ("Pegar del portapapeles", "Paste from clipboard"),
        .urlPlaceholder: ("https://www.youtube.com/watch?v=…", "https://www.youtube.com/watch?v=…"),
        .audioOnly: ("Solo audio", "Audio only"),
        .playButton: ("Reproducir", "Play"),

        .mpvNotInstalled: ("mpv no está instalado", "mpv is not installed"),
        .ytdlpNotInstalled: ("yt-dlp no está instalado", "yt-dlp is not installed"),
        .homebrewNotInstalledEither: ("Homebrew tampoco está instalado.", "Homebrew isn't installed either."),
        .openTerminalToInstallHomebrew: ("Abrir Terminal para instalar Homebrew", "Open Terminal to install Homebrew"),
        .installWithHomebrew: ("Instalar con Homebrew", "Install with Homebrew"),

        .aboutCredit: ("by ©jugomo 2006", "by ©jugomo 2006"),
        .helpSectionTitle: ("Ayuda", "Help"),
        .helpBody: (
            """
            1. Pega la URL de un vídeo de YouTube o escríbela en el campo de texto.
            2. Elige la calidad de vídeo (o "Solo audio").
            3. Pulsa Reproducir para abrir mpv.
            4. Usa el botón Playlist para ver, reproducir de nuevo o exportar tus vídeos anteriores.
            5. Clic derecho en el icono de la barra de menú para abrir Ajustes o salir de la app.
            """,
            """
            1. Paste a YouTube video URL or type it into the text field.
            2. Choose the video quality (or "Audio only").
            3. Press Play to open mpv.
            4. Use the Playlist button to view, replay, or export your previous videos.
            5. Right-click the menu bar icon to open Settings or quit the app.
            """
        ),

        .playlistTitle: ("Playlist", "Playlist"),
        .importEllipsis: ("Importar…", "Import…"),
        .exportEllipsis: ("Exportar…", "Export…"),
        .noVideosYet: ("Aún no se ha reproducido ningún vídeo.", "No videos played yet."),
        .doubleClickToPlay: ("Doble clic para reproducir", "Double-click to play"),
        .qualityTooltip: ("Calidad al reproducir", "Quality when played"),
        .copyUrlTooltip: ("Copiar URL al portapapeles", "Copy URL to clipboard"),
        .removeFromPlaylistTooltip: ("Eliminar de la playlist", "Remove from playlist"),
        .exportFailedPrefix: ("No se pudo exportar la playlist: ", "Could not export the playlist: "),
        .importFailedPrefix: ("No se pudo importar la playlist: ", "Could not import the playlist: "),

        .mpvNotInstalledError: ("mpv no está instalado.", "mpv is not installed."),
        .installingPrefix: ("Instalando ", "Installing "),
        .installationCompleted: ("Instalación completada.", "Installation completed."),
        .homebrewNotInstalledErrorDescription: ("Homebrew no está instalado.", "Homebrew is not installed."),
        .invalidURLError: ("La URL no es válida.", "The URL is not valid."),
        .mpvLaunchFailedPrefix: ("No se pudo iniciar mpv: ", "Could not start mpv: "),

        .cacheSectionTitle: ("Caché de vídeo", "Video cache"),
        .cacheDurationLabel: ("Duración de caché", "Cache duration"),

        .renderSectionTitle: ("Renderizado de vídeo", "Video rendering"),
        .renderQualityHint: (
            "Rendimiento reduce el uso de GPU/batería en pantalla completa; Calidad usa el escalador de mayor nitidez de mpv.",
            "Performance lowers GPU/battery use in fullscreen; Quality uses mpv's sharper scaler."
        ),

        .audioOnlyWindowToggleLabel: (
            "No usar ventana separada al reproducir solo audio",
            "Don't use a separate window when playing audio only"
        ),
        .audioOnlyWindowHint: (
            "Si está activado, el audio se controla desde los controles de esta app (reproducir, pausa, siguiente, buscar) en vez de abrir la ventana de mpv.",
            "When enabled, audio is controlled from this app's own controls (play, pause, next, seek) instead of opening mpv's window."
        ),

        .closeWindowsOnPlayToggleLabel: (
            "Cerrar la ventana principal y la playlist al reproducir",
            "Close the main window and playlist when playing"
        ),
        .closeWindowsOnPlayHint: (
            "Si se desactiva, ambas ventanas permanecen abiertas tras pulsar Reproducir en vez de cerrarse automáticamente.",
            "When disabled, both windows stay open after pressing Play instead of closing automatically."
        ),

        .fullscreenTooltip: ("Pantalla completa", "Fullscreen"),
        .alwaysOnTopTooltip: ("Mantener siempre encima", "Keep always on top"),
        .volumeTooltip: ("Volumen (solo esta reproducción)", "Volume (this playback only)"),
        .vuMeterToggleTooltip: ("Clic para cambiar de estilo (digital/analógico)", "Click to switch style (digital/analog)"),

        .playLinkLabel: ("Reproducir enlace", "Play link"),
        .playLinkTooltip: ("Clic para mostrar/ocultar los controles de reproducción", "Click to show/hide the playback controls"),
    ]
}
