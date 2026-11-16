import Darwin

/// The names of running processes, read in this process: no `ps` to start, so it is cheap enough to ask every few
/// seconds. CPU and memory are left at zero.
public enum ProcessNames {
    public static func running() -> [ProcessUsage] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        // Room for processes started between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let filled = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard filled > 0 else { return [] }
        var name = [CChar](repeating: 0, count: 64)
        return pids.prefix(Int(filled)).compactMap { pid in
            guard pid > 0, proc_name(pid, &name, UInt32(name.count)) > 0 else { return nil }
            return ProcessUsage(pid: pid, name: String(cString: name), cpu: 0, memory: 0)
        }
    }
}
