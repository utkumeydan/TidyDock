import Darwin

/// Measures how much memory an app uses, including its helper processes.
///
/// Helpers come in two kinds: child processes (browsers, Electron apps) and
/// XPC services that launchd starts on the app's behalf (Safari's web pages,
/// Mail). macOS tracks the second kind through the "responsible" process,
/// which Activity Monitor uses too. Each process is counted once.
enum MemoryProbe {
    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t

    /// A private libsystem function, looked up at runtime. Without it only
    /// child processes are counted.
    private static let responsiblePID: ResponsibleFn? = dlsym(dlopen(nil, RTLD_NOW), "responsibility_get_pid_responsible_for_pid")
        .map { unsafeBitCast($0, to: ResponsibleFn.self) }

    static func footprint(of pid: pid_t) -> Int64 {
        var processes: Set<pid_t> = []
        var queue = [pid] + services(of: pid)
        while let next = queue.popLast() {
            // Skip processes reached twice (a child can also be a service).
            guard processes.insert(next).inserted else { continue }
            queue.append(contentsOf: children(of: next))
        }
        return processes.reduce(0) { $0 + ownFootprint($1) }
    }

    private static func ownFootprint(_ pid: pid_t) -> Int64 {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? Int64(info.ri_phys_footprint) : 0
    }

    private static func children(of pid: pid_t) -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 256)
        let count = buffer.withUnsafeMutableBytes { raw in
            proc_listchildpids(pid, raw.baseAddress, Int32(raw.count))
        }
        return count > 0 ? Array(buffer.prefix(Int(count))) : []
    }

    /// Processes macOS considers the app responsible for, other than itself.
    private static func services(of pid: pid_t) -> [pid_t] {
        guard let responsiblePID else { return [] }
        var buffer = [pid_t](repeating: 0, count: 8192)
        let count = buffer.withUnsafeMutableBytes { raw in
            proc_listallpids(raw.baseAddress, Int32(raw.count))
        }
        guard count > 0 else { return [] }
        return buffer.prefix(Int(count)).filter { $0 != pid && $0 > 0 && responsiblePID($0) == pid }
    }
}
