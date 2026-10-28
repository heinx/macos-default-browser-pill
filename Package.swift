// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "BrowserPill", platforms: [.macOS(.v13)], products: [.executable(name: "BrowserPill", targets: ["BrowserPill"])], targets: [.executableTarget(name: "BrowserPill", linkerSettings: [.linkedFramework("AppKit")])])
