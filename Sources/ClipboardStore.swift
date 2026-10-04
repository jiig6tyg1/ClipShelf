import AppKit
import SwiftUI
import Carbon
import ApplicationServices
import ImageIO

struct Clip: Identifiable, Codable {
    var id = UUID()
    var text: String?
    var image: Data?
    var date = Date()
    var pinned = false
    var label: String { text ?? "画像" }
    var byteCount: Int { image?.count ?? text?.utf8.count ?? 0 }
}

/// Serial, coalescing writer: at most one in-flight and one latest snapshot.
/// Removing history is ordered after any previous write, so it cannot reappear.
final class HistoryWriter: @unchecked Sendable {
    private struct Job { let items: [Clip]?; let revision: Int }
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "local.clipshelf.persistence", qos: .utility)
    private var latest: Job?
    private var running = false
    private var revision = 0
    private let url: URL
    private let legacyURL: URL?
    var completion: ((Int, String?) -> Void)?
    init(url: URL, legacyURL: URL?) { self.url = url; self.legacyURL = legacyURL }
    @discardableResult func submit(_ items: [Clip]?) -> Int {
        lock.lock()
        revision += 1
        let current = revision
        latest = Job(items: items, revision: current)
        let start = !running
        running = true
        lock.unlock()
        if start { queue.async { self.drain() } }
        return current
    }
    private func drain() {
        while true {
            lock.lock()
            guard let job = latest else { running = false; lock.unlock(); return }
            latest = nil
            lock.unlock()
            let error: String? = autoreleasepool {
                do {
                    if let items = job.items {
                        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                        let encoder = PropertyListEncoder()
                        encoder.outputFormat = .binary
                        try encoder.encode(items).write(to: url, options: .atomic)
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                    } else if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                    }
                    if job.items == nil, let legacyURL, FileManager.default.fileExists(atPath: legacyURL.path) {
                        try FileManager.default.removeItem(at: legacyURL)
                    }
                    return nil
                } catch { return "履歴の保存・削除に失敗しました" }
            }
            DispatchQueue.main.async { self.completion?(job.revision, error) }
        }
    }
    func flush() { queue.sync {} }
}

/// Downsample before decoding. The cache owns at most 12 MiB of pixel data.
final class ThumbnailCache {
    private var images: [UUID: (NSImage, Int)] = [:]
    private var order: [UUID] = []
    private(set) var byteCount = 0
    static let byteLimit = 12 * 1024 * 1024
    func image(for clip: Clip) -> NSImage? {
        if let cached = images[clip.id] {
            order.removeAll { $0 == clip.id }; order.append(clip.id)
            return cached.0
        }
        guard let data = clip.image,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let cost = cg.bytesPerRow * cg.height
        while byteCount + cost > Self.byteLimit, let oldest = order.first { remove(oldest) }
        let result = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        if cost <= Self.byteLimit { images[clip.id] = (result, cost); order.append(clip.id); byteCount += cost }
        return result
    }
    private func remove(_ id: UUID) {
        if let item = images.removeValue(forKey: id) { byteCount -= item.1 }
        order.removeAll { $0 == id }
    }
    func retain(_ ids: Set<UUID>) { for id in order where !ids.contains(id) { remove(id) } }
    func clear() { images.removeAll(); order.removeAll(); byteCount = 0 }
}

final class ClipboardStore: ObservableObject {
    static let byteLimit = 48 * 1024 * 1024
    static let imageLimit = 8_000_000
    static let textLimit = 1_000_000
    var didCopy: (() -> Void)?
    let thumbnails = ThumbnailCache()
    @Published var items: [Clip] = []
    @Published var query = ""
    @Published var selected: UUID?
    @Published var message = ""
    @Published var confirmsClear = false
    @Published var savesHistory: Bool {
        didSet {
            defaults.set(savesHistory, forKey: "saveHistory")
            persist()
        }
    }
    private let board: NSPasteboard
    private let defaults: UserDefaults
    private var lastChange: Int
    private var timer: Timer?
    private let limit = 80
    private let writer: HistoryWriter
    private var revision = 0
    private var pressure: DispatchSourceMemoryPressure?
    var payloadBytes: Int { items.reduce(0) { $0 + $1.byteCount } }
    var visible: [Clip] {
        items.filter { query.isEmpty || $0.label.localizedCaseInsensitiveContains(query) }
            .sorted { a, b in a.pinned != b.pinned ? a.pinned : a.date > b.date }
    }
    init(board: NSPasteboard = .general, defaults: UserDefaults = .standard, fileURL: URL? = nil, monitoring: Bool = true) {
        self.board = board
        self.defaults = defaults
        self.lastChange = board.changeCount
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ClipShelf")
        let url = fileURL ?? directory.appendingPathComponent("history.plist")
        let legacy = fileURL == nil ? directory.appendingPathComponent("history.json") : nil
        self.writer = HistoryWriter(url: url, legacyURL: legacy)
        self.savesHistory = defaults.bool(forKey: "saveHistory")
        if savesHistory {
            let source = FileManager.default.fileExists(atPath: url.path) ? url : (legacy ?? url)
            // Old versions could save ~850 MB of base64 JSON; don't allocate it on launch.
            if let size = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 96 * 1024 * 1024 {
                message = "保存履歴が大きすぎるため読み込みませんでした。元ファイルは保持しています。"
            } else if let data = try? Data(contentsOf: source, options: .mappedIfSafe) {
                if let saved = (try? PropertyListDecoder().decode([Clip].self, from: data)) ?? (try? JSONDecoder().decode([Clip].self, from: data)) {
                    items = saved.filter(Self.valid)
                    var seen = Set<UUID>()
                    items = items.filter { seen.insert($0.id).inserted }
                    var pins = 0
                    for index in items.indices where items[index].pinned {
                        pins += 1
                        if pins > 20 { items[index].pinned = false }
                    }
                    enforceLimits()
                } else { message = "保存履歴を読み込めませんでした。" }
            }
        }
        writer.completion = { [weak self] revision, error in
            guard let self, self.revision == revision else { return }
            if let error { self.message = error }
        }
        if monitoring {
            timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
                autoreleasepool { self?.capture() }
            }
            timer?.tolerance = 0.15
            pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
            pressure?.setEventHandler { [weak self] in self?.thumbnails.clear() }
            pressure?.resume()
        }
    }
    deinit { timer?.invalidate(); pressure?.cancel() }
    static func valid(_ clip: Clip) -> Bool {
        if let text = clip.text { return clip.image == nil && !text.isEmpty && text.utf8.count <= textLimit }
        guard let image = clip.image, image.count <= imageLimit,
              let source = CGImageSourceCreateWithData(image as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return false }
        return width.doubleValue > 0 && height.doubleValue > 0 && width.doubleValue * height.doubleValue <= 40_000_000
    }
    private func enforceLimits() {
        var bytes = payloadBytes
        while items.count > limit || bytes > Self.byteLimit {
            guard let index = items.lastIndex(where: { !$0.pinned }) else {
                // Only a malformed/legacy archive can have pinned data above the budget.
                if let last = items.popLast() { bytes -= last.byteCount; continue }
                break
            }
            bytes -= items.remove(at: index).byteCount
        }
        thumbnails.retain(Set(items.map(\.id)))
    }
    func capture() {
        guard board.changeCount != lastChange else { return }
        lastChange = board.changeCount
        let excluded = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword"]
        guard !excluded.contains(where: { board.types?.contains(NSPasteboard.PasteboardType($0)) == true }) else { return }
        var clip: Clip
        if let text = board.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard text.utf8.count <= Self.textLimit else { return }
            clip = Clip(text: text)
        } else if let data = board.data(forType: .png) ?? board.data(forType: .tiff), data.count <= Self.imageLimit {
            clip = Clip(image: data)
            guard Self.valid(clip) else { return }
        } else { return }
        if let index = items.firstIndex(where: { $0.text == clip.text && $0.image == clip.image }) {
            clip = items.remove(at: index)
            clip.date = Date()
        }
        items.insert(clip, at: 0)
        enforceLimits()
        if !items.contains(where: { $0.id == clip.id }) { message = "ピン留め済みの履歴が容量上限に達しています。" }
        persist()
    }
    func copy(_ clip: Clip) {
        board.clearContents()
        if let text = clip.text { board.setString(text, forType: .string) }
        else if let data = clip.image {
            let isPNG = data.starts(with: [137,80,78,71,13,10,26,10])
            board.setData(data, forType: isPNG ? .png : .tiff)
        }
        lastChange = board.changeCount
        NSApp.hide(nil)
        didCopy?()
    }
    func togglePin(_ clip: Clip) {
        guard let index = items.firstIndex(where: { $0.id == clip.id }) else { return }
        if !items[index].pinned && items.filter({ $0.pinned }).count >= 20 { message = "ピン留めは20件までです"; return }
        items[index].pinned.toggle()
        persist()
    }
    func delete(_ clip: Clip) { items.removeAll { $0.id == clip.id }; thumbnails.retain(Set(items.map(\.id))); persist() }
    func clear() { items.removeAll { !$0.pinned }; thumbnails.retain(Set(items.map(\.id))); persist() }
    func move(_ step: Int) {
        let list = visible
        guard !list.isEmpty else { return }
        if let index = list.firstIndex(where: { $0.id == selected }) { selected = list[min(max(0, index + step), list.count - 1)].id }
        else { selected = list[0].id }
    }
    func persist() { revision = writer.submit(savesHistory ? items : nil) }
    func flushPersistence() { writer.flush() }
}

