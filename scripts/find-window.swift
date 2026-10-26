// Prints the window number of the largest on-screen window owned by a process ID.
// Usage: find-window <pid>
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]) else {
    FileHandle.standardError.write("usage: find-window <pid>\n".data(using: .utf8)!)
    exit(2)
}
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let best = windows
    .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
    .compactMap { info -> (Int, CGFloat)? in
        guard let number = info[kCGWindowNumber as String] as? Int,
              let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) }),
              bounds.width > 50, bounds.height > 30
        else { return nil }
        return (number, bounds.width * bounds.height)
    }
    .max { $0.1 < $1.1 }
guard let best else { exit(1) }
print(best.0)
