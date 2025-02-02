//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public protocol MessageBackupManager {

    // MARK: - Interact with remotes

    /// Download the encrypted backup for the current user to a local file.
    func downloadEncryptedBackup(localIdentifiers: LocalIdentifiers, auth: ChatServiceAuth) async throws -> URL

    /// Upload the local encrypted backup identified by the given metadata for
    /// the current user.
    func uploadEncryptedBackup(
        metadata: Upload.EncryptedBackupUploadMetadata,
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth
    ) async throws -> Upload.Result<Upload.EncryptedBackupUploadMetadata>

    // MARK: - Export

    /// Export an encrypted backup binary to a local file.
    /// - SeeAlso ``uploadEncryptedBackup(metadata:localIdentifiers:auth:)``
    func exportEncryptedBackup(
        localIdentifiers: LocalIdentifiers,
        backupKey: BackupKey
    ) async throws -> ProgressReportingTask<Upload.EncryptedBackupUploadMetadata, Error>

    /// Export a plaintext backup binary at the returned file URL.
    func exportPlaintextBackup(
        localIdentifiers: LocalIdentifiers
    ) async throws -> ProgressReportingTask<URL, Error>

    // MARK: - Import

    /// Import a backup from the encrypted binary file at the given local URL.
    /// - SeeAlso ``downloadEncryptedBackup(localIdentifiers:auth:)``
    func importEncryptedBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        backupKey: BackupKey
    ) async throws -> ProgressReportingTask<Void, Error>

    /// Import a backup from the plaintext binary file at the given local URL.
    func importPlaintextBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers
    ) async throws -> ProgressReportingTask<Void, Error>

    // MARK: -

    /// Validate the encrypted backup file located at the given local URL.
    func validateEncryptedBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        backupKey: BackupKey
    ) async throws
}
