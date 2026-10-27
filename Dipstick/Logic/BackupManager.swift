//
//  BackupManager.swift
//  Dipstick
//

import Foundation
import SwiftData
import UIKit

/// Automatic backups. Whenever the app goes to the background with changes,
/// a full backup is written to the folder you picked (e.g. in iCloud Drive),
/// or to the app's own folder (Files › On My iPhone › Dipstick) until you
/// pick one, or if the picked folder can't be reached.
@MainActor @Observable
final class BackupManager {
    static let shared = BackupManager()

    private(set) var lastBackup: Date?
    /// Why the last backup didn't go where it should, if it didn't.
    private(set) var problem: String?
    private(set) var isWorking = false
    /// Set when backups are saved to iCloud Drive but aren't uploading
    /// (iCloud storage full, offline for a day…).
    private(set) var uploadProblem: String?

    /// Backups aren't fully protected, or something went wrong.
    var needsAttention: Bool { place != .iCloud || problem != nil || uploadProblem != nil }
    /// The picked folder's name, or nil when backing up on this iPhone.
    private(set) var folderName: String?
    /// What kind of place backups go to, which decides what they survive.
    private(set) var place: Place = .appFolder

    enum Place {
        /// Dipstick's own folder: deleted along with the app.
        case appFolder
        /// iCloud Drive: survives deleting the app and losing the phone.
        case iCloud
        /// Some other folder (on this iPhone or another app's storage).
        case otherFolder

        /// Whether backups here survive each thing that can go wrong.
        var survivesAppDeleted: Bool { self != .appFolder }
        /// nil = depends on the folder (on the iPhone or in a cloud service).
        var survivesPhoneLost: Bool? {
            switch self {
            case .appFolder: false
            case .iCloud: true
            case .otherFolder: nil
            }
        }
    }

    static func isInICloud(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
            || url.path(percentEncoded: false).contains("/Mobile Documents/")
    }

    private let defaults: UserDefaults
    private enum Key {
        static let bookmark = "backup.folderBookmark"
        static let folderName = "backup.folderName"
        static let lastBackup = "backup.lastDate"
        static let fingerprint = "backup.lastFingerprint"
        static let problem = "backup.problem"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastBackup = defaults.object(forKey: Key.lastBackup) as? Date
        problem = defaults.string(forKey: Key.problem)
        if let bookmark = defaults.data(forKey: Key.bookmark) {
            folderName = defaults.string(forKey: Key.folderName)
            var stale = false
            let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale)
            place = url.map { Self.isInICloud($0) ? .iCloud : .otherFolder } ?? .otherFolder
        }
    }

    // MARK: Where

    /// Where backups go: the picked folder (by bookmark) or this iPhone.
    nonisolated struct Location: Sendable {
        var bookmark: Data?

        static var onPhone: URL {
            URL.documentsDirectory.appending(path: BackupFiles.folderName, directoryHint: .isDirectory)
        }

        enum Failure: LocalizedError {
            case unreachable
            var errorDescription: String? { "Couldn't reach the backup folder." }
        }

        /// Runs `body` with the backup folder, opening the picked folder for
        /// the app while it runs.
        func withRoot<T>(_ body: (URL) throws -> T) throws -> T {
            guard let bookmark else {
                try FileManager.default.createDirectory(at: Self.onPhone, withIntermediateDirectories: true)
                return try body(Self.onPhone)
            }
            var stale = false
            guard let picked = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale),
                  picked.startAccessingSecurityScopedResource() else { throw Failure.unreachable }
            defer { picked.stopAccessingSecurityScopedResource() }
            let root = picked.lastPathComponent == BackupFiles.folderName
                ? picked : picked.appending(path: BackupFiles.folderName, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            return try body(root)
        }
    }

    private var location: Location { Location(bookmark: defaults.data(forKey: Key.bookmark)) }

    /// Back up to a folder picked in Files from now on (and right away).
    func choose(folder url: URL, context: ModelContext) throws {
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: Key.bookmark)
        defaults.set(url.lastPathComponent, forKey: Key.folderName)
        folderName = url.lastPathComponent
        place = Self.isInICloud(url) ? .iCloud : .otherFolder
        forgetFingerprint()
        backUp(context: context, force: true)
    }

    /// Back up on this iPhone instead of the picked folder.
    func useThisPhone(context: ModelContext) {
        defaults.removeObject(forKey: Key.bookmark)
        defaults.removeObject(forKey: Key.folderName)
        folderName = nil
        place = .appFolder
        forgetFingerprint()
        backUp(context: context, force: true)
    }

    private func forgetFingerprint() { defaults.removeObject(forKey: Key.fingerprint) }

    // MARK: Backing up

    /// Writes today's backup if anything changed since the last one (or
    /// always, with `force`). Finishes even if the app is put away.
    func backUp(context: ModelContext, force: Bool = false) {
        context.saveNow()
        let snapshot = BackupSnapshot.make(from: context)
        let fingerprint = snapshot.fingerprint
        guard force || fingerprint != defaults.string(forKey: Key.fingerprint) else { return }
        let csv = BackupSnapshot.csvFiles(from: context)
        let location = location
        let now = Date()

        isWorking = true
        let task = UIApplication.shared.beginBackgroundTask(withName: "Dipstick backup")
        Task.detached(priority: .utility) {
            let result = Self.write(snapshot, csv: csv, created: now, to: location)
            await MainActor.run {
                self.finish(result, fingerprint: fingerprint, at: now)
                UIApplication.shared.endBackgroundTask(task)
            }
        }
    }

    /// Writes to the picked folder, or this iPhone if that fails.
    /// - Returns: nil if it went to the picked folder (or this iPhone, when
    ///   that's the choice); otherwise what went wrong.
    nonisolated private static func write(_ snapshot: BackupSnapshot, csv: [String: String], created: Date,
                                          to location: Location) -> Result<String?, Error> {
        let folder = BackupFiles.dayFolderName(for: created)
        do {
            try location.withRoot { root in
                try BackupFiles.write(snapshot, created: created, csv: csv, folder: folder, in: root)
                BackupFiles.prune(in: root)
            }
            return .success(nil)
        } catch {
            guard location.bookmark != nil else { return .failure(error) }
            // Keep a copy on the phone so today's changes aren't only in the app.
            do {
                try Location(bookmark: nil).withRoot { root in
                    try BackupFiles.write(snapshot, created: created, csv: csv, folder: folder, in: root)
                    BackupFiles.prune(in: root)
                }
                return .success("Couldn't reach the backup folder, so this backup was saved on this iPhone.")
            } catch {
                return .failure(error)
            }
        }
    }

    private func finish(_ result: Result<String?, Error>, fingerprint: String, at date: Date) {
        isWorking = false
        switch result {
        case .success(let note):
            lastBackup = date
            defaults.set(date, forKey: Key.lastBackup)
            // A backup that missed the picked folder is tried there again next time.
            if note == nil { defaults.set(fingerprint, forKey: Key.fingerprint) }
            problem = note
        case .failure(let error):
            problem = "Backup failed: \(error.localizedDescription)"
        }
        defaults.set(problem, forKey: Key.problem)
    }

    /// Checks whether the newest backup has reached iCloud. Run when the
    /// app opens and on the backup screen.
    func checkUploads() async {
        guard place == .iCloud else { uploadProblem = nil; return }
        let location = location
        let status = await Task.detached {
            (try? location.withRoot { BackupFiles.uploadStatus(in: $0) }) ?? BackupFiles.UploadStatus()
        }.value
        uploadProblem = BackupFiles.uploadProblem(status)
    }

    // MARK: Restoring

    struct Loaded: Identifiable {
        let id = UUID()
        let entry: BackupFiles.Entry
        let file: BackupFile
        let photos: [String: Data]
        var missingPhotos: Int { file.data.photoFiles.subtracting(photos.keys).count }
    }

    /// The backups in the current folder, newest first.
    func backups() async -> [BackupFiles.Entry] {
        let location = location
        return await Task.detached {
            (try? location.withRoot { BackupFiles.list(in: $0) }) ?? []
        }.value
    }

    /// Reads a backup (downloading it first if it's in iCloud).
    func load(_ entry: BackupFiles.Entry) async throws -> Loaded {
        let location = location
        let (file, photos) = try await Task.detached {
            try location.withRoot { try BackupFiles.read(entry, in: $0) }
        }.value
        return Loaded(entry: entry, file: file, photos: photos)
    }

    /// Replaces all data with the backup, after saving what's there now as
    /// a "before restore" backup.
    func restore(_ loaded: Loaded, context: ModelContext) async throws {
        isWorking = true
        defer { isWorking = false }
        context.saveNow()
        let current = BackupSnapshot.make(from: context)
        if !current.data.isEmpty {
            let csv = BackupSnapshot.csvFiles(from: context)
            let location = location
            let now = Date()
            try await Task.detached {
                try location.withRoot { root in
                    try BackupFiles.write(current, created: now, csv: csv,
                                          folder: BackupFiles.beforeRestoreFolderName(for: now), in: root)
                }
            }.value
        }
        BackupRestore.apply(loaded.file.data, photos: loaded.photos, into: context)
        forgetFingerprint()
        backUp(context: context)
    }
}
