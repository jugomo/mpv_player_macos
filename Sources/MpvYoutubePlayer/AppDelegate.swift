import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let playlistStore = PlaylistStore()
    private lazy var viewModel = PlayerViewModel(playlistStore: playlistStore)
    private var playlistWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "mpv YouTube Player")
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
        viewModel.onQuitRequested = {
            NSApp.terminate(nil)
        }
        viewModel.onOpenPlaylistRequested = { [weak self] in
            self?.showPlaylistWindow()
        }
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

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Salir", action: #selector(quitApp), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
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
