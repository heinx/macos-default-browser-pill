import AppKit
import Carbon
import ServiceManagement

enum Browser: String, CaseIterable {
    case chrome, firefox
    var bundleID: String { self == .chrome ? "com.google.Chrome" : "org.mozilla.firefox" }
    var title: String { self == .chrome ? "Google Chrome" : "Firefox" }
}

final class Pill: NSView {
    var selected: Browser = Browser(rawValue: UserDefaults.standard.string(forKey: "browser") ?? "") ?? .chrome
    private var position: CGFloat = UserDefaults.standard.string(forKey: "browser") == "firefox" ? 1 : 0
    private var animation: Timer?
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 68, height: 20), xRadius: 10, yRadius: 10).fill()
        NSColor.labelColor.withAlphaComponent(0.15).setStroke()
        NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 67, height: 19), xRadius: 9.5, yRadius: 9.5).stroke()
        NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: NSRect(x: 2 + position * 34, y: 2, width: 32, height: 18), xRadius: 9, yRadius: 9).fill()
        for (i, browser) in Browser.allCases.enumerated() {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.draw(in: NSRect(x: 6 + i * 34, y: 0, width: 22, height: 22))
            } else {
                let text = browser == .chrome ? "C" : "F"
                (text as NSString).draw(at: NSPoint(x: 12 + i * 34, y: 3), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor])
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        selected = selected == .chrome ? .firefox : .chrome
        UserDefaults.standard.set(selected.rawValue, forKey: "browser")
        animateSelection()
    }
    private func animateSelection() {
        animation?.invalidate()
        let start = position
        let target: CGFloat = selected == .chrome ? 0 : 1
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
        menu.addItem(withTitle: "Install Browser Switcher…", action: #selector(AppDelegate.setDefaultBrowser), keyEquivalent: "")
        let startup = menu.addItem(withTitle: "Start at Login", action: #selector(AppDelegate.toggleStartup), keyEquivalent: "")
        startup.target = NSApp.delegate
        startup.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Browser Pill", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var status: NSStatusItem!
    let pill = Pill(frame: NSRect(x: 0, y: 0, width: 70, height: 22))
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(openURL(_:withReplyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        status = NSStatusBar.system.statusItem(withLength: 70)
        if let button = status.button { button.addSubview(pill) }
    }
    @objc func openURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue, let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        route([url])
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        route(urls.filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") || $0.isFileURL })
    }
    private func route(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let browser = pill.selected
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) else {
            let alert = NSAlert(); alert.messageText = "\(browser.title) is not installed"; alert.informativeText = "Install the browser or select the other one in Browser Pill."; alert.runModal(); return
        }
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error = error { DispatchQueue.main.async { NSApp.presentError(error) } }
        }
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
