import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let store: QuotaStore
    private var cancellables: Set<AnyCancellable> = []

    init(store: QuotaStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        configureStatusItem()
        configurePopover()
        bindStore()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.title = store.statusTitle
        button.toolTip = "Codex 额度"
        button.target = self
        button.action = #selector(togglePopover)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 500, height: 200)
        popover.contentViewController = NSHostingController(
            rootView: QuotaPanelView(store: store)
        )
    }

    private func bindStore() {
        store.$statusTitle
            .receive(on: RunLoop.main)
            .sink { [weak self] title in
                self?.statusItem.button?.title = title
            }
            .store(in: &cancellables)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        guard let button = statusItem.button else {
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }
}
