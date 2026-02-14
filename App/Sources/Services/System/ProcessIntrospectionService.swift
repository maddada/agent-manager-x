import Foundation

struct ProcessSnapshot: Hashable, Sendable {
    let pid: Int
    let parentPID: Int
    let processGroupID: Int
    let cpuUsage: Double
    let memoryBytes: Int64
    let tty: String
    let state: String
    let elapsed: String
    let commandLine: String

    var executableName: String {
        let first = commandLine
            .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
        return URL(fileURLWithPath: first).lastPathComponent.lowercased()
    }

    func firstArguments(maxCount: Int = 4) -> [String] {
        commandLine
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(maxCount)
            .map(String.init)
    }
}

final class ProcessIntrospectionService {
    private let shell: ShellCommandRunning
    private let processListCacheTTL: TimeInterval = 0.8
    private let processListCacheLock = NSLock()
    private var cachedProcessList: [ProcessSnapshot] = []
    private var cachedProcessListAt: Date = .distantPast

    init(shell: ShellCommandRunning = ShellCommandRunner()) {
        self.shell = shell
    }

    func listProcesses() -> [ProcessSnapshot] {
        let now = Date()
        if let cached = freshProcessListCache(now: now) {
            return cached
        }

        let result = shell.run(
            executable: "/bin/ps",
            arguments: ["-axo", "pid=,ppid=,pgid=,%cpu=,rss=,tty=,state=,etime=,command=", "-ww"],
            currentDirectory: nil,
            environment: [:],
            timeout: 3.0
        )

        guard result.isSuccess else {
            return freshProcessListCache(now: now) ?? []
        }

        let snapshots = result.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap(parsePSLine)

        storeProcessListCache(snapshots, capturedAt: now)
        return snapshots
    }

    func workingDirectory(pid: Int) -> String? {
        let result = shell.run(
            executable: "/usr/sbin/lsof",
            arguments: ["-a", "-p", String(pid), "-d", "cwd", "-Fn"],
            currentDirectory: nil,
            environment: [:],
            timeout: 1.5
        )

        guard result.isSuccess else {
            return nil
        }

        return parseLsofNames(result.stdout).first
    }

    func openFilePaths(pid: Int) -> [String] {
        let result = shell.run(
            executable: "/usr/sbin/lsof",
            arguments: ["-Fn", "-p", String(pid)],
            currentDirectory: nil,
            environment: [:],
            timeout: 1.8
        )

        guard result.isSuccess else {
            return []
        }

        return parseLsofNames(result.stdout)
    }

    func newestOpenFile(
        pid: Int,
        pathContains: String,
        suffix: String,
        excludingFilenamePrefix: String? = nil
    ) -> String? {
        let files = openFilePaths(pid: pid)
            .filter { $0.contains(pathContains) && $0.hasSuffix(suffix) }
            .filter { filePath in
                guard let excludingFilenamePrefix else { return true }
                return !URL(fileURLWithPath: filePath)
                    .lastPathComponent
                    .hasPrefix(excludingFilenamePrefix)
            }

        guard !files.isEmpty else {
            return nil
        }

        return files.max(by: { lhs, rhs in
            let lhsDate = (try? FileManager.default.attributesOfItem(atPath: lhs)[.modificationDate] as? Date) ?? .distantPast
            let rhsDate = (try? FileManager.default.attributesOfItem(atPath: rhs)[.modificationDate] as? Date) ?? .distantPast
            return lhsDate < rhsDate
        })
    }

    func processIsRunning(pid: Int) -> Bool {
        let result = shell.run(
            executable: "/bin/kill",
            arguments: ["-0", String(pid)],
            currentDirectory: nil,
            environment: [:],
            timeout: 1.0
        )
        return result.exitCode == 0
    }

    func descendantPIDs(of rootPID: Int) -> [Int] {
        var descendants: [Int] = []

        let result = shell.run(
            executable: "/usr/bin/pgrep",
            arguments: ["-P", String(rootPID)],
            currentDirectory: nil,
            environment: [:],
            timeout: 1.2
        )

        guard result.exitCode == 0 else {
            return descendants
        }

        for line in result.stdout.split(separator: "\n") {
            guard let child = Int(line.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                continue
            }
            descendants.append(contentsOf: descendantPIDs(of: child))
            descendants.append(child)
        }

        return descendants
    }

    @discardableResult
    func kill(pid: Int, signal: Int32 = 9) -> Bool {
        let result = shell.run(
            executable: "/bin/kill",
            arguments: ["-\(signal)", String(pid)],
            currentDirectory: nil,
            environment: [:],
            timeout: 1.0
        )
        return result.exitCode == 0
    }

    @discardableResult
    func killProcessGroup(groupID: Int, signal: Int32 = 9) -> Bool {
        guard groupID > 0 else {
            return false
        }

        let result = shell.run(
            executable: "/bin/kill",
            arguments: ["-\(signal)", "-\(groupID)"],
            currentDirectory: nil,
            environment: [:],
            timeout: 1.0
        )
        return result.exitCode == 0
    }

    private func parsePSLine(_ line: Substring) -> ProcessSnapshot? {
        let tokens = line.split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
        guard tokens.count >= 9 else {
            return nil
        }

        let commandStart = line.index(line.startIndex, offsetBy: indexAfterEightColumns(line: line))
        let commandLine = String(line[commandStart...]).trimmingCharacters(in: .whitespaces)

        guard
            let pid = Int(tokens[0]),
            let ppid = Int(tokens[1]),
            let pgid = Int(tokens[2]),
            let cpu = Double(tokens[3]),
            let rssKB = Int64(tokens[4])
        else {
            return nil
        }

        return ProcessSnapshot(
            pid: pid,
            parentPID: ppid,
            processGroupID: pgid,
            cpuUsage: cpu,
            memoryBytes: rssKB * 1024,
            tty: String(tokens[5]),
            state: String(tokens[6]),
            elapsed: String(tokens[7]),
            commandLine: commandLine
        )
    }

    private func indexAfterEightColumns(line: Substring) -> Int {
        var index = line.startIndex
        var columns = 0
        var inToken = false

        while index < line.endIndex && columns < 8 {
            let char = line[index]
            let isWhitespace = char.isWhitespace

            if inToken && isWhitespace {
                columns += 1
                inToken = false
            } else if !inToken && !isWhitespace {
                inToken = true
            }

            index = line.index(after: index)
        }

        while index < line.endIndex && line[index].isWhitespace {
            index = line.index(after: index)
        }

        return line.distance(from: line.startIndex, to: index)
    }

    private func parseLsofNames(_ output: String) -> [String] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard let first = line.first, first == "n" else {
                    return nil
                }
                return String(line.dropFirst())
            }
    }

    private func freshProcessListCache(now: Date) -> [ProcessSnapshot]? {
        processListCacheLock.lock()
        defer { processListCacheLock.unlock() }

        guard now.timeIntervalSince(cachedProcessListAt) <= processListCacheTTL else {
            return nil
        }

        return cachedProcessList
    }

    private func storeProcessListCache(_ snapshots: [ProcessSnapshot], capturedAt: Date) {
        processListCacheLock.lock()
        cachedProcessList = snapshots
        cachedProcessListAt = capturedAt
        processListCacheLock.unlock()
    }
}
