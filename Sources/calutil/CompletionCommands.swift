import CalUtilCore
import EventKit
import Foundation

/// `calutil completion install` and the suggestions behind Tab, as cobrakit's completion
/// package does it for the Go tools: the script goes into a directory the shell reads, and
/// calutil says whether it does, rather than leaving a file where nothing loads it.
enum CompletionCommands {
    // MARK: - Suggestions

    static let source = Completion.Source(
        templates: { path in
            let file = path.map { ($0 as NSString).expandingTildeInPath } ?? TemplateStore.defaultPath()
            return ((try? TemplateStore.load(from: file)) ?? [:]).keys.map { $0 }
        },
        calendars: {
            // Only when access was already given: pressing Tab must never bring up a dialog.
            guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
            let calendars = EKEventStore().calendars(for: .event)
            var seen: Set<String> = []
            var candidates: [Completion.Candidate] = []
            for calendar in calendars.sorted(by: { $0.title < $1.title }) {
                let full = EventKitBackend.qualifiedName(calendar)
                let shared = calendars.filter { $0.title == calendar.title }.count > 1
                // A name two calendars share is offered as Account/Name too.
                if seen.insert(calendar.title).inserted {
                    candidates.append(.init(calendar.title, shared ? "several calendars" : full))
                }
                if shared, seen.insert(full).inserted { candidates.append(.init(full)) }
            }
            return candidates
        })

    static func complete(_ words: [String]) {
        print(Completion.render(Completion.reply(for: words, source: source)))
    }

    // MARK: - Installing

    struct Target {
        var dir: String
        var file: String
        var active: Bool
        /// What to do for an inactive directory to be read.
        var hint = ""
    }

    static func install(shell: String, dir: String?, dryRun: Bool) throws {
        let shells: [String]
        switch shell {
        case "auto":
            switch (ProcessInfo.processInfo.environment["SHELL"] as NSString?)?.lastPathComponent {
            case "zsh": shells = ["zsh"]
            case "bash": shells = ["bash"]
            // Unset or something else: both, rather than guess. A file a shell ignores is
            // harmless; installing for the wrong one and reporting success is not.
            default: shells = ["zsh", "bash"]
            }
        case "all": shells = ["zsh", "bash"]
        default: shells = [shell]
        }
        if dir != nil && shells.count != 1 {
            throw CalUtilError("--dir names one directory, so it needs one --shell (\(shell) is \(shells.count) shells)", usage: true)
        }

        for shell in shells {
            let target = try self.target(for: shell, dir: dir)
            let path = (target.dir as NSString).appendingPathComponent(target.file)
            if dryRun {
                print("\(shell): would write \(path)")
            } else {
                do {
                    try FileManager.default.createDirectory(atPath: target.dir, withIntermediateDirectories: true)
                    try Data(Completion.script(for: shell)!.utf8).write(to: URL(fileURLWithPath: path))
                } catch {
                    throw CalUtilError("couldn't write \(path): \(error.localizedDescription)")
                }
                print("\(shell): wrote \(path)")
            }
            if target.active {
                print("     active -- open a new shell to pick it up")
                if shell == "zsh" {
                    // zsh works from a cached index of completions (oh-my-zsh refreshes it
                    // once a day), so a correctly installed script can still not appear.
                    print("     if it does not appear, zsh has cached its completion index:\n       rm -f ~/.zcompdump* && exec zsh")
                }
            } else {
                print("     NOT yet active. \(target.hint)")
            }
        }
    }

    static func target(for shell: String, dir: String?) throws -> Target {
        let home = NSHomeDirectory()
        let file = Completion.fileName(for: shell)
        switch shell {
        case "zsh":
            var target: Target
            if let dir {
                target = Target(dir: dir, file: file, active: zshSearches(dir))
            } else if let found = writableZshFpathDir() {
                // Already on fpath and writable: works with no change to any startup file.
                target = Target(dir: found, file: file, active: true)
            } else {
                let fallback = (home as NSString).appendingPathComponent(".local/share/zsh/site-functions")
                target = Target(dir: fallback, file: file, active: zshSearches(fallback))
            }
            if !target.active {
                target.hint = "add this to ~/.zshrc ABOVE the line that runs compinit, then open a new shell:\n       fpath=(\(target.dir) $fpath)"
            }
            return target
        case "bash":
            let environment = ProcessInfo.processInfo.environment
            let directory = dir
                ?? environment["BASH_COMPLETION_USER_DIR"].flatMap { $0.isEmpty ? nil : ($0 as NSString).appendingPathComponent("completions") }
                ?? (home as NSString).appendingPathComponent(".local/share/bash-completion/completions")
            // bash-completion 2 reads its user directory by itself; without it nothing loads the file.
            var target = Target(dir: directory, file: file, active: bashCompletionInstalled())
            if !target.active {
                target.hint = "bash-completion does not appear to be installed, and bash loads these files through it.\n       On macOS: brew install bash-completion@2, then follow the caveats it prints."
            }
            return target
        default:
            throw CalUtilError("unknown shell '\(shell)'; use zsh, bash, all or auto", usage: true)
        }
    }

    /// The fpath zsh really uses, asked of zsh itself: startup files and frameworks such as
    /// oh-my-zsh assemble it, so it can't be known from outside.
    static func zshFpath() -> [String]? {
        guard let zsh = ["/bin/zsh", "/opt/homebrew/bin/zsh", "/usr/local/bin/zsh"]
            .first(where: FileManager.default.isExecutableFile(atPath:)) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: zsh)
        process.arguments = ["-i", "-c", "print -l $fpath"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let dirs = String(decoding: data, as: UTF8.self).split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return dirs.isEmpty ? nil : dirs
    }

    static func zshSearches(_ dir: String) -> Bool {
        let wanted = (dir as NSString).standardizingPath
        return zshFpath()?.contains { ($0 as NSString).standardizingPath == wanted } ?? false
    }

    /// The best writable directory already on zsh's fpath (see `CompletionInstall.score`).
    static func writableZshFpathDir() -> String? {
        var best: (dir: String, score: Int)?
        for dir in zshFpath() ?? [] {
            let score = CompletionInstall.score(dir, home: NSHomeDirectory())
            if score > (best?.score ?? 0), isWritable(dir) { best = (dir, score) }
        }
        return best?.dir
    }

    static func isWritable(_ dir: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        return FileManager.default.isWritableFile(atPath: dir)
    }

    static func bashCompletionInstalled() -> Bool {
        ["/opt/homebrew/etc/profile.d/bash_completion.sh", "/usr/local/etc/profile.d/bash_completion.sh",
         "/usr/share/bash-completion/bash_completion", "/etc/bash_completion"]
            .contains(where: FileManager.default.fileExists(atPath:))
    }
}
