// SPDX-License-Identifier: MIT
// Copyright © 2018-2023 WireGuard LLC. All Rights Reserved.

import Foundation
import os.log

extension FileManager {
    static var appGroupId: String? {
        #if os(iOS)
        let appGroupIdInfoDictionaryKey = "com.wireguard.ios.app_group_id"
        #elseif os(macOS)
        let appGroupIdInfoDictionaryKey = "com.wireguard.macos.app_group_id"
        #else
        #error("Unimplemented")
        #endif
        return Bundle.main.object(forInfoDictionaryKey: appGroupIdInfoDictionaryKey) as? String
    }
    private static var sharedFolderURL: URL? {
        guard let appGroupId = FileManager.appGroupId else {
            os_log("Cannot obtain app group ID from bundle", log: OSLog.default, type: .error)
            return nil
        }
        guard let sharedFolderURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            wg_log(.error, message: "Cannot obtain shared folder URL")
            return nil
        }
        return sharedFolderURL
    }

    static var logFileURL: URL? {
        return sharedFolderURL?.appendingPathComponent("tunnel-log.bin")
    }

    static var networkExtensionLastErrorFileURL: URL? {
        return sharedFolderURL?.appendingPathComponent("last-error.txt")
    }

    static var loginHelperTimestampURL: URL? {
        return sharedFolderURL?.appendingPathComponent("login-helper-timestamp.bin")
    }

    static func deleteFile(at url: URL) -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            return false
        }
        return true
    }

    static func truncateFile(at url: URL) -> Bool {
        do {
            // Check if file exists first to avoid unnecessary overhead
            guard FileManager.default.fileExists(atPath: url.path) else { return true }

            let fileHandle = try FileHandle(forWritingTo: url)
            // This is the equivalent of 'cp /dev/null'
            // It clears the file but preserves the handle for the Go process
            if #available(iOS 13.0, *) {
                try fileHandle.truncate(atOffset: 0)
            } else {
                fileHandle.truncateFile(atOffset: 0)
            }
            fileHandle.closeFile()
            return true
        } catch {
            wg_log(.error, message: "FWDD: Failed to truncate log file: \(error)")
            return false
        }
    }
}
