import Foundation

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#endif

enum TimedProcessSpawner {
    static func spawnInNewProcessGroup(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?,
        workingDirectory: URL?,
        outputPipe: Pipe,
        errorPipe: Pipe
    ) throws -> pid_t {
        #if os(macOS)
        var actions: posix_spawn_file_actions_t? = nil
        try requirePOSIXSuccess(
            posix_spawn_file_actions_init(&actions),
            operation: "posix_spawn_file_actions_init"
        )
        defer { posix_spawn_file_actions_destroy(&actions) }

        var attributes: posix_spawnattr_t? = nil
        try requirePOSIXSuccess(
            posix_spawnattr_init(&attributes),
            operation: "posix_spawnattr_init"
        )
        defer { posix_spawnattr_destroy(&attributes) }

        try configurePipeActions(&actions, outputPipe: outputPipe, errorPipe: errorPipe)
        try configureWorkingDirectory(&actions, workingDirectory: workingDirectory)
        try configureProcessGroup(&attributes)
        return try spawn(
            executablePath: executablePath,
            arguments: arguments,
            environment: environment,
            actions: &actions,
            attributes: &attributes
        )
        #else
        throw TimedProcessLaunchError.unsupportedPlatform
        #endif
    }

    static func waitForProcessExit(processID: pid_t) -> Int32 {
        #if os(macOS)
        var status: Int32 = 0
        while true {
            let result = waitpid(processID, &status, 0)
            if result == processID {
                return exitCode(fromWaitStatus: status)
            }
            if result == -1, errno == EINTR {
                continue
            }
            return -1
        }
        #else
        return -1
        #endif
    }

    @discardableResult
    static func sendSignalToProcessGroup(
        processID: pid_t,
        processGroupID: pid_t,
        signal: Int32
    ) -> Bool {
        #if os(macOS)
        guard processID > 0, processGroupID > 0, processGroupID != getpgrp() else {
            return false
        }
        return kill(-processGroupID, signal) == 0
        #else
        return false
        #endif
    }

    static func isProcessGroupAlive(_ processGroupID: pid_t) -> Bool {
        #if os(macOS)
        guard processGroupID > 0, processGroupID != getpgrp() else {
            return false
        }
        if kill(-processGroupID, 0) == 0 {
            return true
        }
        return errno == EPERM
        #else
        return false
        #endif
    }

    static func processGroupID(for processID: pid_t) -> pid_t? {
        #if os(macOS)
        let processGroupID = getpgid(processID)
        return processGroupID >= 0 ? processGroupID : nil
        #else
        return nil
        #endif
    }

    #if os(macOS)
    private static func configurePipeActions(
        _ actions: inout posix_spawn_file_actions_t?,
        outputPipe: Pipe,
        errorPipe: Pipe
    ) throws {
        let outputReadFD = outputPipe.fileHandleForReading.fileDescriptor
        let outputWriteFD = outputPipe.fileHandleForWriting.fileDescriptor
        let errorReadFD = errorPipe.fileHandleForReading.fileDescriptor
        let errorWriteFD = errorPipe.fileHandleForWriting.fileDescriptor

        try addCloseFileAction(&actions, fileDescriptor: outputReadFD)
        try addCloseFileAction(&actions, fileDescriptor: errorReadFD)
        try addDuplicateFileAction(&actions, from: outputWriteFD, to: STDOUT_FILENO)
        try addDuplicateFileAction(&actions, from: errorWriteFD, to: STDERR_FILENO)
        if outputWriteFD != STDOUT_FILENO {
            try addCloseFileAction(&actions, fileDescriptor: outputWriteFD)
        }
        if errorWriteFD != STDERR_FILENO {
            try addCloseFileAction(&actions, fileDescriptor: errorWriteFD)
        }
    }

    private static func configureWorkingDirectory(
        _ actions: inout posix_spawn_file_actions_t?,
        workingDirectory: URL?
    ) throws {
        guard let workingDirectory else { return }
        let directoryPath = workingDirectory.path(percentEncoded: false)
        try directoryPath.withCString { path in
            try requirePOSIXSuccess(
                posix_spawn_file_actions_addchdir(&actions, path),
                operation: "posix_spawn_file_actions_addchdir"
            )
        }
    }

    private static func configureProcessGroup(_ attributes: inout posix_spawnattr_t?) throws {
        try requirePOSIXSuccess(
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT)),
            operation: "posix_spawnattr_setflags"
        )
    }

    private static func spawn(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?,
        actions: inout posix_spawn_file_actions_t?,
        attributes: inout posix_spawnattr_t?
    ) throws -> pid_t {
        let argv = try TimedProcessCStringArray([executablePath] + arguments)
        let envp = try environment.map { env in
            try TimedProcessCStringArray(env.keys.sorted().map { key in "\(key)=\(env[key] ?? "")" })
        }

        var processID = pid_t()
        let spawnResult = try executablePath.withCString { executablePointer in
            try argv.withUnsafeMutablePointers { argvPointer in
                if let envp {
                    return try envp.withUnsafeMutablePointers { envPointer in
                        posix_spawn(
                            &processID,
                            executablePointer,
                            &actions,
                            &attributes,
                            argvPointer,
                            envPointer
                        )
                    }
                }
                return posix_spawn(
                    &processID,
                    executablePointer,
                    &actions,
                    &attributes,
                    argvPointer,
                    Darwin.environ
                )
            }
        }
        try requirePOSIXSuccess(spawnResult, operation: "posix_spawn")
        return processID
    }

    private static func addDuplicateFileAction(
        _ actions: inout posix_spawn_file_actions_t?,
        from source: Int32,
        to destination: Int32
    ) throws {
        try requirePOSIXSuccess(
            posix_spawn_file_actions_adddup2(&actions, source, destination),
            operation: "posix_spawn_file_actions_adddup2"
        )
    }

    private static func addCloseFileAction(
        _ actions: inout posix_spawn_file_actions_t?,
        fileDescriptor: Int32
    ) throws {
        try requirePOSIXSuccess(
            posix_spawn_file_actions_addclose(&actions, fileDescriptor),
            operation: "posix_spawn_file_actions_addclose"
        )
    }

    private static func requirePOSIXSuccess(_ result: Int32, operation: String) throws {
        guard result == 0 else {
            throw TimedProcessLaunchError.posixFailure(operation: operation, code: result)
        }
    }

    private static func exitCode(fromWaitStatus status: Int32) -> Int32 {
        let terminationSignal = status & 0x7f
        if terminationSignal == 0 {
            return (status >> 8) & 0xff
        }
        return 128 + terminationSignal
    }
    #endif
}
