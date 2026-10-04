import Darwin
func measurement(_ label: String, _ store: ClipboardStore) {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    precondition(result == KERN_SUCCESS)
    let payload = store.items.reduce(0) { $0 + ($1.image?.count ?? $1.text?.utf8.count ?? 0) }
    print("\(label),\(store.items.count),\(payload),\(info.resident_size),\(info.phys_footprint)")
    fflush(stdout)
}
let suite = "ClipShelf.benchmark.\(UUID())"
let defaults = UserDefaults(suiteName: suite)!
let board = NSPasteboard(name: NSPasteboard.Name(suite))
let path = FileManager.default.temporaryDirectory.appendingPathComponent(suite).appendingPathComponent("history.json")
let store = ClipboardStore(board: board, defaults: defaults, fileURL: path, monitoring: false)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
var random: UInt32 = 0x12345678
for i in 0..<(bitmap.bytesPerRow * bitmap.pixelsHigh) {
    random ^= random << 13; random ^= random >> 17; random ^= random << 5
    bitmap.bitmapData![i] = UInt8(truncatingIfNeeded: random)
}
let fixture = bitmap.representation(using: .png, properties: [:])!
print("stage,items,payload_bytes,resident_bytes,physical_footprint_bytes")
measurement("empty", store)
for i in 1...160 {
    autoreleasepool {
        var data = fixture
        // A legal trailing application marker makes each PNG unique without changing its pixels.
        withUnsafeBytes(of: i) { data.append(contentsOf: $0) }
        board.clearContents()
        precondition(board.setData(data, forType: .png))
        store.capture()
    }
    if [20,80,160].contains(i) { measurement("images_\(i)", store) }
}
store.clear()
measurement("cleared", store)
board.releaseGlobally()
defaults.removePersistentDomain(forName: suite)
try? FileManager.default.removeItem(at: path.deletingLastPathComponent())
