import Foundation

struct PlaylistItem: Codable, Identifiable, Equatable {
    let id: UUID
    let urlString: String
    var quality: VideoQuality
    let addedAt: Date
    /// Título real del vídeo, reportado por mpv (vía IPC) una vez lo resuelve
    /// al cargar el vídeo. nil hasta que se resuelve.
    var title: String?
    /// Descripción obtenida bajo demanda vía yt-dlp (ver `YtDlpMetadataFetcher`)
    /// al pulsar sobre el título en reproducción. nil hasta que se pide.
    var description: String?

    init(id: UUID = UUID(), urlString: String, quality: VideoQuality, addedAt: Date = Date(), title: String? = nil, description: String? = nil) {
        self.id = id
        self.urlString = urlString
        self.quality = quality
        self.addedAt = addedAt
        self.title = title
        self.description = description
    }

    /// `true` para ítems añadidos con el selector de archivos (ver
    /// `PlayerViewModel.playLocalFiles`), que guarda la ruta absoluta llana
    /// en `urlString` en vez de una URL con esquema (ver comentario en
    /// `MPVLauncher.play`). Usado para elegir el icono de tipo en la
    /// playlist y para localizar la carátula local a su lado.
    var isLocalFile: Bool { urlString.hasPrefix("/") }

    /// Extensiones de audio "puro" reconocidas: un archivo local con una de
    /// estas extensiones siempre se reproduce en modo "Solo audio" (ver
    /// `isLocalAudioFile`), sin importar qué `quality` tenga guardada el
    /// ítem — la extensión del archivo es la fuente de verdad. La `quality`
    /// persistida puede haber quedado desactualizada (p. ej. un ítem
    /// añadido antes de que este mecanismo existiera, o del que el usuario
    /// cambió la calidad a mano cuando ese selector todavía se mostraba
    /// para archivos locales).
    private static let audioOnlyExtensions: Set<String> = [
        "mp3", "wav", "aiff", "aif", "flac", "aac", "m4a", "ogg", "opus", "wma", "alac", "wv"
    ]

    /// `true` si `urlString` es la ruta local de un archivo de audio "puro".
    /// Función libre (no solo propiedad de instancia) para poder aplicarse
    /// también a `urlText` antes de que exista un `PlaylistItem` — ver
    /// `PlayerViewModel.play`, que la usa para decidir la calidad real de
    /// reproducción independientemente de lo que pida quien llame.
    static func isLocalAudioFile(urlString: String) -> Bool {
        guard urlString.hasPrefix("/") else { return false }
        return audioOnlyExtensions.contains((urlString as NSString).pathExtension.lowercased())
    }

    /// `true` si este ítem es un archivo de audio "puro" local (ver
    /// `isLocalAudioFile(urlString:)`). Debe consultarse en vez de comparar
    /// `quality != .audioOnly` directamente en cualquier decisión de UI
    /// (ventana con/sin vídeo, vúmetro, etc.), precisamente para no
    /// depender de que `quality` esté al día.
    var isLocalAudioFile: Bool { Self.isLocalAudioFile(urlString: urlString) }

    /// Título de respaldo mientras `title` sigue sin resolver (`nil`): para
    /// un archivo local, su nombre sin la ruta ni la extensión (más legible
    /// que la ruta absoluta completa mientras
    /// `PlayerViewModel.resolveLocalTitleIfNeeded` termina de leer sus
    /// metadatos, o si el archivo no trae ninguno); para un enlace, la URL
    /// tal cual.
    var fallbackDisplayTitle: String {
        guard isLocalFile else { return urlString }
        return URL(fileURLWithPath: urlString).deletingPathExtension().lastPathComponent
    }
}
