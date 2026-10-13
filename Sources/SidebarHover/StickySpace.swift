import AppKit

// Private SkyLight calls, the same technique boring.notch uses to keep its notch still.
@_silgen_name("_CGSDefaultConnection") private func CGSDefaultConnection() -> Int32
@_silgen_name("CGSSpaceCreate") private func CGSSpaceCreate(_ cid: Int32, _ flag: Int, _ options: NSDictionary?) -> Int
@_silgen_name("CGSSpaceSetAbsoluteLevel") private func CGSSpaceSetAbsoluteLevel(_ cid: Int32, _ space: Int, _ level: Int32)
@_silgen_name("CGSShowSpaces") private func CGSShowSpaces(_ cid: Int32, _ spaces: NSArray)
@_silgen_name("CGSAddWindowsToSpaces") private func CGSAddWindowsToSpaces(_ cid: Int32, _ windows: NSArray, _ spaces: NSArray)

/// A Space that is always shown above the user's Spaces. Its windows stay still while
/// the user swipes between Spaces, instead of sliding out and back in.
@MainActor
enum StickySpace {
    private static let space: Int = {
        let cid = CGSDefaultConnection()
        let space = CGSSpaceCreate(cid, 1, nil)
        CGSSpaceSetAbsoluteLevel(cid, space, Int32.max)
        CGSShowSpaces(cid, [space])
        return space
    }()

    static func add(_ window: NSWindow) {
        CGSAddWindowsToSpaces(CGSDefaultConnection(), [window.windowNumber], [space])
    }
}
