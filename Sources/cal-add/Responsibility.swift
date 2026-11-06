import Darwin

/// macOS charges a command-line tool's privacy permissions to the app it runs in
/// (iTerm, Terminal, an IDE), so cal-add would be asking for *that app's* Calendar
/// access, under that app's usage description, and fail if the app has none for full
/// access, as with iTerm. Relaunching ourselves with responsibility disclaimed makes
/// cal-add its own client: the dialog and the System Settings entry say "cal-add" and use
/// the Info.plist embedded in this binary.
///
/// Returns the child's exit status, or nil when no relaunch happened (already the child,
/// or the system call is unavailable), in which case the caller just carries on.
func relaunchAsOwnResponsibleProcess() -> Int32? {
    let marker = "CAL_ADD_RESPONSIBLE"
    guard getenv(marker) == nil else { return nil }

    // Private but long-standing libsystem call; looked up at runtime so a missing symbol
    // degrades to the old behaviour instead of failing to launch.
    typealias SetDisclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
    guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "responsibility_spawnattrs_setdisclaim") else { return nil }
    let setDisclaim = unsafeBitCast(symbol, to: SetDisclaim.self)

    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
    guard proc_pidpath(getpid(), &path, UInt32(path.count)) > 0 else { return nil }

    var attributes: posix_spawnattr_t?
    guard posix_spawnattr_init(&attributes) == 0 else { return nil }
    defer { posix_spawnattr_destroy(&attributes) }
    guard setDisclaim(&attributes, 1) == 0 else { return nil }

    setenv(marker, "1", 1)
    var child: pid_t = 0
    let spawned = posix_spawn(&child, path, nil, &attributes, CommandLine.unsafeArgv, environ)
    guard spawned == 0 else {
        unsetenv(marker)
        return nil
    }

    // The child shares the terminal and gets Ctrl-C itself; just wait for it.
    signal(SIGINT, SIG_IGN)
    var status: Int32 = 0
    while waitpid(child, &status, 0) == -1 && errno == EINTR {}
    let signalNumber = status & 0x7f
    return signalNumber == 0 ? (status >> 8) & 0xff : 128 + signalNumber
}
