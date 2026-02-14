import Foundation

final class GitDiffStatsService {
    private let shell: ShellCommandRunning

    init(shell: ShellCommandRunning = ShellCommandRunner()) {
        self.shell = shell
    }

    func diffStats(for projectPath: String) -> GitDiffStats {
        let result = shell.run(
            executable: "/usr/bin/git",
            arguments: ["-C", projectPath, "diff", "--numstat", "HEAD"],
            currentDirectory: nil,
            environment: [:],
            timeout: 2.5
        )

        if !result.isSuccess {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if stderr.contains("not a git repository") ||
                stderr.contains("bad revision 'HEAD'") ||
                stderr.contains("ambiguous argument 'HEAD'") ||
                stderr.contains("unknown revision or path not in the working tree") {
                return GitDiffStats(additions: 0, deletions: 0)
            }
            return GitDiffStats(additions: 0, deletions: 0)
        }

        var additions = 0
        var deletions = 0

        for line in result.stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 2 else { continue }

            if let added = Int(columns[0]) {
                additions += added
            }
            if let removed = Int(columns[1]) {
                deletions += removed
            }
        }

        return GitDiffStats(additions: additions, deletions: deletions)
    }
}
