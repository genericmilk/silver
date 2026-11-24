import Foundation

/// Executes argument arrays directly. Repository paths and branch names never enter a shell.
public enum GitRunner {
    public static func run(_ arguments: [String], at directory: URL? = nil) async throws -> String {
        String(decoding: try await runData(arguments, at: directory), as: UTF8.self)
    }

    public static func runData(_ arguments: [String], at directory: URL? = nil, maximumBytes: Int? = nil) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: outputDirectory) }
            let stdout = outputDirectory.appendingPathComponent("stdout")
            let stderr = outputDirectory.appendingPathComponent("stderr")
            FileManager.default.createFile(atPath: stdout.path, contents: nil)
            FileManager.default.createFile(atPath: stderr.path, contents: nil)
            let outHandle = try FileHandle(forWritingTo: stdout)
            let errHandle = try FileHandle(forWritingTo: stderr)
            defer { try? outHandle.close(); try? errHandle.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["--no-pager", "-c", "core.quotepath=false", "-c", "color.ui=false"] + arguments
            process.currentDirectoryURL = directory
            var environment = ProcessInfo.processInfo.environment
            environment["GIT_TERMINAL_PROMPT"] = "0"
            environment["GIT_EDITOR"] = "/usr/bin/true"
            environment["GIT_PAGER"] = "cat"
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (environment["PATH"] ?? "")
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = outHandle
            process.standardError = errHandle
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(decoding: try Data(contentsOf: stderr), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw GitFailure(message.isEmpty ? "Git exited with status \(process.terminationStatus)." : message)
            }
            if let maximumBytes {
                let size = try stdout.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= maximumBytes else { throw GitFailure("This file exceeds the 128 MB preview limit.") }
            }
            return try Data(contentsOf: stdout)
        }.value
    }
}
