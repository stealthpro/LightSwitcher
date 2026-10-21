import AppKit

// `@main` on the delegate never installed it, so the app launched without a delegate and no menu bar item appeared.
// Set the delegate explicitly, and keep a strong reference because NSApplication holds it weakly.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}
