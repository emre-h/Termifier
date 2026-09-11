//
//  SFTPOperations.swift
//  Termifier
//
//  What the remote file browser needs from a server, as a protocol so
//  `SSHFileBrowserModel` can be driven by a fake in tests.
//

import Foundation

protocol SFTPOperations: Sendable {
    /// The directory the session starts in -- where the browser opens.
    func workingDirectory() async throws -> String
    func list(path: String, includeHidden: Bool) async throws -> [SFTPEntry]
    func makeDirectory(path: String) async throws
    func rename(from: String, to destination: String) async throws
    /// Deletes one entry. A directory is emptied first: `rmdir` fails on a
    /// non-empty directory with nothing more useful than "Failure".
    func delete(_ entry: SFTPEntry) async throws
    func changeMode(octal: String, path: String) async throws
}

enum SFTPError: LocalizedError, Equatable {
    /// `sftp` could not be started at all.
    case unavailable
    /// The server refused the command; carries sftp's own message.
    case failed(String)
    /// `pwd` answered with something unreadable.
    case noWorkingDirectory
    /// A recursive delete's walk hit its safety limit.
    case treeTooLarge(path: String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Could not start /usr/bin/sftp."
        case .failed(let message):
            message
        case .noWorkingDirectory:
            "The server did not report a working directory."
        case .treeTooLarge(let path):
            "\"\(path)\" holds too many items to delete from the browser. "
                + "Delete it from a terminal session instead."
        }
    }
}
