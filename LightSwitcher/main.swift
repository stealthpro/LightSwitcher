import AppKit

// Set the delegate explicitly. NSApplication holds it weakly, so `delegate` keeps it alive.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}
