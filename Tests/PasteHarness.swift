import AppKit
final class Harness: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var editor: NSTextView!
    let marker = "ClipShelf paste verification 2026"
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let item = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = edit; menu.addItem(item); NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 200, y: 280, width: 580, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ClipShelf Paste Verification"
        editor = NSTextView(frame: NSRect(x: 20, y: 75, width: 540, height: 195))
        editor.font = .systemFont(ofSize: 18)
        editor.isRichText = false
        window.contentView?.addSubview(editor)
        let button = NSButton(title: "Prepare sample and open ClipShelf", target: self, action: #selector(prepare))
        button.frame = NSRect(x: 20, y: 20, width: 380, height: 35)
        window.contentView?.addSubview(button)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func prepare() {
        NSApp.activate(ignoringOtherApps: true)
        editor.string = ""
        window.makeFirstResponder(editor)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(marker, forType: .string)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: CommandLine.arguments[1]), configuration: config)
        }
    }
}
let app = NSApplication.shared
let delegate = Harness()
app.delegate = delegate
app.run()
