import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let statusIconName = "play.rectangle.fill"
    private static let pausedIconName = "pause.rectangle.fill"
    private var statusItem: NSStatusItem!
    /// Estado de icono de la barra de menú: se recalcula por completo cada
    /// vez que cambia `isLoading` o `isPaused`, en vez de ir alternando
    /// pasos sueltos, para que ambos nunca compitan por `button.image`.
    private var isLoading = false
    private var isPaused = false
    /// Evita reprogramar la animación de giro si ya está en marcha.
    private var isShowingLoadingIcon = false
    private var pauseBlinkTimer: Timer?
    private var isShowingPausedIcon = false
    private var popover: NSPopover!
    private let playlistStore = PlaylistStore()
    private lazy var viewModel = PlayerViewModel(playlistStore: playlistStore)
    private var playlistWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var titleToastWindow: NSWindow?
    private var titleToastDismissWorkItem: DispatchWorkItem?
    private var titleToastMouseMonitors: [Any] = []
    private var titleToastIsHovering = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: Self.statusIconName, accessibilityDescription: "mpv YouTube Player")
            button.action = #selector(handleStatusItemClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 260)
        popover.contentViewController = NSHostingController(rootView: PlayerView(viewModel: viewModel))

        viewModel.onPlaybackStarted = { [weak self] in
            self?.closePopover()
        }
        viewModel.onOpenPlaylistRequested = { [weak self] in
            self?.showPlaylistWindow()
        }
        viewModel.onShowAboutRequested = { [weak self] in
            self?.showAboutWindow()
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
    }

    /// Punto único de decisión del icono de la barra de menú: `isLoading`
    /// gana siempre sobre `isPaused` (no pueden solaparse en la práctica,
    /// pero por si acaso), y solo cuando ninguno está activo se muestra el
    /// icono normal fijo.
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
                showNormalIcon()
            }
        }
    }

    private func showNormalIcon() {
        statusItem.button?.image = NSImage(systemSymbolName: Self.statusIconName, accessibilityDescription: "mpv YouTube Player")
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
        showNormalIcon()
        pauseBlinkTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            // Timer.scheduledTimer's closure isn't statically MainActor, but
            // it always fires on the run loop it was scheduled from — the
            // main one here, since this whole class is @MainActor.
            MainActor.assumeIsolated {
                self?.togglePauseBlinkIcon()
            }
        }
    }

    private func togglePauseBlinkIcon() {
        guard let button = statusItem.button else { return }
        isShowingPausedIcon.toggle()
        button.image = NSImage(
            systemSymbolName: isShowingPausedIcon ? Self.pausedIconName : Self.statusIconName,
            accessibilityDescription: "mpv YouTube Player"
        )
    }

    private func stopPauseBlink() {
        pauseBlinkTimer?.invalidate()
        pauseBlinkTimer = nil
        isShowingPausedIcon = false
    }

    private func showPlaylistWindow() {
        if playlistWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: PlaylistView(
                store: playlistStore,
                viewModel: viewModel,
                onItemPlayed: { [weak self] in self?.playlistWindow?.close() }
            )))
            window.title = "Playlist"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.setContentSize(NSSize(width: 460, height: 480))
            window.isReleasedWhenClosed = false
            window.center()
            playlistWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        playlistWindow?.makeKeyAndOrderFront(nil)
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
        menu.addItem(NSMenuItem(title: loc.t(.settings), action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: loc.t(.quit), action: #selector(quitApp), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettings() {
        showSettingsWindow()
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
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
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
