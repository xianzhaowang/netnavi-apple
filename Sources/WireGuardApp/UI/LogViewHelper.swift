// SPDX-License-Identifier: MIT
// Copyright © 2018-2023 WireGuard LLC. All Rights Reserved.

import Foundation

public class LogViewHelper {
    var log: OpaquePointer
    var cursor: UInt32 = UINT32_MAX
    static let formatOptions: ISO8601DateFormatter.Options = [
        .withYear, .withMonth, .withDay, .withTime,
        .withDashSeparatorInDate, .withColonSeparatorInTime, .withSpaceBetweenDateAndTime,
        .withFractionalSeconds
    ]

    struct LogEntry {
        let timestamp: String
        let message: String

        func text() -> String {
            return timestamp + " " + message
        }
    }

    class LogEntries {
        var entries: [LogEntry] = []
    }

    init?(logFilePath: String?) {
        guard let logFilePath = logFilePath else { return nil }
        guard let log = open_log(logFilePath) else { return nil }
        self.log = log
    }

    deinit {
        close_log(self.log)
    }

    func fetchLogEntriesSinceLastFetch(completion: @escaping ([LogViewHelper.LogEntry]) -> Void) {
        var logEntries = LogEntries()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let newCursor = view_lines_from_cursor(self.log, self.cursor, &logEntries) { cStr, timestamp, ctx in
                let message = cStr != nil ? String(cString: cStr!) : ""
                let date = Date(timeIntervalSince1970: Double(timestamp) / 1000000000)
                let dateString = ISO8601DateFormatter.string(from: date, timeZone: TimeZone.current, formatOptions: LogViewHelper.formatOptions)
                if let logEntries = ctx?.bindMemory(to: LogEntries.self, capacity: 1) {
                    logEntries.pointee.entries.append(LogEntry(timestamp: dateString, message: message))
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.cursor = newCursor
                completion(logEntries.entries)
            }
        }
    }

    // TODO: logging only after restart/wgTurnOn
    var isRotating = false
    func clearLog() {
        guard let logFileURL = FileManager.logFileURL else { return }
        let path = logFileURL.path

        // 1. CRITICAL: Block UI to prevent the memcpy crash
        self.isRotating = true
        let logToClose = self.log

        let coordinator = NSFileCoordinator()
        var error: NSError?

        coordinator.coordinate(writingItemAt: logFileURL, options: [], error: &error) { url in
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    // 2. TRUNCATE ONLY: No archive created, history is deleted immediately
                    let fileHandle = try FileHandle(forWritingTo: url)
                    fileHandle.truncateFile(atOffset: 0)
                    try fileHandle.synchronize()
                    fileHandle.closeFile()
                }
            } catch {
                print("FWDD: Truncate failed: \(error)")
            }
        }

        // 3. RE-OPEN & SWAP
        if let newLog = open_log(path) {
            self.log = newLog
            self.cursor = 0

            // 4. Safety delay to let background C-threads finish before unblocking
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                close_log(logToClose)
                self.isRotating = false
            }
        } else {
            self.isRotating = false
        }
    }
}
