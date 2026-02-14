import Foundation
import Darwin

struct ShellCommandResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let didTimeout: Bool

    var isSuccess: Bool {
        exitCode == 0 && !didTimeout
    }
}

protocol ShellCommandRunning: Sendable {
    @discardableResult
    func run(
        executable: String,
        arguments: [String],
        currentDirectory: String?,
        environment: [String: String],
        timeout: TimeInterval
    ) -> ShellCommandResult

    @discardableResult
    func runShell(
        command: String,
        currentDirectory: String?,
        environment: [String: String],
        timeout: TimeInterval
    ) -> ShellCommandResult
}

final class ShellCommandRunner: ShellCommandRunning {
    @discardableResult
    func run(
        executable: String,
        arguments: [String] = [],
        currentDirectory: String? = nil,
        environment: [String: String] = [:],
        timeout: TimeInterval = 3.0
    ) -> ShellCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }

        var mergedEnvironment = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            mergedEnvironment[key] = value
        }
        process.environment = mergedEnvironment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var stdoutData = Data()
        var stderrData = Data()
        let dataLock = NSLock()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }

            dataLock.lock()
            stdoutData.append(chunk)
            dataLock.unlock()
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }

            dataLock.lock()
            stderrData.append(chunk)
            dataLock.unlock()
        }

        do {
            try process.run()
        } catch {
            return ShellCommandResult(
                exitCode: 1,
                stdout: "",
                stderr: "Failed to run \(executable): \(error)",
                didTimeout: false
            )
        }

        let timeoutSeconds = max(0.1, timeout)
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var didTimeout = false

        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }

        if process.isRunning {
            didTimeout = true
            process.terminate()
            Thread.sleep(forTimeInterval: 0.05)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        process.waitUntilExit()
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        // Drain any remaining buffered bytes after the process exits.
        let trailingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let trailingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        dataLock.lock()
        stdoutData.append(trailingStdout)
        stderrData.append(trailingStderr)
        dataLock.unlock()

        return ShellCommandResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self),
            didTimeout: didTimeout
        )
    }

    @discardableResult
    func runShell(
        command: String,
        currentDirectory: String? = nil,
        environment: [String: String] = [:],
        timeout: TimeInterval = 3.0
    ) -> ShellCommandResult {
        run(
            executable: "/bin/zsh",
            arguments: ["-lc", command],
            currentDirectory: currentDirectory,
            environment: environment,
            timeout: timeout
        )
    }
}
