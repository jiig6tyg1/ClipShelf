import AppKit
import SwiftUI
import Carbon
import ApplicationServices
import ImageIO
import ServiceManagement

struct Shortcut: Codable, Equatable {
    var key: UInt32 = UInt32(kVK_ANSI_V)
    var modifiers: UInt32 = UInt32(controlKey)
    static let keys: [(String, UInt32)] = [
        ("A",0),("B",11),("C",8),("D",2),("E",14),("F",3),("G",5),("H",4),("I",34),("J",38),("K",40),("L",37),("M",46),("N",45),("O",31),("P",35),("Q",12),("R",15),("S",1),("T",17),("U",32),("V",9),("W",13),("X",7),("Y",16),("Z",6),
        ("0",29),("1",18),("2",19),("3",20),("4",21),("5",23),("6",22),("7",26),("8",28),("9",25),
        ("Space",49),("F1",122),("F2",120),("F3",99),("F4",118),("F5",96),("F6",97),("F7",98),("F8",100),("F9",101),("F10",109),("F11",103),("F12",111)
    ]
    var valid: Bool { modifiers != 0 && modifiers & ~UInt32(controlKey | optionKey | shiftKey | cmdKey) == 0 && Self.keys.contains { $0.1 == key } }
    var label: String {
        [(controlKey,"⌃"),(optionKey,"⌥"),(shiftKey,"⇧"),(cmdKey,"⌘")].filter { modifiers & UInt32($0.0) != 0 }.map { $0.1 }.joined() + (Self.keys.first { $0.1 == key }?.0 ?? "?")
    }
}

final class ShortcutSettings: ObservableObject {
    @Published var current: Shortcut
    @Published var draft: Shortcut
    @Published var showing = false
    @Published var error = ""
    var apply: ((Shortcut) -> Bool)?
    init() {
        let saved = UserDefaults.standard.data(forKey: "globalShortcut").flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
        let shortcut = saved?.valid == true ? saved! : Shortcut()
        current = shortcut
        draft = shortcut
    }
    func open() { draft = current; error = ""; showing = true }
    func save() {
        guard draft.valid else { error = "修飾キーを1つ以上選んでください。"; return }
        guard apply?(draft) == true else { error = "このキーは登録できません。別の組み合わせを選んでください。"; return }
        current = draft
        UserDefaults.standard.set(try? JSONEncoder().encode(current), forKey: "globalShortcut")
        showing = false
    }
    func flag(_ value: Int) -> Binding<Bool> {
        Binding(get: { self.draft.modifiers & UInt32(value) != 0 }, set: { enabled in
            if enabled { self.draft.modifiers |= UInt32(value) } else { self.draft.modifiers &= ~UInt32(value) }
        })
    }
}

extension View {
    @ViewBuilder func shelfGlass(radius: CGFloat = 24) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
        }
    }
}

final class PastePermissionStatus: ObservableObject {
    @Published var accessibility = AXIsProcessTrusted()
    @Published var eventPosting = CGPreflightPostEventAccess()
    func refresh() {
        accessibility = AXIsProcessTrusted()
        eventPosting = CGPreflightPostEventAccess()
    }
    func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

struct SettingsView: View {
    @StateObject private var loginItem = LoginItemSettings()
    @StateObject private var permissions = PastePermissionStatus()
    @ObservedObject var settings: ShortcutSettings
    @ObservedObject var store: ClipboardStore
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Image(systemName: "slider.horizontal.3").foregroundStyle(.blue)
                Text("設定").font(.title2.bold())
                Spacer()
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("履歴を開くショートカット").font(.headline)
                Text(settings.draft.label).font(.system(size: 28, weight: .medium, design: .rounded))
                    .frame(maxWidth: .infinity).padding(18).shelfGlass(radius: 16)
                HStack {
                    Toggle("⌃ Control", isOn: settings.flag(controlKey))
                    Toggle("⌥ Option", isOn: settings.flag(optionKey))
                }
                HStack {
                    Toggle("⇧ Shift", isOn: settings.flag(shiftKey))
                    Toggle("⌘ Command", isOn: settings.flag(cmdKey))
                }
                Picker("キー", selection: $settings.draft.key) {
                    ForEach(Shortcut.keys, id: \.1) { key in Text(key.0).tag(key.1) }
                }
                Text("Control・Option・Shift・Commandとキーを組み合わせて設定できます。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("初期設定（Ctrl＋V）に戻す") { settings.draft = Shortcut() }.buttonStyle(.link)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("入力位置への表示・自動貼り付け").font(.headline)
                Text("Enterで元のアプリへ貼り付けるには、アクセシビリティの許可が必要です。入力位置を取得できないアプリでは、マウス付近に表示します。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("アクセシビリティ：\(permissions.accessibility ? "許可済み" : "macOSが許可を認識していません")")
                    .font(.caption).foregroundStyle(permissions.accessibility ? Color.secondary : Color.red)
                Text("キー送信：\(permissions.eventPosting ? "許可済み" : "macOSが許可を認識していません")")
                    .font(.caption).foregroundStyle(permissions.eventPosting ? Color.secondary : Color.red)
                if !permissions.accessibility || !permissions.eventPosting {
                    Text("許可済みなのに上記が未認識の場合は、システム設定のClipShelfを一度削除し、アプリケーションフォルダのClipShelfを追加し直してください。開発用署名の更新で許可が無効になる場合があります。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("アクセシビリティの設定を開く") { permissions.openSettings() }
            }
            VStack(alignment: .leading, spacing: 7) {
                Toggle("ログイン時に開く", isOn: Binding(get: { loginItem.enabled }, set: { loginItem.setEnabled($0) }))
                if loginItem.status == .requiresApproval {
                    Text("システム設定でログイン項目の許可が必要です。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("ログイン項目の設定を開く") { SMAppService.openSystemSettingsLoginItems() }
                }
                if !loginItem.error.isEmpty { Text(loginItem.error).font(.caption).foregroundStyle(.red) }
            }
            Toggle("終了後も履歴を保存", isOn: $store.savesHistory)
            if !settings.error.isEmpty { Text(settings.error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("キャンセル") { settings.showing = false }.keyboardShortcut(.cancelAction)
                Button("保存") { settings.save() }.keyboardShortcut(.defaultAction).disabled(!settings.draft.valid)
            }
        }.padding(22).frame(width: 380)
        .onAppear { loginItem.refresh(); permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh(); permissions.refresh() }
    }
}

enum ShelfPalette {
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    static let card = adaptive(light: NSColor(white: 1, alpha: 0.82), dark: NSColor(calibratedRed: 0.25, green: 0.28, blue: 0.33, alpha: 0.88))
    static let control = adaptive(light: NSColor(white: 1, alpha: 0.78), dark: NSColor(calibratedRed: 0.32, green: 0.35, blue: 0.40, alpha: 0.88))
    static let border = adaptive(light: NSColor(white: 1, alpha: 0.9), dark: NSColor(white: 1, alpha: 0.20))
    static let selected = adaptive(light: NSColor(calibratedRed: 0.85, green: 0.93, blue: 1, alpha: 0.96), dark: NSColor(calibratedRed: 0.20, green: 0.36, blue: 0.53, alpha: 0.95))
}

struct ShelfButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(ShelfPalette.control, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(ShelfPalette.border))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

final class ThumbnailModel: ObservableObject { @Published var image: NSImage? }
struct ClipThumbnail: View {
    let clip: Clip
    let cache: ThumbnailCache
    @StateObject private var model = ThumbnailModel()
    var body: some View {
        Group {
            if let image = model.image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 130)
        .onAppear { model.image = cache.image(for: clip) }
        .onDisappear { model.image = nil }
    }
}

struct ShelfView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var settings: ShortcutSettings
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("検索", text: $store.query).textFieldStyle(.plain).focused($searchFocused)
                }.font(.system(size: 12)).padding(9)
                    .background(ShelfPalette.control, in: RoundedRectangle(cornerRadius: 6))
                Button("すべてクリア") { store.confirmsClear = true }
                    .buttonStyle(ShelfButtonStyle())
                    .disabled(!store.items.contains { !$0.pinned })
                Menu {
                    Button("設定…") { settings.open() }
                    Divider()
                    Button("ClipShelfを終了") { NSApp.terminate(nil) }
                } label: { Image(systemName: "gearshape").frame(width: 16, height: 16) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                    .frame(width: 30, height: 30)
                    .background(ShelfPalette.control, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(ShelfPalette.border))
                    .help("設定")
            }.padding(12)
            if store.visible.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text(store.query.isEmpty ? "履歴はありません" : "一致する履歴がありません").font(.system(size: 13))
                    if store.query.isEmpty { Text("コピーしたテキストや画像が表示されます").font(.system(size: 11)).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(store.visible) { clip in card(clip).id(clip.id) }
                        }.padding(.horizontal, 12).padding(.bottom, 12)
                    }.onChange(of: store.selected) { value in
                        if let value { withAnimation { proxy.scrollTo(value) } }
                    }
                }
            }
            if !store.message.isEmpty {
                Text(store.message).font(.caption).foregroundStyle(.orange).padding(10)
            }
        }
        .frame(minWidth: 340, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
        .shelfGlass(radius: 16)
        .sheet(isPresented: $settings.showing) { SettingsView(settings: settings, store: store) }
        .onAppear { searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .init("ShelfOpened"))) { _ in searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .init("ShelfSearch"))) { _ in searchFocused = true }
        .onChange(of: store.query) { _ in store.selected = store.visible.first?.id }
        .onExitCommand { NSApp.hide(nil) }
        .alert("ピン留め以外の履歴を消去しますか？", isPresented: $store.confirmsClear) {
            Button("キャンセル", role: .cancel) {}
            Button("消去", role: .destructive) { store.clear() }
        } message: { Text("現在のクリップボードの内容は保持されます。") }
    }
    func card(_ clip: Clip) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button { store.copy(clip) } label: {
                Group {
                    if let text = clip.text {
                        Text(String(text.prefix(600))).font(.system(size: 13)).lineLimit(5).lineSpacing(3)
                            .frame(maxWidth: .infinity, minHeight: 46, alignment: .topLeading)
                    } else if clip.image != nil {
                        ClipThumbnail(clip: clip, cache: store.thumbnails)
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help("元の入力先に貼り付ける")
            VStack(spacing: 8) {
                Menu {
                    Button(clip.pinned ? "ピン留めを解除" : "ピン留め", systemImage: clip.pinned ? "pin.slash" : "pin") { store.togglePin(clip) }
                    Button("削除", systemImage: "trash", role: .destructive) { store.delete(clip) }
                } label: { Image(systemName: "ellipsis").frame(width: 18, height: 18) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                    .frame(width: 28, height: 26)
                    .background(ShelfPalette.control, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(ShelfPalette.border))
                    .help("その他の操作")
                if clip.pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(.secondary).help("ピン留め済み") }
            }.padding(.trailing, 10).padding(.top, 10)
        }
        .background(store.selected == clip.id ? ShelfPalette.selected : ShelfPalette.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(store.selected == clip.id ? Color.accentColor : ShelfPalette.border, lineWidth: store.selected == clip.id ? 2 : 1))
    }
}

final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ClipboardStore()
    let settings = ShortcutSettings()
    var window: NSPanel!
    var statusItem: NSStatusItem!
    var previousApp: NSRunningApplication?
    var hotKey: EventHotKeyRef?
    var eventHandler: EventHandlerRef?
    var keyMonitor: Any?
    private var pasteGeneration = 0
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "設定…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "ClipShelfを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "編集")
        editMenu.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "すべて選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
        window = ShelfPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 460), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.title = "ClipShelf"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.isFloatingPanel = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: ShelfView(store: store, settings: settings))
        window.minSize = NSSize(width: 340, height: 360)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let statusImage = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipShelf")
        statusImage?.isTemplate = true
        statusItem.button?.image = statusImage
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.toolTip = "ClipShelf — \(settings.current.label)"
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            delegate.toggle()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        settings.apply = { [weak self] shortcut in self?.register(shortcut) ?? false }
        if !register(settings.current) { settings.error = "ショートカットを登録できません。別のキーを設定してください。"; settings.showing = true }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window.isKeyWindow, !self.settings.showing, self.window.attachedSheet == nil else { return event }
            if let editor = self.window.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            if event.modifierFlags.intersection([.command, .control, .option]).isEmpty == false { return event }
            switch event.keyCode {
            case 125: self.store.move(1); return nil
            case 126: self.store.move(-1); return nil
            case 36, 76:
                if let clip = self.store.visible.first(where: { $0.id == self.store.selected }) ?? self.store.visible.first { self.store.copy(clip) }
                return nil
            case 53: NSApp.hide(nil); return nil
            default:
                if let text = event.characters, text.unicodeScalars.contains(where: { !$0.properties.isWhitespace && $0.value >= 32 && $0.value < 0xF700 }) {
                    NotificationCenter.default.post(name: .init("ShelfSearch"), object: nil)
                }
                return event
            }
        }
        store.didCopy = { [weak self] in self?.pasteIntoPreviousApp() }
        show()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return true
    }
    func pasteIntoPreviousApp() {
        pasteGeneration += 1
        let generation = pasteGeneration
        let accessibilityAllowed = AXIsProcessTrusted()
        let eventPostingAllowed = CGPreflightPostEventAccess()
        guard accessibilityAllowed, eventPostingAllowed else {
            show()
            settings.open()
            settings.error = "現在のアプリの権限をmacOSが認識していません（アクセシビリティ: \(accessibilityAllowed ? "許可" : "未認識")、キー送信: \(eventPostingAllowed ? "許可" : "未認識")）。内容はコピー済みです。"
            return
        }
        guard let target = previousApp, !target.isTerminated,
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            show()
            store.message = "貼り付け先がありません。入力先でショートカットを押して開いてください。"
            return
        }
        guard target.activate(options: [.activateIgnoringOtherApps]) else {
            show(); store.message = "入力先に戻れませんでした。内容はコピー済みです。"; return
        }
        func deliver(_ attempt: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self, self.pasteGeneration == generation else { return }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
                    if attempt < 10 { deliver(attempt + 1) }
                    else { self.show(); self.store.message = "入力先への切り替えに失敗しました。内容はコピー済みです。" }
                    return
                }
                guard let source = CGEventSource(stateID: .privateState),
                      let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return }
                down.flags = .maskCommand
                up.flags = .maskCommand
                down.postToPid(target.processIdentifier)
                up.postToPid(target.processIdentifier)
            }
        }
        deliver(0)
    }
    func register(_ shortcut: Shortcut) -> Bool {
        guard shortcut.valid else { return false }
        if shortcut == settings.current, hotKey != nil { return true }
        var newKey: EventHotKeyRef?
        let result = RegisterEventHotKey(shortcut.key, shortcut.modifiers, EventHotKeyID(signature: 0x434C4950, id: 1), GetApplicationEventTarget(), 0, &newKey)
        guard result == noErr else { return false }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = newKey
        statusItem.button?.toolTip = "ClipShelf — \(shortcut.label)"
        return true
    }
    @objc func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "履歴を表示", action: #selector(toggle), keyEquivalent: "").target = self
            menu.addItem(withTitle: "設定…", action: #selector(openSettings), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "ClipShelfを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else { toggle() }
    }
    @objc func openSettings() { show(); settings.open() }
    @objc func toggle() {
        if settings.showing { show(); return }
        if window.isVisible && NSApp.isActive { NSApp.hide(nil) } else { show() }
    }
    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        // Read the source editor before activating our panel.
        let anchor = front?.processIdentifier != ProcessInfo.processInfo.processIdentifier ? InputAnchor.focusedRect() : nil
        let pointer = NSEvent.mouseLocation
        let target = anchor ?? CGRect(x: pointer.x, y: pointer.y, width: 1, height: 1)
        store.query = ""
        store.selected = store.visible.first?.id
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(target) }) ?? NSScreen.main {
            window.setFrameOrigin(InputAnchor.origin(anchor: target, panel: window.frame.size, screen: screen.visibleFrame))
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .init("ShelfOpened"), object: nil)
    }
    func applicationWillTerminate(_ notification: Notification) {
        store.flushPersistence()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
