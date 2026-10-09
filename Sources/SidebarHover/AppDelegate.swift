import AppKit
import ServiceManagement
import SidebarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let client = HerdrClient()
    private var store: AgentStore!
    private var light: EdgeLightWindow!
    private var hover: HoverController!
    private var statusItem: NSStatusItem!
    private let loginItem = NSMenuItem(title: "Start at login", action: #selector(toggleLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = AgentStore(api: client)
        store.start()
        hover = HoverController(model: PanelModel(store: store, api: client))
        light = EdgeLightWindow(store: store) { [weak self] inside in
            self?.hover.lightHover(inside)
        }
        hover.anchor = { [weak self] in self?.light.frame ?? .zero }
        light.orderFrontRegardless()
        setUpStatusItem()
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "light.beacon.max",
                                           accessibilityDescription: "SidebarHover")
        let menu = NSMenu()
        menu.delegate = self
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
