import Foundation

enum HomebrewInstallerError: LocalizedError {
    case brewNotFound
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .brewNotFound:
            return "Homebrew no está instalado."
        case .processFailed(let output):
            return "brew install falló:\n\(output)"
        }
    }
}

enum HomebrewInstaller {
    /// Homebrew's official installer requests an interactive sudo password,
    /// so we never run it unattended from a background Process — instead we
    /// open Terminal.app with the command pre-filled for the user to review
    /// and run themselves.
    static func openTerminalForHomebrewInstall() {
        let command = #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#
        let script = """
        tell application "Terminal"
            activate
            do script "\(command.replacingOccurrences(of: "\"", with: "\\\""))"
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    /// Runs `brew install <packages>`, streaming combined stdout/stderr lines
    /// to `progress` on the main thread, then calls `completion` when done.
    static func install(
        packages: [String],
        brewPath: String,
        progress: @escaping (String) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard !packages.isEmpty else {
            completion(.success(()))
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = ["install"] + packages

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        var outputBuffer = ""

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            outputBuffer += chunk
            let lastLine = chunk
                .split(separator: "\n", omittingEmptySubsequences: true)
                .last
                .map(String.init) ?? chunk
            DispatchQueue.main.async {
                progress(lastLine.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        process.terminationHandler = { finishedProcess in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                if finishedProcess.terminationStatus == 0 {
                    completion(.success(()))
                } else {
                    completion(.failure(HomebrewInstallerError.processFailed(outputBuffer)))
                }
            }
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            completion(.failure(error))
        }
    }
}
