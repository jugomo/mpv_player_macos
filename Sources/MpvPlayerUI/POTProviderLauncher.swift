import Foundation

/// Arranca y gestiona el servidor local de "PO Token" (bgutil-ytdlp-pot-provider,
/// ver vendorización en build.sh) que el plugin de yt-dlp vendorizado en
/// `Contents/Resources/bin/yt-dlp-plugins/` usa automáticamente (por HTTP en
/// `127.0.0.1:4416`, su puerto por defecto) para pedir el token que YouTube
/// exige cada vez más antes de servir el vídeo/audio.
///
/// Sin este token, algunas reproducciones fallan con "HTTP error 403
/// Forbidden" aunque la URL se acabe de extraer (ver el log de mpv). El
/// propio proveedor no garantiza evitarlo del todo, solo lo mitiga.
///
/// Todo esto es opcional y se degrada sin más si falta: si el runtime Deno o
/// el proveedor no están vendorizados (p. ej. en desarrollo con `swift run`,
/// donde `Bundle.main.resourceURL` no apunta a un bundle empaquetado),
/// simplemente no se arranca nada y yt-dlp sigue funcionando exactamente
/// igual que antes de este mecanismo, sin PO Token.
enum POTProviderLauncher {
    private static let lock = NSLock()
    private static var process: Process?

    /// Arranca el servidor en segundo plano si no está ya en marcha. Se
    /// llama una vez al lanzar la app (ver AppDelegate): local, en segundo
    /// plano y con arranque en ~1-2s, así ya está listo mucho antes de que
    /// el usuario pulse Reproducir por primera vez.
    static func start() {
        lock.lock()
        defer { lock.unlock() }
        guard process == nil else { return }

        guard let denoPath = DependencyChecker.bundledExecutable(named: "deno")
            ?? DependencyChecker.findExecutable(named: "deno") else { return }
        guard let resourceURL = Bundle.main.resourceURL else { return }

        let providerDir = resourceURL.appendingPathComponent("bgutil-provider", isDirectory: true)
        let nodeModulesDir = providerDir.appendingPathComponent("node_modules", isDirectory: true)
        let mainScript = providerDir.appendingPathComponent("src/main.ts")
        guard FileManager.default.fileExists(atPath: mainScript.path),
              FileManager.default.fileExists(atPath: nodeModulesDir.path) else { return }

        let newProcess = Process()
        newProcess.executableURL = URL(fileURLWithPath: denoPath)
        // El propio README del proveedor recomienda invocarlo así: con el
        // directorio de trabajo puesto en `node_modules` (para que Deno
        // resuelva ahí los paquetes npm, incluido el módulo nativo de
        // `canvas`) y `main.ts` referenciado en relativo desde ahí.
        newProcess.currentDirectoryURL = nodeModulesDir
        newProcess.arguments = [
            "run",
            "--allow-env",
            "--allow-net",
            "--allow-ffi=\(nodeModulesDir.path)",
            "--allow-read=\(nodeModulesDir.path)",
            "../src/main.ts",
            "--port", "\(port)",
        ]
        newProcess.standardOutput = FileHandle.nullDevice
        newProcess.standardError = FileHandle.nullDevice
        newProcess.terminationHandler = { _ in
            lock.lock()
            process = nil
            lock.unlock()
        }

        if (try? newProcess.run()) != nil {
            process = newProcess
        }
    }

    /// Puerto por defecto del proveedor (el mismo que su plugin de yt-dlp
    /// consulta automáticamente sin necesidad de pasarle `--extractor-args`).
    static let port = 4416

    /// Termina el servidor, si está en marcha (cierre de la app).
    static func stop() {
        lock.lock()
        let current = process
        process = nil
        lock.unlock()
        if let current, current.isRunning {
            current.terminate()
        }
    }
}
