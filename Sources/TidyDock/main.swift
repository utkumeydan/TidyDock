import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu bar only: no Dock icon even when run outside the app bundle.
app.setActivationPolicy(.accessory)
app.run()
