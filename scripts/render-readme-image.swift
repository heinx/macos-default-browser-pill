import AppKit

// Render a mock of the pill with synthetic profile names for the README image.

enum Browser: String, CaseIterable {
    case chrome, firefox
    var bundleID: String { self == .chrome ? "com.google.Chrome" : "org.mozilla.firefox" }
    var title: String { self == .chrome ? "Google Chrome" : "Firefox" }
}

struct Profile: Equatable {
    var id: String
    var name: String
    var isDefault: Bool
}

struct Slot {
    var browser: Browser
    var profile: Profile?
    var key: String { profile == nil ? browser.rawValue : "\(browser.rawValue)|\(profile!.id)" }
    var label: String { profile?.name ?? browser.title }
}

final class Pill: NSView {
    var slots: [Slot] = []
    var selectedIndex = 0
    var pillWidth: CGFloat = 70
    var slotFrames: [NSRect] = []
    var position: CGFloat = 0

    override var isFlipped: Bool { true }

    func layoutSlots() {
        slotFrames = []
        var x: CGFloat = 4
        for slot in slots {
            let width: CGFloat
            if slot.profile == nil {
                width = 28
            } else {
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 10)]
                let textWidth = min((slot.label as NSString).size(withAttributes: attrs).width + 2, 76)
                width = 2 + 18 + 3 + textWidth + 4
            }
            slotFrames.append(NSRect(x: x, y: 2, width: width, height: 18))
            x += width + 2
        }
        pillWidth = x - 2 + 4
        frame.size.width = pillWidth
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: pillWidth - 2, height: 20), xRadius: 10, yRadius: 10).fill()
        NSColor.labelColor.withAlphaComponent(0.15).setStroke()
        NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: pillWidth - 3, height: 19), xRadius: 9.5, yRadius: 9.5).stroke()

        NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: highlightRect(), xRadius: 8, yRadius: 8).fill()

        for (i, slot) in slots.enumerated() {
            draw(slot: slot, in: slotFrames[i], active: i == selectedIndex)
        }
    }

    private func highlightRect() -> NSRect {
        guard !slotFrames.isEmpty else { return .zero }
        let i = max(0, min(CGFloat(slots.count - 1), position))
        let lo = Int(floor(i))
        let hi = min(slots.count - 1, lo + 1)
        let t = i - CGFloat(lo)
        let a = slotFrames[lo]
        let b = slotFrames[hi]
        return NSRect(x: a.minX + (b.minX - a.minX) * t, y: 2,
                      width: a.width + (b.width - a.width) * t, height: 18)
    }

    private func draw(slot: Slot, in r: NSRect, active: Bool) {
        let icon = NSWorkspace.shared.icon(forFile: "/Applications/\(slot.browser == .chrome ? "Google Chrome" : "Firefox").app")
        if slot.profile == nil {
            draw(icon: icon, in: NSRect(x: r.midX - 11, y: r.midY - 11, width: 22, height: 22), active: active)
        } else {
            draw(icon: icon, in: NSRect(x: r.minX + 1, y: r.midY - 8, width: 16, height: 16), active: active)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 10),
                .foregroundColor: active ? NSColor.alternateSelectedControlTextColor : NSColor.secondaryLabelColor
            ]
            let text = slot.label as NSString
            let maxWidth = r.maxX - (r.minX + 21) - 1
            let bounds = text.boundingRect(with: NSSize(width: maxWidth, height: 13),
                                           options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                           attributes: attrs)
            text.draw(in: NSRect(x: r.minX + 21, y: r.midY - bounds.height / 2, width: maxWidth, height: bounds.height),
                      withAttributes: attrs)
        }
    }

    private func draw(icon: NSImage, in r: NSRect, active: Bool) {
        if active {
            icon.draw(in: r)
        } else {
            icon.draw(in: r, from: .zero, operation: .sourceOver, fraction: 0.55)
        }
    }
}

let slots = [
    Slot(browser: .chrome, profile: nil),
    Slot(browser: .chrome, profile: Profile(id: "work", name: "Work", isDefault: false)),
    Slot(browser: .chrome, profile: Profile(id: "personal", name: "Personal", isDefault: false)),
    Slot(browser: .firefox, profile: nil),
    Slot(browser: .firefox, profile: Profile(id: "home", name: "Home", isDefault: true))
]

let pill = Pill(frame: NSRect(x: 0, y: 0, width: 300, height: 22))
pill.slots = slots
pill.selectedIndex = 1
pill.position = 1
pill.layoutSlots()

let scale: CGFloat = 4
let width = Int(pill.pillWidth) * Int(scale)
let height = 22 * Int(scale)
let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()
NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
pill.draw(NSRect(x: 0, y: 0, width: pill.pillWidth, height: 22))
image.unlockFocus()

let tiff = image.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("written", width, "x", height)
