import Foundation

/// Estado y ciclo de vida de la búsqueda: debounce de la query
/// tecleada, cancelación de la búsqueda en curso al llegar una nueva o al
/// cerrarse la ventana, y watchdog de tiempo máximo total (ver
/// `YtDlpSearchFetcher`: `--socket-timeout` solo acota operaciones de red
/// individuales, no todo el crawl de `ytsearch`).
///
/// Vive fuera de `SearchView` (lo posee `AppDelegate`, como `PlaylistStore`/
/// `DownloadManager`) para que una búsqueda en curso sobreviva a cerrar y
/// reabrir la ventana.
@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = "" {
        didSet { scheduleSearch() }
    }
    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var errorMessage: String?

    /// Mínimo de caracteres para lanzar una búsqueda: evita procesos yt-dlp
    /// para queries de una letra que no devolverían nada útil.
    private static let minimumQueryLength = 2
    private static let debounceSeconds: Double = 0.4
    private static let timeoutSeconds: Double = 15

    private var debounceTask: DispatchWorkItem?
    private var timeoutTask: DispatchWorkItem?
    private var currentSearch: YtDlpSearchFetcher.SearchTask?
    /// Distingue una búsqueda de otra más nueva: si el resultado/fin de una
    /// búsqueda llega después de que ya se lanzó otra, se descarta en vez de
    /// pisar el estado de la búsqueda actual.
    private var currentToken = 0

    /// Se pide de forma perezosa (no se guarda una copia fija en el init)
    /// porque puede cambiar tras `refreshDependencyStatus()` — p.ej. si el
    /// usuario instala yt-dlp con la ventana de búsqueda ya abierta.
    private let ytdlpPath: () -> String?

    init(ytdlpPath: @escaping () -> String?) {
        self.ytdlpPath = ytdlpPath
    }

    private func scheduleSearch() {
        debounceTask?.cancel()
        cancelInFlightSearch()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumQueryLength else {
            results = []
            errorMessage = nil
            return
        }
        let task = DispatchWorkItem { [weak self] in self?.runSearch(trimmed) }
        debounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceSeconds, execute: task)
    }

    private func runSearch(_ query: String) {
        guard let ytdlpPath = ytdlpPath() else {
            errorMessage = LocalizationManager.shared.t(.searchNeedsYtdlp)
            return
        }
        currentToken += 1
        let token = currentToken
        isSearching = true
        errorMessage = nil
        results = []

        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.currentToken == token else { return }
            self.currentSearch?.cancel()
            self.errorMessage = LocalizationManager.shared.t(.searchTimedOut)
            self.isSearching = false
        }
        timeoutTask = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeoutSeconds, execute: timeout)

        currentSearch = YtDlpSearchFetcher.search(
            query: query,
            ytdlpPath: ytdlpPath,
            onResult: { [weak self] result in
                guard let self, self.currentToken == token else { return }
                self.results.append(result)
            },
            onFinished: { [weak self] failureMessage in
                guard let self, self.currentToken == token else { return }
                self.timeoutTask?.cancel()
                self.timeoutTask = nil
                self.isSearching = false
                self.currentSearch = nil
                // `onFinished(nil)` es justo lo que reporta tanto un final
                // sin errores como una cancelación (propia o del watchdog de
                // arriba): si el timeout ya dejó su propio mensaje, no debe
                // borrarlo.
                if let failureMessage {
                    self.errorMessage = failureMessage
                }
            }
        )
    }

    /// Cancela la búsqueda en curso (y su watchdog) sin dejar mensaje de
    /// error: llegó una query nueva, o se cerró la ventana. A diferencia del
    /// timeout, esto no es un fallo que el usuario deba ver.
    func cancelInFlightSearch() {
        timeoutTask?.cancel()
        timeoutTask = nil
        currentSearch?.cancel()
        currentSearch = nil
        isSearching = false
    }
}
