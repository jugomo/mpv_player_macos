import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Icono mostrado cuando no hay nada cargado en mpv (arranque de la app,
    /// o tras terminar/cerrar la reproducción). Es el icono original de la
    /// app (rectángulo relleno, look tipo YouTube), distinto del icono de
    /// reproducción para que "nada seleccionado" no se confunda con "en
    /// reproducción" a simple vista.
    private static let idleIconName = "play.rectangle.fill"
    private static let statusIconName = "play.fill"
    private static let pausedIconName = "pause.fill"
    private var statusItem: NSStatusItem!
    /// Estado de icono de la barra de menú: se recalcula por completo cada
    /// vez que cambia `isLoading`, `isPaused` o `isIdle`, en vez de ir
    /// alternando pasos sueltos, para que todos nunca compitan por
    /// `button.image`.
    private var isLoading = false
    private var isPaused = false
    /// `true` mientras no haya ningún item cargado en mpv (antes de la
    /// primera reproducción, o tras terminar/detenerse la actual).
    private var isIdle = true
    /// Evita reprogramar la animación de giro si ya está en marcha.
    private var isShowingLoadingIcon = false
    private var pauseBlinkTimer: Timer?
    private var isShowingPausedIcon = false
    private var popover: NSPopover!
    private let playlistStore = PlaylistStore()
    private let downloadManager = DownloadManager()
    private lazy var viewModel = PlayerViewModel(playlistStore: playlistStore)
    private var playlistWindow: NSWindow?
    private var playlistHostingController: NSHostingController<PlaylistView>?
    private var isPlaylistDocked = false
    private var dockedMainWindowObservers: [NSObjectProtocol] = []
    private var playlistWindowCloseObserver: NSObjectProtocol?
    private var focusLossObservers: [NSObjectProtocol] = []
    private weak var dockedMainWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var titleToastWindow: NSWindow?
    private var titleToastDismissWorkItem: DispatchWorkItem?
    private var titleToastMouseMonitors: [Any] = []
    private var titleToastIsHovering = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: Self.idleIconName, accessibilityDescription: "mpv player UI")
            button.action = #selector(handleStatusItemClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let playerHostingController = NSHostingController(rootView: PlayerView(viewModel: viewModel))
        // Sin esto, el popover se queda con el tamaño fijo de su primer
        // layout: si luego el título pasa a ocupar varias líneas (o aparece
        // la seek bar), SwiftUI comprime el contenido para caber en ese
        // alto viejo en vez de crecer, y el título se ve recortado a una
        // sola línea pese al lineLimit. Con esto, el popover sigue
        // ajustando su alto al contenido real en todo momento.
        playerHostingController.sizingOptions = [.preferredContentSize]
        popover = NSPopover()
        popover.behavior = Self.popoverBehavior
        popover.contentViewController = playerHostingController
        popover.delegate = self

        viewModel.onPlaybackStarted = { [weak self] in
            if PlaybackWindowSettingsManager.shared.closeWindowsOnPlay {
                self?.closePopover()
            }
            self?.isIdle = false
            self?.refreshStatusIcon()
        }
        viewModel.onPlaybackStopped = { [weak self] in
            self?.isIdle = true
            self?.refreshStatusIcon()
        }
        viewModel.onOpenPlaylistRequested = { [weak self] in
            self?.togglePlaylistVisibility()
        }
        viewModel.onShowTitleToastRequested = { [weak self] title in
            self?.showTitleToast(title)
        }
        viewModel.onLoadingStateChanged = { [weak self] isLoading in
            self?.isLoading = isLoading
            self?.refreshStatusIcon()
        }
        viewModel.onPauseStateChanged = { [weak self] isPaused in
            self?.isPaused = isPaused
            self?.refreshStatusIcon()
        }

        startObservingFocusLossForAutoClose()
    }

    /// Con `closeWindowsOnPlay` activado, la ventana principal y la playlist
    /// deben comportarse como una sola "sesión": mientras cualquiera de las
    /// dos tenga el foco, ambas siguen abiertas; en cuanto ninguna lo tenga
    /// (clic en otra app, en el escritorio, en la ventana de mpv, etc.) se
    /// cierran las dos juntas. Se comprueba en cualquier cambio de key
    /// window o de app activa, no solo en las nuestras, porque lo que
    /// importa es el estado resultante (quién es key ahora), no quién lo
    /// perdió.
    private func startObservingFocusLossForAutoClose() {
        let handler: (Notification) -> Void = { [weak self] _ in
            DispatchQueue.main.async {
                self?.closeCompanionWindowsIfFocusLost()
            }
        }
        focusLossObservers = [
            NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main, using: handler),
            NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main, using: handler),
        ]
    }

    private func closeCompanionWindowsIfFocusLost() {
        guard PlaybackWindowSettingsManager.shared.closeWindowsOnPlay else { return }
        guard popover.isShown || playlistWindow?.isVisible == true else { return }
        let keyWindow = NSApp.keyWindow
        let stillFocused = keyWindow != nil && (keyWindow === mainPopoverWindow() || keyWindow === playlistWindow)
        guard !stillFocused else { return }
        if popover.isShown { closePopover() }
        if playlistWindow?.isVisible == true { hidePlaylistWindow() }
    }

    /// Punto único de decisión del icono de la barra de menú: `isLoading`
    /// gana siempre sobre `isPaused`, y este a su vez sobre `isIdle` (no
    /// pueden solaparse en la práctica, pero por si acaso). Solo cuando
    /// ninguno de los tres está activo se muestra el icono fijo de
    /// "reproduciendo".
    private func refreshStatusIcon() {
        if isLoading {
            stopPauseBlink()
            showLoadingSpinIcon()
        } else {
            stopLoadingSpinIcon()
            if isPaused {
                startPauseBlink()
            } else {
                stopPauseBlink()
                if isIdle {
                    showIdleIcon()
                } else {
                    showPlayingIcon()
                }
            }
        }
    }

    private func showIdleIcon() {
        statusItem.button?.image = NSImage(systemSymbolName: Self.idleIconName, accessibilityDescription: "mpv player UI")
    }

    private func showPlayingIcon() {
        statusItem.button?.image = NSImage(systemSymbolName: Self.statusIconName, accessibilityDescription: "mpv player UI")
    }

    /// Sustituye el icono normal por uno giratorio mientras mpv/yt-dlp
    /// inicializan un vídeo (en vez de un segundo status item aparte: dos
    /// status items independientes no se garantiza que macOS los mantenga
    /// contiguos, y se desagrupaban al reordenar los iconos de la barra).
    private func showLoadingSpinIcon() {
        guard let button = statusItem.button, !isShowingLoadingIcon else { return }
        isShowingLoadingIcon = true
        button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Loading")
        button.wantsLayer = true
        // El layer de respaldo de un NSView ancla en la esquina (0,0), no en
        // el centro (0.5,0.5) como un CALayer normal: girar `rotation.z` sin
        // corregirlo hace que el icono orbite alrededor de esa esquina en vez
        // de girar sobre sí mismo. Recentrar el anchorPoint y restaurar el
        // frame a continuación evita ese "salto" sin mover el icono en pantalla.
        // El frame recién asignado tras cambiar la imagen puede no estar
        // finalizado todavía (AppKit difiere el layout) — forzarlo aquí evita
        // que se capture un frame stale, lo que en algunas máquinas (visto en
        // Intel) hacía que el giro quedara excéntrico en vez de concéntrico.
        button.layoutSubtreeIfNeeded()
        if let layer = button.layer {
            let frame = layer.frame
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.frame = frame
        }
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = -CGFloat.pi * 2
        rotation.duration = 0.9
        rotation.repeatCount = .infinity
        button.layer?.add(rotation, forKey: "mpvytp.loadingSpin")
    }

    private func stopLoadingSpinIcon() {
        guard isShowingLoadingIcon else { return }
        isShowingLoadingIcon = false
        statusItem.button?.layer?.removeAnimation(forKey: "mpvytp.loadingSpin")
    }

    /// Alterna el icono normal y uno de "pausa" cada 2s mientras el vídeo
    /// esté en pausa, para que se note de un vistazo sin tener que abrir el
    /// popover.
    private func startPauseBlink() {
        guard pauseBlinkTimer == nil else { return }
        isShowingPausedIcon = false
        showPlayingIcon()
        pauseBlinkTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            // Timer.scheduledTimer always fires on the run loop it was scheduled
            // from — the main one here, since this whole class is @MainActor.
            assert(Thread.isMainThread)
            self?.togglePauseBlinkIcon()
        }
    }

    private func togglePauseBlinkIcon() {
        guard let button = statusItem.button else { return }
        isShowingPausedIcon.toggle()

        button.wantsLayer = true
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.35
        button.layer?.add(fade, forKey: "mpvytp.pauseFade")

        button.image = NSImage(
            systemSymbolName: isShowingPausedIcon ? Self.pausedIconName : Self.statusIconName,
            accessibilityDescription: "mpv player UI"
        )
    }

    private func stopPauseBlink() {
        pauseBlinkTimer?.invalidate()
        pauseBlinkTimer = nil
        isShowingPausedIcon = false
    }

    private func makePlaylistView(docked: Bool) -> PlaylistView {
        PlaylistView(
            store: playlistStore,
            viewModel: viewModel,
            downloads: downloadManager,
            isDocked: docked,
            onItemPlayed: { [weak self] in
                if PlaybackWindowSettingsManager.shared.closeWindowsOnPlay {
                    self?.hidePlaylistWindow()
                }
            },
            onToggleDocked: { [weak self] in
                guard let self else { return }
                self.showPlaylistWindow(docked: !self.isPlaylistDocked)
            }
        )
    }

    /// Botón "Playlist" de la ventana principal: si la playlist ya está
    /// visible (acoplada o flotante) la oculta; si no, la muestra acoplada.
    /// La preferencia se persiste (a diferencia del cierre automático de
    /// `hidePlaylistWindow` al perder el foco o cerrarse la ventana
    /// principal, que no la toca) para que la próxima vez que se abra la
    /// ventana principal —incluso en un lanzamiento distinto de la app— la
    /// playlist vuelva a aparecer si se dejó así a propósito.
    private func togglePlaylistVisibility() {
        if playlistWindow?.isVisible == true {
            hidePlaylistWindow()
            PlaybackWindowSettingsManager.shared.playlistVisible = false
        } else {
            showPlaylistWindow(docked: true)
            PlaybackWindowSettingsManager.shared.playlistVisible = true
        }
    }

    private func hidePlaylistWindow() {
        playlistWindow?.orderOut(nil)
        stopObservingDockedMainWindow()
        viewModel.isPlaylistVisible = false
    }

    private static let defaultFloatingPlaylistSize = NSSize(width: 460, height: 480)

    /// Botón "Playlist" de la ventana principal (popover) => acoplada al
    /// lado izquierdo de esa ventana. Opción "Playlist" del menú contextual
    /// del ícono de la barra de menú => flotante, como antes.
    private func showPlaylistWindow(docked: Bool) {
        let wasAlreadyVisible = playlistWindow?.isVisible ?? false
        let modeChanged = isPlaylistDocked != docked
        isPlaylistDocked = docked

        if playlistWindow == nil {
            let hostingController = NSHostingController(rootView: makePlaylistView(docked: docked))
            let window = BorderlessInteractableWindow(contentViewController: hostingController)
            window.title = "Playlist"
            window.setContentSize(Self.defaultFloatingPlaylistSize)
            window.isReleasedWhenClosed = false
            playlistWindow = window
            playlistHostingController = hostingController
            installDockedResizeHandle(in: window)
            playlistWindowCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                self?.stopObservingDockedMainWindow()
                self?.viewModel.isPlaylistVisible = false
            }
        } else {
            playlistHostingController?.rootView = makePlaylistView(docked: docked)
        }

        guard let window = playlistWindow else { return }
        NSApp.activate(ignoringOtherApps: true)

        window.styleMask = docked ? [.resizable] : [.titled, .closable, .resizable, .miniaturizable]
        dockedResizeHandle?.isHidden = !docked

        if docked, let mainWindow = mainPopoverWindow() {
            window.isMovable = false
            observeDockedMainWindow(mainWindow)
            applyDockedFrame(to: window, relativeTo: mainWindow)
            if modeChanged || !wasAlreadyVisible {
                window.orderFront(nil)
                // Con la ventana aún no visible, el `setFrame` de arriba no
                // siempre alcanza a que SwiftUI/NSHostingController vuelvan
                // a maquetar su contenido al tamaño final (queda con el alto
                // por defecto del primer layout, centrado y dejando un
                // margen vacío arriba). Repetirlo ahora que la ventana ya
                // está en pantalla fuerza ese re-layout real — es el mismo
                // camino que sigue un redimensionado manual (que sí funciona).
                applyDockedFrame(to: window, relativeTo: mainWindow)
                animateRollOutReveal(on: window)
            }
        } else {
            stopObservingDockedMainWindow()
            window.isMovable = true
            if modeChanged {
                window.setContentSize(Self.defaultFloatingPlaylistSize)
            }
            if modeChanged || !wasAlreadyVisible {
                window.center()
            }
        }
        window.makeKeyAndOrderFront(nil)
        viewModel.isPlaylistVisible = true
    }

    /// Ventana real tras el popover (el globo del ícono de la barra de
    /// menú), usada como referencia para acoplar la playlist a su lado
    /// izquierdo. `nil` si el popover no está visible en ese momento.
    private func mainPopoverWindow() -> NSWindow? {
        guard popover.isShown else { return nil }
        return popover.contentViewController?.view.window
    }

    /// Ancho de la playlist acoplada. El usuario puede ensancharla
    /// arrastrando su borde izquierdo (ver `LeftEdgeResizeHandle`); se
    /// recuerda mientras la app siga abierta.
    private var dockedPlaylistWidth: CGFloat = 450
    private static let minDockedPlaylistWidth: CGFloat = 260
    private var dockedResizeHandle: LeftEdgeResizeHandle?

    private func applyDockedFrame(to window: NSWindow, relativeTo mainWindow: NSWindow) {
        let mainFrame = mainWindow.frame
        let frame = NSRect(
            x: mainFrame.minX - dockedPlaylistWidth,
            y: mainFrame.minY,
            width: dockedPlaylistWidth,
            height: mainFrame.height
        )
        window.setFrame(frame, display: true)
    }

    /// Instala, una sola vez, la franja invisible en el borde izquierdo del
    /// contenido de la ventana que permite ensancharla arrastrando (la
    /// ventana acoplada no tiene barra de título, así que AppKit no ofrece
    /// redimensionado automático por bordes). Se muestra/oculta según el
    /// modo (acoplada/flotante) en `showPlaylistWindow`.
    private func installDockedResizeHandle(in window: NSWindow) {
        guard let contentView = window.contentView else { return }
        let handle = LeftEdgeResizeHandle()
        handle.onDrag = { [weak self, weak window] deltaX in
            guard let self, let window else { return }
            self.adjustDockedPlaylistWidth(of: window, byDeltaX: deltaX)
        }
        handle.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(handle)
        NSLayoutConstraint.activate([
            handle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            handle.topAnchor.constraint(equalTo: contentView.topAnchor),
            handle.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            handle.widthAnchor.constraint(equalToConstant: 6),
        ])
        dockedResizeHandle = handle
    }

    /// Redimensiona la ventana acoplada arrastrando su borde izquierdo: el
    /// borde derecho (pegado a la ventana principal) queda fijo, y solo se
    /// mueve/crece el izquierdo, sin superar el borde de la pantalla.
    private func adjustDockedPlaylistWidth(of window: NSWindow, byDeltaX deltaX: CGFloat) {
        guard isPlaylistDocked else { return }
        var frame = window.frame
        let rightEdge = frame.maxX
        let proposedWidth = frame.width - deltaX
        let screenMinX = window.screen?.visibleFrame.minX ?? -.greatestFiniteMagnitude
        let maxWidth = rightEdge - screenMinX
        let newWidth = min(maxWidth, max(Self.minDockedPlaylistWidth, proposedWidth))
        frame.size.width = newWidth
        frame.origin.x = rightEdge - newWidth
        window.setFrame(frame, display: true)
        dockedPlaylistWidth = newWidth
    }

    /// Mantiene la playlist acoplada pegada a la ventana principal tanto si
    /// esta se mueve (p. ej. al reposicionarse el popover bajo el ícono de
    /// la barra de menú) como si cambia de alto en el sitio (el popover se
    /// redimensiona solo, sin "moverse", cuando su contenido crece o
    /// encoge, p. ej. al mostrar/ocultar la descripción) — de lo contrario
    /// la playlist se queda con un alto viejo y desalineado del actual.
    private func observeDockedMainWindow(_ mainWindow: NSWindow) {
        guard dockedMainWindow !== mainWindow else { return }
        stopObservingDockedMainWindow()
        dockedMainWindow = mainWindow
        let handler: (Notification) -> Void = { [weak self] _ in
            guard let self, self.isPlaylistDocked, let window = self.playlistWindow, let mainWindow = self.dockedMainWindow else { return }
            self.applyDockedFrame(to: window, relativeTo: mainWindow)
        }
        dockedMainWindowObservers = [
            NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: mainWindow, queue: .main, using: handler),
            NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: mainWindow, queue: .main, using: handler),
        ]
    }

    private func stopObservingDockedMainWindow() {
        for observer in dockedMainWindowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        dockedMainWindowObservers = []
        dockedMainWindow = nil
    }

    /// Efecto "roll-out": la ventana ya aparece en su posición y tamaño
    /// finales (acoplada a la izquierda de la ventana principal), pero su
    /// contenido queda inicialmente oculto tras una máscara que solo revela
    /// una franja de ancho cero pegada al borde derecho (el que toca la
    /// ventana principal). Esa máscara crece hacia la izquierda hasta cubrir
    /// toda la vista, dando la sensación de que la playlist se "descorre"
    /// hacia la izquierda desde debajo de la ventana principal, sin que el
    /// contenido SwiftUI se comprima como pasaría animando el frame real.
    private func animateRollOutReveal(on window: NSWindow) {
        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        let bounds = contentView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let maskLayer = CALayer()
        let toRect = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        maskLayer.frame = toRect
        contentView.layer?.mask = maskLayer

        let fromRect = CGRect(x: bounds.width, y: 0, width: 0, height: bounds.height)
        let animation = CABasicAnimation(keyPath: "frame")
        animation.fromValue = fromRect
        animation.toValue = toRect
        animation.duration = 0.32
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        maskLayer.add(animation, forKey: "mpvytp.playlistRollOut")

        DispatchQueue.main.asyncAfter(deadline: .now() + animation.duration) { [weak contentView] in
            contentView?.layer?.mask = nil
        }
    }

    private func showAboutWindow() {
        if aboutWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
            window.title = LocalizationManager.shared.t(.help)
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            aboutWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow?.makeKeyAndOrderFront(nil)
    }

    private func showSettingsWindow() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = LocalizationManager.shared.t(.settings)
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Aviso "reproduciendo ahora" a nivel de macOS (no un OSD dentro de la
    /// ventana de mpv): una ventana sin bordes, flotando bajo la barra de
    /// menú en la esquina superior derecha de la pantalla, que aparece con
    /// un fundido y se retira sola a los 2s — salvo que el ratón esté encima,
    /// en cuyo caso el cierre se pospone hasta que el ratón se retire.
    private func showTitleToast(_ title: String) {
        titleToastDismissWorkItem?.cancel()
        stopWatchingTitleToastHover()
        titleToastWindow?.orderOut(nil)

        guard let screen = NSScreen.main else { return }

        let hostingController = NSHostingController(rootView: TitleToastView(title: title))
        let window = NonActivatingPanel(contentViewController: hostingController)
        window.styleMask = [.borderless]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false

        // `fittingSize` mide con anchura sin restricción, así que un `Text`
        // envolvible (hasta 3 líneas) nunca llegaba a envolver: siempre
        // medía como si cupiera en una sola línea. `sizeThatFits(in:)` sí
        // acepta una anchura máxima propuesta, dejando que el texto largo
        // envuelva dentro de ese límite y que el corto siga ajustándose a
        // su contenido.
        let fittingSize = hostingController.sizeThatFits(in: NSSize(width: 480, height: CGFloat.greatestFiniteMagnitude))
        let margin: CGFloat = 10
        let origin = NSPoint(
            x: screen.visibleFrame.maxX - fittingSize.width - margin,
            y: screen.visibleFrame.maxY - fittingSize.height - margin
        )
        window.setFrame(NSRect(origin: origin, size: fittingSize), display: false)

        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window.animator().alphaValue = 1
        }

        titleToastWindow = window
        titleToastIsHovering = false
        startWatchingTitleToastHover()
        scheduleTitleToastDismiss()
    }

    /// El hover se vigila con monitores de eventos de ratón en vez de
    /// `.onHover` de SwiftUI: esta ventana nunca es la app activa ni la
    /// ventana clave (ver `NonActivatingPanel`), y `.onHover` no siempre se
    /// dispara en esas condiciones. El monitor global cubre el caso normal
    /// (otra app, p. ej. mpv, en primer plano) y el local cubre el caso en
    /// que esta app sí esté activa en ese momento.
    private func startWatchingTitleToastHover() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            self?.updateTitleToastHoverState()
        }
        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: handler)
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
            handler(event)
            return event
        }
        titleToastMouseMonitors = [globalMonitor, localMonitor].compactMap { $0 }
    }

    private func stopWatchingTitleToastHover() {
        for monitor in titleToastMouseMonitors {
            NSEvent.removeMonitor(monitor)
        }
        titleToastMouseMonitors.removeAll()
    }

    private func updateTitleToastHoverState() {
        guard let window = titleToastWindow else { return }
        let isInside = window.frame.contains(NSEvent.mouseLocation)
        guard isInside != titleToastIsHovering else { return }
        titleToastIsHovering = isInside
        if isInside {
            titleToastDismissWorkItem?.cancel()
        } else {
            scheduleTitleToastDismiss()
        }
    }

    private func scheduleTitleToastDismiss() {
        titleToastDismissWorkItem?.cancel()
        let dismissWorkItem = DispatchWorkItem { [weak self] in
            self?.dismissTitleToast()
        }
        titleToastDismissWorkItem = dismissWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: dismissWorkItem)
    }

    private func dismissTitleToast() {
        guard let window = titleToastWindow else { return }
        stopWatchingTitleToastHover()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                window.orderOut(nil)
                if self?.titleToastWindow === window {
                    self?.titleToastWindow = nil
                }
            }
        })
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func showContextMenu() {
        let loc = LocalizationManager.shared
        let menu = NSMenu()
        let playlistItem = NSMenuItem(title: loc.t(.playlist), action: #selector(openPlaylist), keyEquivalent: "")
        playlistItem.image = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: loc.t(.playlist))
        menu.addItem(playlistItem)
        let settingsItem = NSMenuItem(title: loc.t(.settings), action: #selector(openSettings), keyEquivalent: "")
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: loc.t(.settings))
        menu.addItem(settingsItem)
        let helpItem = NSMenuItem(title: loc.t(.help), action: #selector(openHelp), keyEquivalent: "")
        helpItem.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: loc.t(.help))
        menu.addItem(helpItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: loc.t(.quit), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: loc.t(.quit))
        menu.addItem(quitItem)
        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openPlaylist() {
        showPlaylistWindow(docked: false)
    }

    @objc private func openSettings() {
        showSettingsWindow()
    }

    @objc private func openHelp() {
        showAboutWindow()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        MPVLauncher.terminateAllRunningProcesses()
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            closePopover()
        } else {
            viewModel.refreshDependencyStatus()
            popover.behavior = Self.popoverBehavior
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            repositionPopoverBelowStatusItem(sender)
            if PlaybackWindowSettingsManager.shared.playlistVisible {
                showPlaylistWindow(docked: true)
            }
        }
    }

    /// Siempre `.applicationDefined`: nunca dejamos que `NSPopover` decida
    /// por su cuenta cuándo cerrarse (su modo `.transient` lo cierra en
    /// cuanto CUALQUIER otra ventana pasa a ser la key window, incluida la
    /// playlist acoplada/flotante que abrimos nosotros mismos — así se
    /// cerraba la principal nada más pulsar "Mostrar playlist"). En su
    /// lugar, `closeCompanionWindowsIfFocusLost` implementa el mismo cierre
    /// automático a mano, pero sabiendo distinguir "el foco pasó a la otra
    /// ventana nuestra" (no cerrar) de "el foco se fue de verdad" (cerrar
    /// ambas).
    private static let popoverBehavior: NSPopover.Behavior = .applicationDefined

    /// Con "ocultar y mostrar automáticamente la barra de menús" activo,
    /// `NSPopover.show(relativeTo:of:)` calcula la posición como si la barra
    /// tuviera su alto habitual en vez de partir del botón ya visible,
    /// dejando un hueco del tamaño de esa barra entre el ícono y el globo.
    /// Se corrige reubicando la ventana del globo a mano, usando el frame
    /// real y actual del botón en coordenadas de pantalla.
    ///
    /// Al recalcular el origen a mano perdemos el ajuste automático que
    /// `NSPopover` aplica para no salirse de la pantalla: si el ícono está
    /// cerca del borde derecho, centrar el popover bajo el botón lo hace
    /// asomar fuera del `visibleFrame` y quedar recortado. Se limita el eje
    /// X al rango válido de la pantalla del botón para que el globo quede
    /// siempre completo, aunque eso desplace la punta/flecha lejos del centro
    /// del ícono en ese caso.
    private func repositionPopoverBelowStatusItem(_ sender: NSStatusBarButton) {
        guard let buttonWindow = sender.window,
              let popoverWindow = popover.contentViewController?.view.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }
        let buttonFrameOnScreen = buttonWindow.convertToScreen(sender.convert(sender.bounds, to: nil))
        let popoverSize = popoverWindow.frame.size
        let idealX = buttonFrameOnScreen.midX - popoverSize.width / 2
        let minX = screen.visibleFrame.minX
        let maxX = screen.visibleFrame.maxX - popoverSize.width
        let origin = NSPoint(
            x: min(max(idealX, minX), maxX),
            y: buttonFrameOnScreen.minY - popoverSize.height
        )
        popoverWindow.setFrameOrigin(origin)
    }

    private func closePopover() {
        popover.performClose(nil)
    }
}

extension AppDelegate: NSPopoverDelegate {
    /// Marca el popover como visible para que `PlayerViewModel` reanude las
    /// actualizaciones del vúmetro (ver `isWindowVisible`), congeladas
    /// mientras estaba cerrado.
    func popoverDidShow(_ notification: Notification) {
        viewModel.isWindowVisible = true
    }

    /// Al cerrarse la ventana principal (botón de la barra de menú, clic
    /// fuera con comportamiento `.transient`, etc.), la playlist deja de
    /// tener sentido visible —sobre todo acoplada, ya que quedaría flotando
    /// sola sin nada a lo que estar pegada— así que se oculta junto con ella.
    ///
    /// También marca el popover como no visible para que `PlayerViewModel`
    /// deje de aplicar las actualizaciones del vúmetro que mpv sigue
    /// mandando por IPC mientras reproduce en segundo plano (ver
    /// `isWindowVisible`): sin esto, `NSHostingController` seguía
    /// recalculando el layout completo de la vista en cada una aunque no
    /// hubiera ninguna ventana en pantalla.
    func popoverDidClose(_ notification: Notification) {
        viewModel.isWindowVisible = false
        if viewModel.isPlaylistVisible {
            hidePlaylistWindow()
        }
    }
}

/// Ventana del toast: recibe eventos de ratón (para detectar hover y pausar
/// el auto-cierre) pero nunca pasa a ser la ventana clave/principal, así que
/// ni roba el foco de mpv/otra app ni activa esta app en segundo plano solo
/// por mover el cursor sobre ella o por un clic accidental.
private final class NonActivatingPanel: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// La ventana de la playlist se vuelve borderless en modo acoplado (sin
/// barra de título). Un `NSWindow` borderless normal no puede pasar a ser la
/// ventana clave por defecto, lo que rompería el foco/teclado en sus
/// controles; esta subclase lo permite igualmente.
private final class BorderlessInteractableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Franja invisible en el borde izquierdo del contenido de la playlist
/// acoplada: al no tener barra de título, AppKit no ofrece redimensionado
/// automático arrastrando el borde, así que se implementa a mano aquí. Solo
/// informa el desplazamiento del ratón; quien la usa decide cómo aplicarlo
/// al frame de la ventana (ver `AppDelegate.adjustDockedPlaylistWidth`).
private final class LeftEdgeResizeHandle: NSView {
    var onDrag: ((_ deltaX: CGFloat) -> Void)?

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(event.deltaX)
    }
}
