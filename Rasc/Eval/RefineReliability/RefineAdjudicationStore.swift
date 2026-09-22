import Foundation

enum RefineAdjudicationStore {
    static let adjudicationsV1FileName = "adjudications.v1.jsonl"
    static let adjudicationsV2FileName = "adjudications.v2.jsonl"

    static func adjudicationsV1URL(corpusRoot: URL) -> URL {
        corpusRoot.appendingPathComponent(adjudicationsV1FileName)
    }

    static func adjudicationsV2URL(corpusRoot: URL) -> URL {
        corpusRoot.appendingPathComponent(adjudicationsV2FileName)
    }

    static func loadV1(from corpusRoot: URL) throws -> [RefineAdjudicationRecord] {
        let url = adjudicationsV1URL(corpusRoot: corpusRoot)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        return text
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> RefineAdjudicationRecord? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return try? decoder.decode(RefineAdjudicationRecord.self, from: Data(trimmed.utf8))
            }
    }

    static func loadV2(from corpusRoot: URL) throws -> [RefineAdjudicationRecordV2] {
        let url = adjudicationsV2URL(corpusRoot: corpusRoot)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        return text
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> RefineAdjudicationRecordV2? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return try? decoder.decode(RefineAdjudicationRecordV2.self, from: Data(trimmed.utf8))
            }
    }

    static func load(from corpusRoot: URL) throws -> [RefineAdjudicationRecord] {
        try loadV1(from: corpusRoot)
    }

    static func latestV2ByCaseID(_ records: [RefineAdjudicationRecordV2]) -> [String: RefineAdjudicationRecordV2] {
        var map: [String: RefineAdjudicationRecordV2] = [:]
        for record in records {
            if let existing = map[record.caseID] {
                map[record.caseID] = merge(existing: existing, update: record)
            } else {
                map[record.caseID] = record
            }
        }
        return map
    }

    static func latestMergedV2(
        from corpusRoot: URL,
        hasRefineOutputByCaseID: [String: Bool] = [:]
    ) throws -> [String: RefineAdjudicationRecordV2] {
        var map = latestV2ByCaseID(try loadV2(from: corpusRoot))
        for legacy in latestByCaseID(try loadV1(from: corpusRoot)).values {
            let migrated = migrateV1(legacy)
            if let existing = map[migrated.caseID] {
                map[migrated.caseID] = merge(existing: existing, update: migrated)
            } else {
                map[migrated.caseID] = migrated
            }
        }
        return map
    }

    static func appendV2(_ record: RefineAdjudicationRecordV2, to corpusRoot: URL) throws {
        let url = adjudicationsV2URL(corpusRoot: corpusRoot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        let line = String(decoding: data, as: UTF8.self) + "\n"
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } else {
            try line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func merge(
        existing: RefineAdjudicationRecordV2,
        update: RefineAdjudicationRecordV2
    ) -> RefineAdjudicationRecordV2 {
        RefineAdjudicationRecordV2(
            schemaVersion: 2,
            caseID: update.caseID,
            reviewedAt: max(existing.reviewedAt, update.reviewedAt),
            productJudgment: update.productJudgment ?? existing.productJudgment,
            productFailureLabels: update.productFailureLabels ?? existing.productFailureLabels,
            productNote: update.productNote ?? existing.productNote,
            productReviewedAt: update.productReviewedAt ?? existing.productReviewedAt,
            benchmarkJudgment: update.benchmarkJudgment ?? existing.benchmarkJudgment,
            benchmarkNote: update.benchmarkNote ?? existing.benchmarkNote,
            constraintCorrection: update.constraintCorrection ?? existing.constraintCorrection,
            benchmarkReviewedAt: update.benchmarkReviewedAt ?? existing.benchmarkReviewedAt,
            queueSource: update.queueSource ?? existing.queueSource,
            reviewer: update.reviewer
        )
    }

    static func migrateV1(_ record: RefineAdjudicationRecord) -> RefineAdjudicationRecordV2 {
        let productJudgment: RefineProductJudgment?
        let benchmarkJudgment: RefineBenchmarkJudgment?
        switch record.verdict {
        case .productFailure:
            productJudgment = .productFailure
            benchmarkJudgment = nil
        case .outputAcceptable:
            productJudgment = .outputAcceptable
            benchmarkJudgment = nil
        case .languageAmbiguous:
            productJudgment = .languageAmbiguous
            benchmarkJudgment = nil
        case .benchmarkExpectationWrong:
            productJudgment = nil
            benchmarkJudgment = .benchmarkExpectationWrong
        case .needsConstraintEdit:
            productJudgment = nil
            benchmarkJudgment = .needsConstraintEdit
        case .defer:
            productJudgment = .defer
            benchmarkJudgment = nil
        }

        return RefineAdjudicationRecordV2(
            caseID: record.caseID,
            reviewedAt: record.reviewedAt,
            productJudgment: productJudgment,
            productFailureLabels: record.productFailureLabels,
            productNote: record.note,
            productReviewedAt: productJudgment == nil ? nil : record.reviewedAt,
            benchmarkJudgment: benchmarkJudgment,
            benchmarkNote: record.note,
            constraintCorrection: record.constraintCorrection,
            benchmarkReviewedAt: benchmarkJudgment == nil ? nil : record.reviewedAt,
            queueSource: record.queueSource,
            reviewer: record.reviewer
        )
    }

    static func latestByCaseID(_ records: [RefineAdjudicationRecord]) -> [String: RefineAdjudicationRecord] {
        var map: [String: RefineAdjudicationRecord] = [:]
        for record in records {
            if let existing = map[record.caseID] {
                if record.reviewedAt >= existing.reviewedAt {
                    map[record.caseID] = record
                }
            } else {
                map[record.caseID] = record
            }
        }
        return map
    }

    static func append(_ record: RefineAdjudicationRecord, to corpusRoot: URL) throws {
        let url = adjudicationsV1URL(corpusRoot: corpusRoot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        let line = String(decoding: data, as: UTF8.self) + "\n"
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } else {
            try line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func reviewStatus(
        for caseID: String,
        adjudications: [String: RefineAdjudicationRecord],
        inReviewQueue75: Bool
    ) -> RefineMaintainerReviewStatus {
        guard let record = adjudications[caseID] else {
            return .unreviewed
        }
        switch record.verdict {
        case .outputAcceptable, .productFailure:
            return .approved
        case .benchmarkExpectationWrong, .needsConstraintEdit:
            return .corrected
        case .`defer`, .languageAmbiguous:
            return .deferred
        }
    }

    static func summarizeReviewQueue75(
        reviewQueueCaseIDs: [String],
        adjudications: [String: RefineAdjudicationRecord],
        adjudicationsV2: [String: RefineAdjudicationRecordV2] = [:],
        hasRefineOutputByCaseID: [String: Bool] = [:]
    ) -> RefineReviewQueueStatusSummary {
        var unreviewed = 0
        var approved = 0
        var corrected = 0
        var deferred = 0
        var productReviewed = 0
        var benchmarkReviewed = 0
        var fullyReviewed = 0

        for caseID in reviewQueueCaseIDs {
            if let v2 = adjudicationsV2[caseID] {
                let hasOutput = hasRefineOutputByCaseID[caseID] ?? true
                let status = RefineReviewPayloadBuilder.reviewStatus(
                    hasRefineOutput: hasOutput,
                    adjudication: v2
                )
                if status.fullyReviewed { fullyReviewed += 1 }
                if status.productReviewed || status.productNotApplicable { productReviewed += 1 }
                if status.benchmarkReviewed { benchmarkReviewed += 1 }
                if status.deferred {
                    deferred += 1
                } else if status.fullyReviewed {
                    if v2.benchmarkJudgment == .benchmarkExpectationWrong
                        || v2.benchmarkJudgment == .needsConstraintEdit
                    {
                        corrected += 1
                    } else {
                        approved += 1
                    }
                } else {
                    unreviewed += 1
                }
                continue
            }

            switch reviewStatus(for: caseID, adjudications: adjudications, inReviewQueue75: true) {
            case .unreviewed: unreviewed += 1
            case .approved: approved += 1
            case .corrected: corrected += 1
            case .deferred: deferred += 1
            }
        }

        return RefineReviewQueueStatusSummary(
            totalCases: reviewQueueCaseIDs.count,
            unreviewed: unreviewed,
            approved: approved,
            corrected: corrected,
            deferred: deferred,
            productReviewed: productReviewed,
            benchmarkReviewed: benchmarkReviewed,
            fullyReviewed: fullyReviewed,
            agentGeneratedMaintainerUnapproved: fullyReviewed < reviewQueueCaseIDs.count
        )
    }
}
