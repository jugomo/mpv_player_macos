import Darwin
import Foundation

/// Cliente mínimo del protocolo JSON IPC de mpv (--input-ipc-server) sobre un
/// socket unix, usado para mandar comandos (play/pause) a un mpv ya en
/// marcha y para observar cambios de propiedades (`pause`, `media-title`),
/// ya que mpv corre como proceso aparte y no hay otra forma de controlarlo
/// ni de leer su estado una vez lanzado.
final class MPVIPCClient {
    private let fileHandle: FileHandle
    private var buffer = Data()
    var onPauseChanged: ((Bool) -> Void)?
    /// mpv ya resuelve el título real vía su propio ytdl_hook al cargar el
    /// vídeo; lo leemos de aquí en vez de lanzar un segundo proceso yt-dlp
    /// solo para mostrarlo, que competía por red/CPU con la resolución de
    /// mpv y retrasaba el inicio de la reproducción.
    var onMediaTitleChanged: ((String) -> Void)?

    init?(socketPath: String) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(fd)
            return nil
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { rawPtr in
            let buf = rawPtr.bindMemory(to: CChar.self)
            for (index, byte) in pathBytes.enumerated() {
                buf[index] = byte
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { addrPtr -> Int32 in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            Darwin.close(fd)
            return nil
        }

        fileHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.handle(data)
        }
    }

    private func handle(_ data: Data) {
        buffer.append(data)
        while let newlineIndex = buffer.firstIndex(of: 0x0a) {
            let lineData = buffer.subdata(in: buffer.startIndex..<newlineIndex)
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
            guard !lineData.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  object["event"] as? String == "property-change",
                  let name = object["name"] as? String else { continue }
            switch name {
            case "pause":
                guard let paused = object["data"] as? Bool else { continue }
                DispatchQueue.main.async { [weak self] in
                    self?.onPauseChanged?(paused)
                }
            case "media-title":
                guard let title = object["data"] as? String, !title.isEmpty else { continue }
                DispatchQueue.main.async { [weak self] in
                    self?.onMediaTitleChanged?(title)
                }
            default:
                break
            }
        }
    }

    func send(command: [Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: ["command": command]) else { return }
        var payload = data
        payload.append(0x0a)
        fileHandle.write(payload)
    }

    func observePauseProperty() {
        send(command: ["observe_property", 1, "pause"])
    }

    func observeMediaTitleProperty() {
        send(command: ["observe_property", 2, "media-title"])
    }

    func close() {
        fileHandle.readabilityHandler = nil
        fileHandle.closeFile()
    }
}
