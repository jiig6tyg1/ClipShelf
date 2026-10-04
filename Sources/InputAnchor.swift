import AppKit
import ApplicationServices

// Accessibility coordinates use a top-left origin; AppKit uses a bottom-left origin.
enum InputAnchor {
    static func focusedRect() -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(raw, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.15)
        var rangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
           let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() {
            let value = unsafeBitCast(rangeValue, to: AXValue.self)
            var range = CFRange()
            if AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &range) {
                range.location += range.length
                range.length = 0
                if let parameter = AXValueCreate(.cfRange, &range) {
                    var bounds: CFTypeRef?
                    if AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &bounds) == .success,
                       let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() {
                        let value = unsafeBitCast(bounds, to: AXValue.self)
                        var rect = CGRect.zero
                        if AXValueGetType(value) == .cgRect, AXValueGetValue(value, .cgRect, &rect), usable(rect) {
                            return toAppKit(rect)
                        }
                    }
                }
            }
        }
        // Some editors expose a focused input field but no caret bounds.
        var position: CFTypeRef?
        var size: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
           AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
           let position, let size,
           CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
            var point = CGPoint.zero
            var dimensions = CGSize.zero
            let p = unsafeBitCast(position, to: AXValue.self)
            let s = unsafeBitCast(size, to: AXValue.self)
            if AXValueGetType(p) == .cgPoint, AXValueGetType(s) == .cgSize,
               AXValueGetValue(p, .cgPoint, &point), AXValueGetValue(s, .cgSize, &dimensions) {
                let rect = CGRect(origin: point, size: dimensions)
                if usable(rect), rect.height < 160 { return toAppKit(rect) }
            }
        }
        return nil
    }
    static func usable(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite && rect.height > 0 && rect.width >= 0
    }
    static func toAppKit(_ rect: CGRect) -> CGRect {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
    }
    static func origin(anchor: CGRect, panel: CGSize, screen: CGRect) -> CGPoint {
        let margin: CGFloat = 8
        let below = anchor.minY - panel.height - margin
        let y = below >= screen.minY + margin ? below : anchor.maxY + margin
        return CGPoint(x: max(screen.minX + margin, min(anchor.minX, screen.maxX - panel.width - margin)),
                       y: max(screen.minY + margin, min(y, screen.maxY - panel.height - margin)))
    }
}

