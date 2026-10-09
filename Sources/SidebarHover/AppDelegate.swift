import AppKit
import SidebarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let client = HerdrClient()
    private var store: AgentStore!
    private var light: EdgeLightWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = AgentStore(api: client)
        store.start()
        light = EdgeLightWindow(store: store) { _ in }
        light.orderFrontRegardless()
    }
}
