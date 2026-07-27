import Foundation

enum VideoTitleFetcher {
    static func fetchTitle(urlString: String, ytdlpPath: String, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ytdlpPath)
            process.arguments = ["--no-playlist", "--get-title", urlString]

            var environment = ProcessInfo.processInfo.environment
            let homebrewBinDirs = ["/opt/homebrew/bin", "/usr/local/bin"]
            let existingPath = environment["PATH"] ?? ""
            environment["PATH"] = (homebrewBinDirs + [existingPath]).joined(separator: ":")
            process.environment = environment

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    completion(nil)
                    return
                }
                let title = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                completion((title?.isEmpty ?? true) ? nil : title)
            } catch {
                completion(nil)
            }
        }
    }
}
