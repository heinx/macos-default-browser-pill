import AppKit
import Carbon
import ServiceManagement

// MARK: - Model

enum Browser: String, CaseIterable {
    case chrome, firefox
    var bundleID: String { self == .chrome ? "com.google.Chrome" : "org.mozilla.firefox" }
    var title: String { self == .chrome ? "Google Chrome" : "Firefox" }
}

struct Profile: Equatable {
    var id: String          // Chrome: profile directory ("Default", "Profile 1"); Firefox: profile name
    var name: String
    var isDefault: Bool
}

struct Slot {
    var browser: Browser
    var profile: Profile?

    var key: String { profile == nil ? browser.rawValue : "\(browser.rawValue)|\(profile!.id)" }
    var label: String { profile?.name ?? browser.title }
}

enum CycleDirection: Int { case forward = 1, backward = -1 }

// MARK: - Profile discovery

enum Profiles {
    private static func home(_ path: String) -> String {
        path.hasPrefix("~") ? NSHomeDirectory() + path.dropFirst() : path
    }

    static func load(browser: Browser) -> [Profile] {
        return browser == .chrome ? loadChrome() : loadFirefox()
    }

    private static func loadChrome() -> [Profile] {
        let path = home("~/Library/Application Support/Google/Chrome/Local State")
        guard let data = FileManager.default.contents(atPath: path),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: [String: Any]] else { return [] }
        let order = (profile["profiles_order"] as? [Any])?.compactMap { $0 as? String } ?? []
        var profiles: [Profile] = []
        for dir in order where cache[dir] != nil {
            profiles.append(chromeProfile(dir: dir, dict: cache[dir]!))
        }
        for dir in cache.keys.sorted() where !order.contains(dir) {
            profiles.append(chromeProfile(dir: dir, dict: cache[dir]!))
        }
        return profiles
    }

    private static func chromeProfile(dir: String, dict: [String: Any]) -> Profile {
        let name = (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Profile(id: dir, name: name.isEmpty ? dir : name, isDefault: dir == "Default")
    }

    private static func loadFirefox() -> [Profile] {
        let path = home("~/Library/Application Support/Firefox/profiles.ini")
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        let installDefaults = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("Default=") && !$0.hasPrefix("Default=1") }
            .map { String($0.dropFirst("Default=".count)) }
        var profiles: [Profile] = []
        var section: [String: String] = [:]
        func flush() {
            defer { section = [:] }
            guard let name = section["Name"] else { return }
            let isDefault = section["Default"] == "1" || installDefaults.contains(section["Path"] ?? "")
            profiles.append(Profile(id: name, name: name, isDefault: isDefault))
        }
        for line in text.components(separatedBy: .newlines) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("[") {
                if !section.isEmpty { flush() }
                continue
            }
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { section[String(parts[0]).trimmingCharacters(in: .whitespaces)] = String(parts[1]) }
        }
        if !section.isEmpty { flush() }
        return profiles
    }
}

// MARK: - Persistence

enum Store {
    static let defaults = UserDefaults.standard

    static func loadSelectedKey() -> String? {
        if let key = defaults.string(forKey: "selection") { return key }
        if let legacy = defaults.string(forKey: "browser") {
            defaults.set(legacy, forKey: "selection")
            defaults.removeObject(forKey: "browser")
            return legacy
        }
        return nil
    }

    static func saveSelected(key: String) {
        defaults.set(key, forKey: "selection")
    }

    static func shownProfileIDs(browser: Browser) -> Set<String> {
        return Set(defaults.stringArray(forKey: "shownProfiles.\(browser.rawValue)") ?? [])
    }

    static func isProfileShown(browser: Browser, id: String) -> Bool {
        return shownProfileIDs(browser: browser).contains(id)
    }

    static func toggleProfileShown(browser: Browser, id: String) {
        var shown = shownProfileIDs(browser: browser)
        if shown.contains(id) { shown.remove(id) } else { shown.insert(id) }
        defaults.set(Array(shown).sorted(), forKey: "shownProfiles.\(browser.rawValue)")
    }

    static func showBrowserSlot(browser: Browser) -> Bool {
        let key = "showBrowser.\(browser.rawValue)"
        return defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
    }

    static func toggleBrowserSlot(browser: Browser) {
        defaults.set(!showBrowserSlot(browser: browser), forKey: "showBrowser.\(browser.rawValue)")
    }

    static func loadSlots() -> [Slot] {
        var slots: [Slot] = []
        for browser in Browser.allCases {
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) != nil else { continue }
            if showBrowserSlot(browser: browser) {
                slots.append(Slot(browser: browser, profile: nil))
            }
            slots.append(contentsOf: Profiles.load(browser: browser)
                .filter { isProfileShown(browser: browser, id: $0.id) }
                .map { Slot(browser: browser, profile: $0) })
        }
        return slots
    }
}

// MARK: - Pill view

final class Pill: NSView {
    var slots: [Slot] = []
    var selectedKey = "" {
        didSet { needsDisplay = true }
    }
    private(set) var selectedIndex = 0
    private(set) var pillWidth: CGFloat = 70
    private var slotFrames: [NSRect] = []
    private var position: CGFloat = 0
    private var animation: Timer?

    var selectedSlot: Slot? { slots.indices.contains(selectedIndex) ? slots[selectedIndex] : nil }

    func reload() {
        animation?.invalidate()
        animation = nil
        slots = Store.loadSlots()
        let key = selectedKey
        let index = slots.firstIndex(where: { $0.key == key }) ?? 0
        selectedIndex = index
        selectedKey = slots.isEmpty ? "" : slots[index].key
        if !slots.isEmpty && selectedKey != key { Store.saveSelected(key: selectedKey) }
        position = CGFloat(selectedIndex)
        layoutSlots()
        toolTip = slots.isEmpty ? "Browser Pill" : slots[selectedIndex].label
        needsDisplay = true
    }

    private func layoutSlots() {
        slotFrames = []
        var x: CGFloat = 4
        for slot in slots {
            let width: CGFloat
            if slot.profile == nil {
                width = 28
            } else {
                let hasBrowserSlot = slots.contains { $0.browser == slot.browser && $0.profile == nil }
                let fromX: CGFloat = hasBrowserSlot ? 3 : 19
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 10)]
                let textWidth = min((slot.label as NSString).size(withAttributes: attrs).width + 2, 76)
                width = fromX - 1 + textWidth + 4
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
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: slot.browser.bundleID) else {
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
            let text = String(slot.browser.title.prefix(1)) as NSString
            let size = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2 + 1), withAttributes: attrs)
            return
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        let hasBrowserSlot = slots.contains { $0.browser == slot.browser && $0.profile == nil }
        if slot.profile == nil {
            draw(icon: icon, in: NSRect(x: r.midX - 11, y: r.midY - 11, width: 22, height: 22), active: active)
        } else if !hasBrowserSlot {
            draw(icon: icon, in: NSRect(x: r.minX + 1, y: r.midY - 8, width: 16, height: 16), active: active)
            drawProfileLabel(slot: slot, in: r, fromX: r.minX + 19, active: active)
        } else {
            drawProfileLabel(slot: slot, in: r, fromX: r.minX + 3, active: active)
        }
    }

    private func drawProfileLabel(slot: Slot, in r: NSRect, fromX: CGFloat, active: Bool) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 10),
            .foregroundColor: active ? NSColor.alternateSelectedControlTextColor : NSColor.secondaryLabelColor
        ]
        let text = slot.label as NSString
        let maxWidth = r.maxX - fromX - 1
        let bounds = text.boundingRect(with: NSSize(width: maxWidth, height: 13),
                                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                       attributes: attrs)
        text.draw(in: NSRect(x: fromX, y: r.midY - bounds.height / 2, width: maxWidth, height: bounds.height),
                  withAttributes: attrs)
    }

    private func draw(icon: NSImage, in r: NSRect, active: Bool) {
        if active {
            icon.draw(in: r)
        } else {
            icon.draw(in: r, from: .zero, operation: .sourceOver, fraction: 0.55)
        }
    }

    private func slotIndex(at point: NSPoint) -> Int? {
        for i in slotFrames.indices {
            if slotFrames[i].insetBy(dx: -1, dy: -3).contains(point) { return i }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let i = slotIndex(at: point) {
            if i == selectedIndex {
                cycle(point.x < slotFrames[i].midX ? .backward : .forward)
            } else {
                select(i)
            }
        } else {
            cycle(.forward)
        }
    }

    private func select(_ index: Int) {
        guard slots.indices.contains(index), index != selectedIndex else { return }
        selectedIndex = index
        selectedKey = slots[index].key
        Store.saveSelected(key: selectedKey)
        toolTip = slots[index].label
        animateSelection()
    }

    private func cycle(_ direction: CycleDirection) {
        guard slots.count > 1 else { return }
        select((selectedIndex + direction.rawValue + slots.count) % slots.count)
    }

    private func animateSelection() {
        animation?.invalidate()
        let start = position
        let target = CGFloat(selectedIndex)
        let began = ProcessInfo.processInfo.systemUptime
        animation = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            let progress = min(1, (ProcessInfo.processInfo.systemUptime - began) / 0.22)
            let eased = 1 - pow(1 - progress, 3)
            self.position = start + (target - start) * eased
            self.needsDisplay = true
            if progress >= 1 { timer.invalidate(); self.animation = nil }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let profilesItem = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "Profiles")
        for browser in Browser.allCases {
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) != nil else { continue }
            let infos = Profiles.load(browser: browser)
            let item = NSMenuItem(title: browser.title, action: nil, keyEquivalent: "")
            let browserSub = NSMenu(title: browser.title)
            for info in infos {
                let slot = Slot(browser: browser, profile: info)
                let toggle = NSMenuItem(title: info.name, action: #selector(AppDelegate.toggleProfileVisibility(_:)), keyEquivalent: "")
                toggle.state = Store.isProfileShown(browser: browser, id: info.id) ? .on : .off
                toggle.representedObject = slot.key
                browserSub.addItem(toggle)
            }
            if infos.isEmpty {
                let none = NSMenuItem(title: "No profiles found", action: nil, keyEquivalent: "")
                none.isEnabled = false
                browserSub.addItem(none)
            }
            browserSub.addItem(.separator())
            let showBrowser = NSMenuItem(title: "Show Browser Icon", action: #selector(AppDelegate.toggleBrowserSlotVisibility(_:)), keyEquivalent: "")
            showBrowser.state = Store.showBrowserSlot(browser: browser) ? .on : .off
            showBrowser.representedObject = browser.rawValue
            browserSub.addItem(showBrowser)
            item.submenu = browserSub
            sub.addItem(item)
        }
        profilesItem.submenu = sub
        menu.addItem(profilesItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Install Browser Switcher…", action: #selector(AppDelegate.setDefaultBrowser), keyEquivalent: "")
        let startup = menu.addItem(withTitle: "Start at Login", action: #selector(AppDelegate.toggleStartup), keyEquivalent: "")
        startup.target = NSApp.delegate
        startup.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Browser Pill", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var status: NSStatusItem!
    let pill = Pill(frame: NSRect(x: 0, y: 0, width: 70, height: 22))

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(openURL(_:withReplyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = status.button {
            pill.selectedKey = Store.loadSelectedKey() ?? ""
            pill.reload()
            button.addSubview(pill)
            status.length = pill.pillWidth
        }
    }

    @objc func openURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue, let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        route([url])
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        route(urls.filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") || $0.isFileURL })
    }

    private func route(_ urls: [URL]) {
        guard !urls.isEmpty, let slot = pill.selectedSlot else { return }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: slot.browser.bundleID) else {
            let alert = NSAlert()
            alert.messageText = "\(slot.browser.title) is not installed"
            alert.informativeText = "Install the browser or select the other one in Browser Pill."
            alert.runModal()
            return
        }
        guard let profile = slot.profile else {
            NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error = error { DispatchQueue.main.async { NSApp.presentError(error) } }
            }
            return
        }
        let profileArgs: [String] = slot.browser == .chrome ? ["--profile-directory=\(profile.id)"] : ["-P", profile.id]
        let binary: String = slot.browser == .chrome ? "Google Chrome" : "Firefox"
        let executableURL = appURL.appendingPathComponent("Contents/MacOS/\(binary)")
        let proc = Process()
        proc.executableURL = executableURL
        proc.arguments = profileArgs + urls.map(\.absoluteString)
        do { try proc.run() } catch { NSApp.presentError(error) }
    }

    private func refreshPill() {
        pill.reload()
        status.length = pill.pillWidth
    }

    @objc func toggleProfileVisibility(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        let parts = key.components(separatedBy: "|")
        guard parts.count == 2, let browser = Browser(rawValue: parts[0]) else { return }
        Store.toggleProfileShown(browser: browser, id: parts[1])
        refreshPill()
    }

    @objc func toggleBrowserSlotVisibility(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let browser = Browser(rawValue: raw) else { return }
        Store.toggleBrowserSlot(browser: browser)
        refreshPill()
    }

    @objc func toggleStartup() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSApp.presentError(error) }
    }

    private func showSetupError(_ error: Error, scheme: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            let details = error as NSError
            alert.messageText = "Could not install browser switcher for \(scheme.uppercased())"
            alert.informativeText = "\(details.localizedDescription)\nIf macOS asked you to confirm, choose Browser Pill in the confirmation dialog.\n\nDetails: \(details.userInfo)\n\nError: \(details.domain) (\(details.code))\nApp: \(Bundle.main.bundleURL.path)"
            alert.runModal()
        }
    }

    @objc func setDefaultBrowser() {
        let appURL = Bundle.main.bundleURL
        let registration = LSRegisterURL(appURL as CFURL, true)
        guard registration == noErr else {
            showSetupError(NSError(domain: NSOSStatusErrorDomain, code: Int(registration)), scheme: "registration")
            return
        }
        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "https") { error in
            if let error = error { self.showSetupError(error, scheme: "https"); return }
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "http") { error in
                if let error = error { self.showSetupError(error, scheme: "http") }
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
