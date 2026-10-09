import AppKit
import SidebarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let client = HerdrClient()
    private var store: AgentStore!
    private var light: EdgeLightWindow!
    private var hover: HoverController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = AgentStore(api: client)
        store.start()
        hover = HoverController(model: PanelModel(store: store, api: client))
        light = EdgeLightWindow(store: store) { [weak self] inside in
            self?.hover.lightHover(inside)
        }
        hover.anchor = { [weak self] in self?.light.frame ?? .zero }
        light.orderFrontRegardless()
    }
}
