//
//  BackupFiles.swift
//  Dipstick
//

import Foundation

/// How backups are laid out in the backup folder:
///
///     Dipstick Backups/
///       Photos/3f2a….jpg                      shared by every backup
///       2026-10-26/Dipstick backup.json       one folder per day (today's is replaced)
///       2026-10-26/Acura RSX.csv              readable copy per car
///       2026-10-26 14.05 before restore/…     made before a restore replaces data
///
/// Kept: the last 7 days' backups, the newest backup in each of the last 6
/// months, and the last 3 made before a restore. Photos no kept backup uses
/// are removed. Works in iCloud Drive: every read and write is coordinated,
/// so files not downloaded yet are fetched first.
nonisolated enum BackupFiles {
    static let folderName = "Dipstick Backups"
    static let photosFolder = "Photos"
    static let dataFile = "Dipstick backup.json"
    static let beforeRestoreSuffix = " before restore"

    struct Entry: Identifiable, Hashable {
        let name: String
        let url: URL
        var id: String { name }
        /// The day it was made, from the folder name.
        var day: Date? { BackupFiles.dayFormatter.date(from: String(name.prefix(10))) }
        var isBeforeRestore: Bool { name.hasSuffix(BackupFiles.beforeRestoreSuffix) }
        /// When a "before restore" backup was made, from the folder name.
        var madeAt: Date? {
            isBeforeRestore ? BackupFiles.minuteFormatter.date(from: String(name.prefix(16))) : nil
        }
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayFolderName(for date: Date) -> String { dayFormatter.string(from: date) }

    static let minuteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd HH.mm"
        return f
    }()

    static func beforeRestoreFolderName(for date: Date) -> String {
        minuteFormatter.string(from: date) + beforeRestoreSuffix
    }

    // MARK: Writing

    /// Writes one backup into `folder` (inside `root`): photos first, then
    /// the CSVs, then the backup file last, so a backup file is only there
    /// once everything it needs is.
    static func write(_ snapshot: BackupSnapshot, created: Date, csv: [String: String],
                      folder: String, in root: URL) throws {
        let photos = root.appending(path: photosFolder, directoryHint: .isDirectory)
        let target = root.appending(path: folder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        for (name, bytes) in snapshot.photos where !exists(name, in: photos) {
            try coordinatedWrite(bytes, to: photos.appending(path: name))
        }
        // Old CSVs (a renamed or deleted car) go, so the folder matches the backup.
        for old in (try? FileManager.default.contentsOfDirectory(atPath: target.path(percentEncoded: false))) ?? []
        where old.hasSuffix(".csv") && csv[old] == nil {
            try? coordinatedDelete(target.appending(path: old))
        }
        for (name, text) in csv {
            try coordinatedWrite(Data(text.utf8), to: target.appending(path: name))
        }
        let json = try BackupFile.encoder().encode(BackupFile(created: created, data: snapshot.data))
        try coordinatedWrite(json, to: target.appending(path: dataFile))
    }

    // MARK: Listing and reading

    /// Every backup in `root`, newest first.
    static func list(in root: URL) -> [Entry] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))) ?? []
        return names
            .filter { $0 != photosFolder && dayFormatter.date(from: String($0.prefix(10))) != nil }
            .filter { exists(dataFile, in: root.appending(path: $0, directoryHint: .isDirectory)) }
            .sorted(by: >)
            .map { Entry(name: $0, url: root.appending(path: $0, directoryHint: .isDirectory)) }
    }

    /// A backup and the photos it uses (missing photos are left out).
    static func read(_ entry: Entry, in root: URL) throws -> (file: BackupFile, photos: [String: Data]) {
        let file = try BackupFile.decode(coordinatedRead(entry.url.appending(path: dataFile)))
        let folder = root.appending(path: photosFolder, directoryHint: .isDirectory)
        var photos: [String: Data] = [:]
        for name in file.data.photoFiles {
            photos[name] = try? coordinatedRead(folder.appending(path: name))
        }
        return (file, photos)
    }

    // MARK: Keeping and removing

    /// Which backups to keep (by folder name; see the type's note).
    static func namesToKeep(_ names: [String]) -> Set<String> {
        let restores = names.filter { $0.hasSuffix(beforeRestoreSuffix) }.sorted(by: >)
        let days = names.filter { !$0.hasSuffix(beforeRestoreSuffix) && dayFormatter.date(from: $0) != nil }
            .sorted(by: >)
        var keep = Set(days.prefix(7))
        var months: [String] = []
        for day in days where !months.contains(String(day.prefix(7))) {
            months.append(String(day.prefix(7)))
            if months.count > 6 { break }
            keep.insert(day)
        }
        keep.formUnion(restores.prefix(3))
        return keep
    }

    /// Removes old backups, then photos no kept backup uses. If any kept
    /// backup can't be read, photos are left alone.
    static func prune(in root: URL) {
        let entries = list(in: root)
        let keep = namesToKeep(entries.map(\.name))
        for entry in entries where !keep.contains(entry.name) {
            try? coordinatedDelete(entry.url)
        }

        var used = Set<String>()
        for entry in entries where keep.contains(entry.name) {
            guard let json = try? coordinatedRead(entry.url.appending(path: dataFile)),
                  let file = try? BackupFile.decode(json) else { return }
            used.formUnion(file.data.photoFiles)
        }
        let photos = root.appending(path: photosFolder, directoryHint: .isDirectory)
        for name in (try? FileManager.default.contentsOfDirectory(atPath: photos.path(percentEncoded: false))) ?? [] {
            let real = placeholderTarget(name) ?? name
            guard real.hasSuffix(".jpg"), !used.contains(real) else { continue }
            try? coordinatedDelete(photos.appending(path: real))
        }
    }

    // MARK: iCloud uploads

    /// What iCloud says about the newest backup's files (its folder and the
    /// photos): any upload errors, and when the oldest file still waiting
    /// to upload was written.
    struct UploadStatus {
        var errors: [NSError] = []
        var oldestWaiting: Date?
    }

    static func uploadStatus(in root: URL) -> UploadStatus {
        guard let newest = list(in: root).first else { return UploadStatus() }
        let photos = root.appending(path: photosFolder, directoryHint: .isDirectory)
        let files = [(newest.url, (try? FileManager.default.contentsOfDirectory(atPath: newest.url.path(percentEncoded: false))) ?? []),
                     (photos, (try? FileManager.default.contentsOfDirectory(atPath: photos.path(percentEncoded: false))) ?? [])]
            .flatMap { folder, names in names.filter { !$0.hasPrefix(".") }.map { folder.appending(path: $0) } }

        var status = UploadStatus()
        for var url in files {
            url.removeAllCachedResourceValues()
            guard let values = try? url.resourceValues(forKeys: [
                .isUbiquitousItemKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemUploadingErrorKey,
                .contentModificationDateKey,
            ]), values.isUbiquitousItem == true else { continue }
            if let error = values.ubiquitousItemUploadingError { status.errors.append(error) }
            if values.ubiquitousItemIsUploaded == false, let written = values.contentModificationDate {
                status.oldestWaiting = min(status.oldestWaiting ?? written, written)
            }
        }
        return status
    }

    /// What to tell you if backups aren't reaching iCloud, or nil if they
    /// are (or are only just written and still uploading).
    static func uploadProblem(_ status: UploadStatus, now: Date = .now) -> String? {
        if status.errors.contains(where: { $0.code == NSUbiquitousFileNotUploadedDueToQuotaError }) {
            return "Backups aren't reaching iCloud because your iCloud storage is full. Until you free up space or upgrade your iCloud plan, new backups are only on this iPhone."
        }
        if let error = status.errors.first {
            return "Backups aren't reaching iCloud (\(error.localizedDescription)). For now, new backups are only on this iPhone."
        }
        if let waiting = status.oldestWaiting, now.timeIntervalSince(waiting) > 24 * 3600 {
            return "Backups haven't reached iCloud for over a day. Check that iCloud Drive is on and your iPhone is online. Until then, new backups are only on this iPhone."
        }
        return nil
    }

    // MARK: Files

    /// True if the file is there, downloaded or not (iCloud keeps files it
    /// hasn't downloaded as ".name.icloud").
    static func exists(_ name: String, in folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: name).path(percentEncoded: false))
            || FileManager.default.fileExists(atPath: folder.appending(path: ".\(name).icloud").path(percentEncoded: false))
    }

    private static func placeholderTarget(_ name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return nil }
        return String(name.dropFirst().dropLast(".icloud".count))
    }

    static func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { url in
            do { try data.write(to: url, options: .atomic) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    static func coordinatedRead(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
            result = Result { try Data(contentsOf: url) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    static func coordinatedDelete(_ url: URL) throws {
        var coordinationError: NSError?
        var deleteError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { url in
            do { try FileManager.default.removeItem(at: url) } catch { deleteError = error }
        }
        if let error = coordinationError ?? deleteError { throw error }
    }
}
