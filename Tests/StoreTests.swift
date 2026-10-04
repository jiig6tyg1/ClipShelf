let testBoard = NSPasteboard(name: NSPasteboard.Name("ClipShelf.tests.\(UUID())"))
let suite = "ClipShelf.tests.\(UUID())"
let prefs = UserDefaults(suiteName: suite)!
let testDir = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
let testURL = testDir.appendingPathComponent("history.json")
let store = ClipboardStore(board: testBoard, defaults: prefs, fileURL: testURL, monitoring: false)
func put(_ text: String, concealed: Bool = false) {
    testBoard.clearContents()
    testBoard.setString(text, forType: .string)
    if concealed { testBoard.setData(Data(), forType: .init("org.nspasteboard.ConcealedType")) }
    store.capture()
}
put("Alpha")
put("Beta")
put("Alpha")
assert(store.items.count == 2 && store.items[0].text == "Alpha", "deduplication")
store.togglePin(store.items[0])
put("Gamma")
assert(store.visible[0].text == "Alpha", "pinned ordering")
store.query = "beta"
assert(store.visible.count == 1 && store.visible[0].text == "Beta", "search")
store.query = ""
put("secret", concealed: true)
assert(!store.items.contains { $0.text == "secret" }, "concealed exclusion")
for i in 0..<100 { put("Item \(i)") }
assert(store.items.count == 80 && store.visible[0].text == "Alpha", "bounded history preserves pins")
store.clear()
assert(store.items.count == 1 && store.items[0].pinned, "clear preserves pins")
assert(!FileManager.default.fileExists(atPath: testURL.path), "no persistence by default")
store.savesHistory = true
store.flushPersistence()
let restored = ClipboardStore(board: testBoard, defaults: prefs, fileURL: testURL, monitoring: false)
assert(restored.items.count == 1 && restored.items[0].text == "Alpha", "persistence round trip")
store.savesHistory = false
store.flushPersistence()
assert(!FileManager.default.fileExists(atPath: testURL.path), "disable persistence removes file")
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
testBoard.clearContents()
testBoard.setData(bitmap.representation(using: .png, properties: [:])!, forType: .png)
store.capture()
assert(store.items.first?.image != nil, "image capture")
store.move(1)
assert(store.selected == store.visible.first?.id, "keyboard selection")
store.delete(store.items[0])
assert(store.items.count == 1, "delete")
prefs.removePersistentDomain(forName: suite)
testBoard.releaseGlobally()
try? FileManager.default.removeItem(at: testDir)
print("PASS: 12 clipboard behavior checks")
assert(Shortcut().label == "⌃V", "default Control V")
assert(!Shortcut(key: 9, modifiers: 0).valid, "modifier required")
assert(!Shortcut(key: 999, modifiers: UInt32(controlKey)).valid, "invalid key rejected")
let custom = Shortcut(key: 40, modifiers: UInt32(cmdKey | optionKey))
assert(custom.valid && custom.label == "⌥⌘K", "custom shortcut")
let decodedShortcut = try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(custom))
assert(decodedShortcut == custom, "shortcut persistence")
print("PASS: 5 shortcut checks")
let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
let panel = CGSize(width: 360, height: 460)
let below = InputAnchor.origin(anchor: CGRect(x: 400, y: 700, width: 1, height: 20), panel: panel, screen: screen)
assert(below == CGPoint(x: 400, y: 232), "panel below caret")
let above = InputAnchor.origin(anchor: CGRect(x: 400, y: 100, width: 1, height: 20), panel: panel, screen: screen)
assert(above == CGPoint(x: 400, y: 128), "panel above caret near screen bottom")
let edge = InputAnchor.origin(anchor: CGRect(x: 1430, y: 100, width: 1, height: 20), panel: panel, screen: screen)
assert(edge.x == 1072, "right edge clamped")
let leftScreen = CGRect(x: -1440, y: -200, width: 1440, height: 900)
let secondary = InputAnchor.origin(anchor: CGRect(x: -1439, y: 500, width: 1, height: 20), panel: panel, screen: leftScreen)
assert(secondary.x == -1432 && secondary.y == 32, "secondary display placement")
store.items = [Clip(text: "One"), Clip(text: "Two"), Clip(text: "Three")]
store.selected = store.visible.first?.id
store.move(1)
assert(store.selected == store.visible[1].id, "down moves to next item")
store.move(-1)
assert(store.selected == store.visible[0].id, "up moves to previous item")
print("PASS: 4 placement and 2 keyboard navigation checks")
let dataURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.plist")
let serialPrefs = UserDefaults(suiteName: "ClipShelf.serial.tests")!
serialPrefs.removePersistentDomain(forName: "ClipShelf.serial.tests")
let serial = ClipboardStore(board: testBoard, defaults: serialPrefs, fileURL: dataURL, monitoring: false)
serial.savesHistory = true
for i in 0..<50 { serial.items = [Clip(text: "Latest \(i)")]; serial.persist() }
serial.flushPersistence()
let finalSaved = try PropertyListDecoder().decode([Clip].self, from: Data(contentsOf: dataURL))
assert(finalSaved.first?.text == "Latest 49", "coalesced writer preserves newest snapshot")
serial.savesHistory = false
serial.flushPersistence()
assert(!FileManager.default.fileExists(atPath: dataURL.path), "disable cannot race with older writes")
serialPrefs.removePersistentDomain(forName: "ClipShelf.serial.tests")
try? FileManager.default.removeItem(at: dataURL.deletingLastPathComponent())
let cache = ThumbnailCache()
let largeBitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2048, pixelsHigh: 2048, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
memset(largeBitmap.bitmapData!, 127, largeBitmap.bytesPerRow * largeBitmap.pixelsHigh)
let largePNG = largeBitmap.representation(using: .png, properties: [:])!
for _ in 0..<40 {
    let thumb = cache.image(for: Clip(image: largePNG))!
    assert(max(thumb.size.width, thumb.size.height) <= 512, "thumbnail downsampling")
    assert(cache.byteCount <= ThumbnailCache.byteLimit, "cache budget")
}
cache.clear()
assert(cache.byteCount == 0, "cache purge")
assert(!ClipboardStore.valid(Clip(image: Data([1,2,3]))), "invalid image rejected")
let budgetBoard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
let budgetStore = ClipboardStore(board: budgetBoard, defaults: serialPrefs, fileURL: dataURL, monitoring: false)
for i in 0..<20 {
    var padded = largePNG
    padded.append(Data(repeating: UInt8(i), count: 4_000_000))
    budgetBoard.clearContents(); budgetBoard.setData(padded, forType: .png)
    budgetStore.capture()
    if i == 0 { budgetStore.togglePin(budgetStore.items[0]) }
    assert(budgetStore.payloadBytes <= ClipboardStore.byteLimit, "history budget")
}
assert(budgetStore.items.contains(where: { $0.pinned }), "budget eviction preserves pinned item")
budgetStore.flushPersistence()
budgetBoard.releaseGlobally()
print("PASS: persistence ordering, image validation, thumbnail and history budgets")
var mockLoginStatus: SMAppService.Status = .notRegistered
var registerCount = 0
var unregisterCount = 0
let login = LoginItemSettings(readStatus: { mockLoginStatus }, register: {
    registerCount += 1; mockLoginStatus = .enabled
}, unregister: {
    unregisterCount += 1; mockLoginStatus = .notRegistered
})
assert(!login.enabled && registerCount == 0, "login setting does not enable itself")
login.setEnabled(true)
assert(login.enabled && registerCount == 1, "login enable")
login.setEnabled(false)
assert(!login.enabled && unregisterCount == 1, "login disable")
mockLoginStatus = .requiresApproval
login.refresh()
assert(login.enabled && login.status == .requiresApproval, "approval pending is represented")
let denied = LoginItemSettings(readStatus: { .notRegistered }, register: { throw NSError(domain: "test", code: 1) })
denied.setEnabled(true)
assert(!denied.enabled && !denied.error.isEmpty, "failure reports actual service state")
print("PASS: 5 login-item settings checks (no system settings changed)")
