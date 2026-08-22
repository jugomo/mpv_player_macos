import Foundation

/// Una actualización disponible para una herramienta vendorizada (ver
/// `build.sh`): versión que hay empaquetada en este bundle vs. la última
/// publicada aguas arriba. `Codable` para poder cachearla entre lanzamientos
/// (ver `UpdateChecker`).
struct AvailableUpdate: Equatable, Identifiable, Codable {
    let tool: String
    let current: String
    let latest: String
    let releaseURL: String

    var id: String { tool }
}

/// Comprueba en segundo plano, una vez al arrancar la app, si hay una
/// versión más reciente de mpv/yt-dlp que la vendorizada en el bundle (ver
/// build.sh). No instala nada ni se autoactualiza: solo informa (ver
/// `AboutView`), porque tanto mpv como yt-dlp aquí no se instalan sueltos en
/// el sistema sino que van empaquetados dentro de la app — "actualizar"
/// significa volver a correr `./build.sh` (que sí trae siempre la última
/// yt-dlp y la mpv que haya instalada en esa máquina) y reinstalar el
/// resultado.
///
/// yt-dlp es el que de verdad importa aquí: YouTube le cambia las reglas casi
/// semana a semana (ver historial de `MPVLauncher.applySessionSettings`), así
/// que una copia vieja es la causa más probable de que la reproducción
/// empiece a fallar con 403. mpv cambia con mucha menos frecuencia, pero se
/// comprueba igual ya que se pidió explícitamente.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published private(set) var availableUpdates: [AvailableUpdate] = []

    private var hasChecked = false

    /// Aunque las dos peticiones HTTP van en segundo plano y no bloquean
    /// `applicationDidFinishLaunching`, medido con Instruments (plantilla
    /// "App Launch" + Time Profiler) se veía un hueco de ~4.5s justo tras el
    /// arranque donde NINGÚN hilo del proceso llegaba siquiera a
    /// programarse — macOS suprime agresivamente el trabajo en QoS
    /// `.background` durante los primeros segundos tras lanzar un proceso —
    /// seguido de una ráfaga (resolución DNS, caché sqlite de URLSession,
    /// parseo de JSON) al completarse por fin las peticiones. Repetir esto
    /// en cada lanzamiento —antes se hacía siempre, `hasChecked` era una
    /// bandera solo en memoria— es un coste real y innecesario, y además
    /// bombardea la API de GitHub/Homebrew sin motivo. Cachear el resultado
    /// y el momento del último chequeo en UserDefaults reduce las peticiones
    /// de red a como mucho una vez al día, sin perder la utilidad de la
    /// comprobación (yt-dlp puede cambiar cada semana, un día de margen es
    /// sobrado).
    private static let checkIntervalSeconds: TimeInterval = 24 * 60 * 60
    private static let lastCheckDateKey = "UpdateChecker.lastCheckDate"
    private static let cachedUpdatesKey = "UpdateChecker.cachedUpdates"

    private init() {
        availableUpdates = Self.loadCachedUpdates()
    }

    /// Llamar una vez al lanzar la app (ver AppDelegate). Si ya se comprobó
    /// hace menos de `checkIntervalSeconds`, no hace ninguna petición de red
    /// y se queda con lo que ya había en caché (cargado en `init`), así que
    /// la mayoría de lanzamientos no tocan la red para nada. No bloquea el
    /// arranque en ningún caso: cuando sí corre, va en segundo plano y tarda
    /// lo que tarden dos peticiones HTTP cortas (con timeout de 8s cada
    /// una). Si no hay red, o la API de GitHub/Homebrew no responde,
    /// simplemente no se marca ninguna actualización — no es un error
    /// visible para el usuario.
    func checkForUpdatesInBackground() {
        guard !hasChecked else { return }
        hasChecked = true
        let lastCheck = UserDefaults.standard.object(forKey: Self.lastCheckDateKey) as? Date
        if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.checkIntervalSeconds {
            return
        }
        // `.utility` en vez de `.background`: sigue sin competir por
        // prioridad con nada del arranque en sí (que ya ha terminado para
        // cuando esto se dispara), pero evita la supresión más agresiva que
        // aplica macOS a `.background` justo tras lanzar el proceso — ver
        // comentario de más arriba.
        Task.detached(priority: .utility) {
            async let ytdlp = Self.checkYtdlp()
            async let mpv = Self.checkMpv()
            let results = await [ytdlp, mpv].compactMap { $0 }
            await MainActor.run {
                UpdateChecker.shared.availableUpdates = results
                Self.persist(results)
            }
        }
    }

    private static func loadCachedUpdates() -> [AvailableUpdate] {
        guard let data = UserDefaults.standard.data(forKey: cachedUpdatesKey),
              let decoded = try? JSONDecoder().decode([AvailableUpdate].self, from: data) else { return [] }
        return decoded
    }

    /// Persiste tanto el resultado (incluso vacío: si ya no hay actualización
    /// pendiente, la próxima vez tampoco debe mostrarse una vieja) como la
    /// fecha del chequeo, esta última incluso si `results` viene vacío por un
    /// fallo de red — reintentar en cada lanzamiento mientras no hay red
    /// reproduciría exactamente el mismo hueco de varios segundos que esto
    /// corrige; perder como mucho un día de margen en detectarlo no lo justifica.
    private static func persist(_ results: [AvailableUpdate]) {
        UserDefaults.standard.set(Date(), forKey: lastCheckDateKey)
        if let data = try? JSONEncoder().encode(results) {
            UserDefaults.standard.set(data, forKey: cachedUpdatesKey)
        }
    }

    private static func checkYtdlp() async -> AvailableUpdate? {
        guard let path = DependencyChecker.bundledExecutable(named: "yt-dlp") ?? DependencyChecker.findExecutable(named: "yt-dlp"),
              let current = runVersion(at: path)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let latest = await latestGitHubReleaseTag(repo: "yt-dlp/yt-dlp"),
              latest != current else { return nil }
        return AvailableUpdate(
            tool: "yt-dlp",
            current: current,
            latest: latest,
            releaseURL: "https://github.com/yt-dlp/yt-dlp/releases/latest"
        )
    }

    private static func checkMpv() async -> AvailableUpdate? {
        guard let path = DependencyChecker.bundledExecutable(named: "mpv") ?? DependencyChecker.findExecutable(named: "mpv"),
              let rawOutput = runVersion(at: path),
              let current = parseMpvVersion(from: rawOutput),
              let latest = await latestHomebrewFormulaVersion(formula: "mpv"),
              latest != current else { return nil }
        return AvailableUpdate(
            tool: "mpv",
            current: current,
            latest: latest,
            releaseURL: "https://github.com/mpv-player/mpv/releases/latest"
        )
    }

    /// La primera línea de `mpv --version` es p. ej.
    /// "mpv v0.41.0 Copyright © 2000-2025 mpv/MPlayer/mplayer2 projects" —
    /// extrae solo "0.41.0", que es el mismo formato que devuelve la API de
    /// Homebrew (fuente real de mpv en build.sh). Busca por palabra, no solo
    /// la primera "v" del texto: la propia palabra "mpv" ya contiene una.
    private static func parseMpvVersion(from rawOutput: String) -> String? {
        guard let firstLine = rawOutput.split(separator: "\n").first else { return nil }
        for word in firstLine.split(separator: " ") where word.first == "v" && word.dropFirst().first?.isNumber == true {
            return String(word.dropFirst())
        }
        return nil
    }

    private static func runVersion(at executablePath: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func latestGitHubReleaseTag(repo: String) async -> String? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        guard let json = await fetchJSON(url) else { return nil }
        return json["tag_name"] as? String
    }

    private static func latestHomebrewFormulaVersion(formula: String) async -> String? {
        guard let url = URL(string: "https://formulae.brew.sh/api/formula/\(formula).json") else { return nil }
        guard let json = await fetchJSON(url) else { return nil }
        let versions = json["versions"] as? [String: Any]
        return versions?["stable"] as? String
    }

    private static func fetchJSON(_ url: URL) async -> [String: Any]? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }
}
