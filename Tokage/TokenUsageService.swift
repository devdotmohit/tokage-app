import Foundation

struct TokenTotals: Decodable, Equatable {
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let reasoningOutputTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
        case totalTokens = "total_tokens"
    }

    static let zero = TokenTotals(
        inputTokens: 0,
        cachedInputTokens: 0,
        outputTokens: 0,
        reasoningOutputTokens: 0,
        totalTokens: 0
    )

    func delta(since previous: TokenTotals) -> TokenTotals {
        let inputDelta = Self.delta(current: inputTokens, previous: previous.inputTokens)
        let cachedDelta = Self.delta(current: cachedInputTokens, previous: previous.cachedInputTokens)
        let outputDelta = Self.delta(current: outputTokens, previous: previous.outputTokens)
        let reasoningDelta = Self.delta(current: reasoningOutputTokens, previous: previous.reasoningOutputTokens)
        let totalDelta = Self.delta(current: totalTokens, previous: previous.totalTokens)

        return TokenTotals(
            inputTokens: inputDelta,
            cachedInputTokens: cachedDelta,
            outputTokens: outputDelta,
            reasoningOutputTokens: reasoningDelta,
            totalTokens: totalDelta
        )
    }

    func adding(_ other: TokenTotals) -> TokenTotals {
        TokenTotals(
            inputTokens: inputTokens + other.inputTokens,
            cachedInputTokens: cachedInputTokens + other.cachedInputTokens,
            outputTokens: outputTokens + other.outputTokens,
            reasoningOutputTokens: reasoningOutputTokens + other.reasoningOutputTokens,
            totalTokens: totalTokens + other.totalTokens
        )
    }

    var isZero: Bool {
        totalTokens == 0
    }

    private static func delta(current: Int, previous: Int) -> Int {
        let delta = current - previous
        return delta >= 0 ? delta : current
    }
}

struct DailyTokenUsage: Identifiable {
    let id: String
    let date: Date
    let displayDate: String
    let totals: TokenTotals

    init(dayIdentifier: String, date: Date, displayDate: String, totals: TokenTotals) {
        self.id = dayIdentifier
        self.date = date
        self.displayDate = displayDate
        self.totals = totals
    }
}

enum TokenUsageError: LocalizedError {
    case missingSessionsDirectory
    case missingMonthDirectory

    var errorDescription: String? {
        switch self {
        case .missingSessionsDirectory:
            return "Expected to find ~/.codex/sessions but it is missing."
        case .missingMonthDirectory:
            return "No token logs found for today inside ~/.codex/sessions."
        }
    }
}

final class TokenUsageService {
    private struct CacheKey: Equatable {
        let year: Int
        let month: Int
        let day: Int
    }

    private struct FileState {
        var offset: UInt64 = 0
        var leftover: String?
        var totals: TokenTotals = .zero
        var hasTargetDayData: Bool = false
        var fileIdentifier: UInt64?
        var previousTotals: TokenTotals?
        var lastSignature: EventSignature?
    }

    private struct EventSignature: Equatable {
        let timestamp: String
        let totals: TokenTotals?
    }

    private let fileManager: FileManager
    private let calendar: Calendar
    private let decoder = JSONDecoder()
    private let isoFormatter: ISO8601DateFormatter
    private lazy var dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var cacheKey: CacheKey?
    private var fileStates: [URL: FileState] = [:]
    private var cachedUsage: [DailyTokenUsage]?
    private var cacheDirty = true

    init(fileManager: FileManager = .default, calendar: Calendar = .current) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.isoFormatter = ISO8601DateFormatter()
        self.isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func fetchDailyUsage(for date: Date = Date()) throws -> [DailyTokenUsage] {
        let key = makeCacheKey(for: date)

        let rootURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)

        guard fileManager.fileExists(atPath: rootURL.path) else {
            throw TokenUsageError.missingSessionsDirectory
        }

        if cacheKey != key {
            resetCache(for: key)
        }

        let logFiles = discoverLogFiles(for: key, rootURL: rootURL)

        if logFiles.isEmpty {
            cachedUsage = nil
            cacheDirty = true
            throw TokenUsageError.missingMonthDirectory
        }

        pruneMissingFiles(presentFiles: logFiles)

        guard let targetDay = targetDay(for: key) else {
            preconditionFailure("Unable to derive target day for components \(key)")
        }

        for url in logFiles {
            let previousState = fileStates[url]
            let (updatedState, changed) = processFile(at: url, previousState: previousState, targetDay: targetDay)
            fileStates[url] = updatedState
            if changed {
                cacheDirty = true
            }
        }

        if let cachedUsage, cacheDirty == false {
            return cachedUsage
        }

        let usage = try buildUsage(for: targetDay)
        cachedUsage = usage
        cacheDirty = false
        return usage
    }

    private func makeCacheKey(for date: Date) -> CacheKey {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            preconditionFailure("Unable to derive date components for \(date)")
        }
        return CacheKey(year: year, month: month, day: day)
    }

    private func resetCache(for key: CacheKey) {
        cacheKey = key
        fileStates.removeAll()
        cachedUsage = nil
        cacheDirty = true
    }

    private func discoverLogFiles(for key: CacheKey, rootURL: URL) -> [URL] {
        var files: [URL] = []

        if let dayDirectory = dayDirectory(for: key, rootURL: rootURL) {
            files = jsonlFiles(at: dayDirectory)
            if files.isEmpty == false {
                return files.sorted { $0.path < $1.path }
            }
        }

        if let monthDirectory = monthDirectory(for: key, rootURL: rootURL) {
            files = jsonlFiles(at: monthDirectory)
            if files.isEmpty == false {
                return files.sorted { $0.path < $1.path }
            }
        }

        if let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
                files.append(fileURL)
            }
        }

        return files.sorted { $0.path < $1.path }
    }

    private func dayDirectory(for key: CacheKey, rootURL: URL) -> URL? {
        let yearURL = rootURL.appendingPathComponent(String(key.year), isDirectory: true)
        let monthURL = yearURL.appendingPathComponent(String(format: "%02d", key.month), isDirectory: true)
        let dayURL = monthURL.appendingPathComponent(String(format: "%02d", key.day), isDirectory: true)
        return fileManager.fileExists(atPath: dayURL.path) ? dayURL : nil
    }

    private func monthDirectory(for key: CacheKey, rootURL: URL) -> URL? {
        let yearURL = rootURL.appendingPathComponent(String(key.year), isDirectory: true)
        let monthURL = yearURL.appendingPathComponent(String(format: "%02d", key.month), isDirectory: true)
        return fileManager.fileExists(atPath: monthURL.path) ? monthURL : nil
    }

    private func jsonlFiles(at directory: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }

        var results: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            results.append(fileURL)
        }
        return results
    }

    private func pruneMissingFiles(presentFiles: [URL]) {
        let presentSet = Set(presentFiles)
        let removed = fileStates.keys.filter { presentSet.contains($0) == false }

        if removed.isEmpty == false {
            removed.forEach { fileStates.removeValue(forKey: $0) }
            cacheDirty = true
        }
    }

    private func targetDay(for key: CacheKey) -> Date? {
        calendar.date(from: DateComponents(year: key.year, month: key.month, day: key.day))
    }

    private func processFile(at url: URL, previousState: FileState?, targetDay: Date) -> (FileState, Bool) {
        var state = previousState ?? FileState()
        var changed = false

        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        let identifier = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value

        if state.fileIdentifier != identifier || fileSize < state.offset {
            state = FileState()
            state.fileIdentifier = identifier
            changed = true
        } else {
            state.fileIdentifier = identifier
        }

        if fileSize == state.offset, state.leftover == nil {
            return (state, changed)
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return (state, changed)
        }

        defer {
            try? handle.close()
        }

        if state.offset > 0 {
            try? handle.seek(toOffset: state.offset)
        }

        guard let data = try? handle.readToEnd() else {
            return (state, changed)
        }

        state.offset = fileSize

        if data.isEmpty, changed == false {
            return (state, false)
        }

        var buffer = state.leftover ?? ""
        if let chunk = String(data: data, encoding: .utf8) {
            buffer.append(chunk)
        } else {
            state.leftover = nil
            return (state, changed)
        }

        state.leftover = nil

        var lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
        if buffer.last?.isNewline == false, let trailing = lines.popLast() {
            state.leftover = String(trailing)
        }

        if lines.isEmpty {
            return (state, changed)
        }

        var totals = state.totals
        var hasUsage = state.hasTargetDayData
        var previousTotals = state.previousTotals

        for line in lines {
            if line.isEmpty {
                continue
            }

            let lineString = String(line)
            guard let lineData = lineString.data(using: .utf8),
                  let event = try? decoder.decode(TokenLogLine.self, from: lineData) else {
                continue
            }

            guard event.type == "event_msg" else { continue }
            guard event.payload?.type == "token_count" else { continue }
            let info = event.payload?.info
            let currentTotals = info?.totalTokenUsage
            let lastUsage = info?.lastTokenUsage
            guard let timestamp = event.timestamp else { continue }
            guard let eventDate = isoFormatter.date(from: timestamp) else { continue }

            let signature = EventSignature(timestamp: timestamp, totals: currentTotals ?? lastUsage)
            if let lastSignature = state.lastSignature, lastSignature == signature {
                continue
            }
            state.lastSignature = signature

            var deltaTotals: TokenTotals?

            if let lastUsage = lastUsage {
                deltaTotals = lastUsage
            } else if let currentTotals = currentTotals {
                if let previous = previousTotals {
                    let rawDelta = currentTotals.delta(since: previous)
                    deltaTotals = rawDelta
                } else {
                    previousTotals = currentTotals
                    continue
                }
            } else {
                continue
            }

            if let currentTotals = currentTotals {
                previousTotals = currentTotals
            }

            guard let deltaTotals = deltaTotals, deltaTotals.isZero == false else {
                continue
            }

            guard calendar.isDate(eventDate, inSameDayAs: targetDay) else {
                continue
            }

            let freshInput = max(deltaTotals.inputTokens - deltaTotals.cachedInputTokens, 0)
            let billedTotal = freshInput
                + deltaTotals.cachedInputTokens
                + deltaTotals.outputTokens
                + deltaTotals.reasoningOutputTokens
            let adjustedDelta = TokenTotals(
                inputTokens: freshInput,
                cachedInputTokens: deltaTotals.cachedInputTokens,
                outputTokens: deltaTotals.outputTokens,
                reasoningOutputTokens: deltaTotals.reasoningOutputTokens,
                totalTokens: billedTotal
            )

            totals = totals.adding(adjustedDelta)
            hasUsage = true
            changed = true
        }

        state.totals = totals
        state.hasTargetDayData = hasUsage
        state.previousTotals = previousTotals

        return (state, changed)
    }

    private func buildUsage(for targetDay: Date) throws -> [DailyTokenUsage] {
        var totals: TokenTotals = .zero
        var sawUsage = false

        for state in fileStates.values {
            totals = totals.adding(state.totals)
            sawUsage = sawUsage || state.hasTargetDayData
        }

        guard sawUsage else {
            throw TokenUsageError.missingMonthDirectory
        }

        let displayDate = dayFormatter.string(from: targetDay)
        let usage = DailyTokenUsage(
            dayIdentifier: displayDate,
            date: targetDay,
            displayDate: displayDate,
            totals: totals
        )

        return [usage]
    }
}

private struct TokenLogLine: Decodable {
    let type: String
    let timestamp: String?
    let payload: Payload?

    struct Payload: Decodable {
        let type: String
        let info: Info?

        enum CodingKeys: String, CodingKey {
            case type
            case info
        }

        struct Info: Decodable {
            let totalTokenUsage: TokenTotals?
            let lastTokenUsage: TokenTotals?

            enum CodingKeys: String, CodingKey {
                case totalTokenUsage = "total_token_usage"
                case lastTokenUsage = "last_token_usage"
            }
        }
    }
}
