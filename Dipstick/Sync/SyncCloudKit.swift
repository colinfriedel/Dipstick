//
//  SyncCloudKit.swift
//  Dipstick
//

import Foundation
import CloudKit

/// `SyncRecord` ⇄ CloudKit record. Each car lives in its own record zone,
/// so a car can be shared on its own (a share covers the whole zone).
/// Photos go as assets; children point to their parent with a reference
/// that deletes them along with it.
nonisolated enum SyncCloudKit {
    static let zonePrefix = "car-"

    /// The zone for a car (by the car's `syncID`).
    static func zoneID(forCar carID: String, owner: String = CKCurrentUserDefaultName) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zonePrefix + carID, ownerName: owner)
    }

    /// The car's `syncID` for a zone, or nil if it isn't a car zone.
    static func carID(for zoneID: CKRecordZone.ID) -> String? {
        zoneID.zoneName.hasPrefix(zonePrefix) ? String(zoneID.zoneName.dropFirst(zonePrefix.count)) : nil
    }

    /// Fields with their own CloudKit keys (not record fields).
    private static let parentKey = "parent"
    private static let parentKindKey = "parentKind"

    static func ckRecord(_ record: SyncRecord, zoneID: CKRecordZone.ID, existing: CKRecord? = nil) throws -> CKRecord {
        let id = CKRecord.ID(recordName: record.id, zoneID: zoneID)
        let ck = existing ?? CKRecord(recordType: record.kind.rawValue, recordID: id)
        // Remove fields that are now empty.
        for key in ck.allKeys() where record.fields[key] == nil && key != parentKey && key != parentKindKey {
            ck[key] = nil
        }
        for (key, value) in record.fields {
            switch value {
            case .string(let v): ck[key] = v as NSString
            case .int(let v): ck[key] = NSNumber(value: Int64(v))
            case .double(let v): ck[key] = NSNumber(value: v)
            case .bool(let v): ck[key] = NSNumber(value: v ? Int64(1) : Int64(0))
            case .date(let v): ck[key] = v as NSDate
            case .data(let v): ck[key] = CKAsset(fileURL: try assetFile(v, name: "\(record.id)-\(key)"))
            }
        }
        if let parentID = record.parentID {
            ck[parentKey] = CKRecord.Reference(recordID: CKRecord.ID(recordName: parentID, zoneID: zoneID),
                                               action: .deleteSelf)
        }
        ck[parentKindKey] = record.parentKind?.rawValue as NSString?
        return ck
    }

    static func syncRecord(_ ck: CKRecord) -> SyncRecord? {
        guard let kind = SyncRecord.Kind(rawValue: ck.recordType) else { return nil }
        var record = SyncRecord(kind: kind, id: ck.recordID.recordName)
        record.parentID = (ck[parentKey] as? CKRecord.Reference)?.recordID.recordName
        record.parentKind = (ck[parentKindKey] as? String).flatMap(SyncRecord.Kind.init(rawValue:))
        for key in ck.allKeys() where key != parentKey && key != parentKindKey {
            switch ck[key] {
            case let v as String: record.fields[key] = .string(v)
            case let v as Date: record.fields[key] = .date(v)
            case let v as CKAsset:
                if let url = v.fileURL, let data = try? Data(contentsOf: url) { record.fields[key] = .data(data) }
            case let v as NSNumber:
                // CloudKit keeps whole numbers and decimals apart.
                let type = String(cString: v.objCType)
                record.fields[key] = (type == "d" || type == "f") ? .double(v.doubleValue) : .int(v.intValue)
            default: break
            }
        }
        // Yes/no fields travel as 0 or 1.
        for key in boolFields[kind] ?? [] {
            if let n = record.int(key) { record.fields[key] = .bool(n != 0) }
        }
        return record
    }

    private static let boolFields: [SyncRecord.Kind: [String]] = [.fuel: ["isFullTank"]]

    /// Assets upload from files; written to a temporary folder.
    private static func assetFile(_ data: Data, name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "sync-assets", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try data.write(to: url, options: .atomic)
        return url
    }
}
