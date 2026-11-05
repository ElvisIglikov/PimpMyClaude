import Darwin

/// Кто слушает TCP-порт (#8302, WF41): процессы своего пользователя с сокетом LISTEN на порту (IPv4 и IPv6, любой адрес) —
/// по libproc, как `lsof -iTCP:<порт> -sTCP:LISTEN`. Процессы других пользователей libproc не раскрывает: их слушатель
/// для проверки — «своего нет», и запрос с токеном не идёт. Песочницы своего пользователя видны — их отличает путь.
///
/// Дословно из PimpViewer (`app/Sources/ViewerKit/ViewerChannel.swift`, `PortOwner`, 1.10.20): тот же определитель на
/// обеих сторонах канала К-V8 (WF259).
enum PortOwner {
    struct Holder: Equatable {
        let pid: pid_t
        let path: String
    }

    /// Свои слушатели порта; `pid` — смотреть только этот процесс (быстрый путь), чужой uid — пусто. nil — libproc не
    /// дал список процессов.
    static func listeners(port: UInt16, pid: pid_t? = nil, uid: uid_t = getuid()) -> [Holder]? {
        let pids: [pid_t]
        if let pid = pid {
            guard owner(of: pid) == uid else { return [] }
            pids = [pid]
        } else {
            let size = proc_listpids(UInt32(PROC_UID_ONLY), uid, nil, 0)
            guard size > 0 else { return nil }
            var all = [pid_t](repeating: 0, count: Int(size) / MemoryLayout<pid_t>.stride + 64)
            let got = proc_listpids(UInt32(PROC_UID_ONLY), uid, &all, Int32(all.count * MemoryLayout<pid_t>.stride))
            guard got > 0 else { return nil }
            pids = all.prefix(Int(got) / MemoryLayout<pid_t>.stride).filter { $0 > 0 }
        }
        return pids.filter { listens($0, port: port) }.map { Holder(pid: $0, path: path(of: $0) ?? "") }
    }

    /// Владелец процесса (действующий uid); nil — процесса нет или он закрыт.
    static func owner(of pid: pid_t) -> uid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info.pbi_uid
    }

    static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))  // PROC_PIDPATHINFO_MAXSIZE
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Есть ли у процесса TCP-сокет LISTEN на порту.
    private static func listens(_ pid: pid_t, port: UInt16) -> Bool {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return false }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / stride + 16)
        let used = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * stride))
        guard used > 0 else { return false }
        for fd in fds.prefix(Int(used) / stride) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var info = socket_fdinfo()
            let want = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, want) == want,
                  info.psi.soi_kind == SOCKINFO_TCP else { continue }
            let tcp = info.psi.soi_proto.pri_tcp
            if tcp.tcpsi_state == TSI_S_LISTEN,
               UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport)) == port { return true }
        }
        return false
    }
}
