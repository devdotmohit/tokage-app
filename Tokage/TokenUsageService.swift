import Foundation

struct TokenTotals: Decodable, Equatable, Hashable {
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

    private enum LegacyCodingKeys: String, CodingKey {
        case cacheReadInputTokens = "cache_read_input_tokens"
    }

    init(
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int,
        reasoningOutputTokens: Int,
        totalTokens: Int
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try? decoder.container(keyedBy: LegacyCodingKeys.self)

        let input = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        let cached = (try container.decodeIfPresent(Int.self, forKey: .cachedInputTokens))
            ?? (legacyContainer.flatMap { try? $0.decodeIfPresent(Int.self, forKey: .cacheReadInputTokens) }) ?? 0
        let output = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        let reasoning = try container.decodeIfPresent(Int.self, forKey: .reasoningOutputTokens) ?? 0
        let total = try container.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0

        self.init(
            inputTokens: input,
            cachedInputTokens: cached,
            outputTokens: output,
            reasoningOutputTokens: reasoning,
            totalTokens: total
        )
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
        inputTokens == 0
            && cachedInputTokens == 0
            && outputTokens == 0
            && reasoningOutputTokens == 0
            && totalTokens == 0
    }

    var billedInputTokens: Int {
        let normalizedInput = max(inputTokens, 0)
        let clampedCached = max(min(cachedInputTokens, normalizedInput), 0)
        return max(normalizedInput - clampedCached, 0)
    }

    var billingTokenTotal: Int {
        // Reasoning tokens are billed on top of output tokens, so we include them separately here.
        billedInputTokens + cachedInputTokens + outputTokens + reasoningOutputTokens
    }

    func normalized() -> TokenTotals {
        let normalizedInput = max(inputTokens, 0)
        let clampedCached = max(min(cachedInputTokens, normalizedInput), 0)
        let normalizedOutput = max(outputTokens, 0)
        let normalizedReasoning = min(max(reasoningOutputTokens, 0), normalizedOutput)
        let fallbackTotal = normalizedInput + normalizedOutput
        let normalizedTotal = totalTokens > 0 ? totalTokens : fallbackTotal

        return TokenTotals(
            inputTokens: normalizedInput,
            cachedInputTokens: clampedCached,
            outputTokens: normalizedOutput,
            reasoningOutputTokens: normalizedReasoning,
            totalTokens: max(normalizedTotal, 0)
        )
    }

    private static func delta(current: Int, previous: Int) -> Int {
        let delta = current - previous
        return delta >= 0 ? delta : 0
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

    private struct EventSignature: Hashable {
        let timestamp: String
        let totals: TokenTotals?

        func hash(into hasher: inout Hasher) {
            hasher.combine(timestamp)
            hasher.combine(totals)
        }
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

        let fileDescriptors = discoverLogFiles(for: key, rootURL: rootURL)
        let logFiles = fileDescriptors.map(\.url)

        if logFiles.isEmpty {
            cachedUsage = nil
            cacheDirty = true
            throw TokenUsageError.missingMonthDirectory
        }

        pruneMissingFiles(presentFiles: logFiles)

        guard let targetDay = targetDay(for: key) else {
            preconditionFailure("Unable to derive target day for components \(key)")
        }

        for descriptor in fileDescriptors {
            let url = descriptor.url
            let previousState = fileStates[url]
            let (updatedState, changed) = processFile(
                at: url,
                previousState: previousState,
                targetDay: targetDay,
                enforceTimestamp: descriptor.enforceTimestamp
            )
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

    private func discoverLogFiles(for key: CacheKey, rootURL: URL) -> [FileDescriptor] {
        let dayComponent = String(format: "%02d", key.day)
        var descriptors: [URL: Bool] = [:]

        if let dayDirectory = dayDirectory(for: key, rootURL: rootURL) {
            let files = jsonlFiles(at: dayDirectory)
            for file in files {
                descriptors[file] = false
            }
        }

        if let monthDirectory = monthDirectory(for: key, rootURL: rootURL) {
            let monthFiles = jsonlFiles(at: monthDirectory)
            for file in monthFiles where descriptors[file] == nil {
                let relativeComponents = file.pathComponents.dropFirst(monthDirectory.pathComponents.count)
                let firstRelativeComponent = relativeComponents.first
                let enforce = firstRelativeComponent != dayComponent
                descriptors[file] = enforce
            }
        }

        if descriptors.isEmpty {
            let fallbackFiles = jsonlFiles(at: rootURL)
            for file in fallbackFiles {
                descriptors[file] = true
            }
        }

        return descriptors
            .map { FileDescriptor(url: $0.key, enforceTimestamp: $0.value) }
            .sorted { $0.url.path < $1.url.path }
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

    private func processFile(at url: URL, previousState: FileState?, targetDay: Date, enforceTimestamp: Bool) -> (FileState, Bool) {
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

            guard let deltaTotals = deltaTotals else {
                continue
            }

            if enforceTimestamp, calendar.isDate(eventDate, inSameDayAs: targetDay) == false {
                continue
            }

            let normalizedDelta = deltaTotals.normalized()
            guard normalizedDelta.isZero == false else {
                continue
            }

            totals = totals.adding(normalizedDelta)
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

    func fetchMonthlyTotals(for date: Date = Date()) throws -> TokenTotals {
        let key = makeCacheKey(for: date)

        let rootURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)

        guard fileManager.fileExists(atPath: rootURL.path) else {
            throw TokenUsageError.missingSessionsDirectory
        }

        guard let monthDirectory = monthDirectory(for: key, rootURL: rootURL) else {
            throw TokenUsageError.missingMonthDirectory
        }

        guard let enumerator = fileManager.enumerator(at: monthDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            throw TokenUsageError.missingMonthDirectory
        }

        var monthTotals: TokenTotals = .zero
        var processedSignatures: Set<EventSignature> = []

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            var previousTotals: TokenTotals?

            guard let data = try? Data(contentsOf: fileURL),
                  let content = String(data: data, encoding: .utf8) else {
                continue
            }

            for line in content.split(separator: "\n") {
                if line.isEmpty {
                    continue
                }

                guard
                    let lineData = line.data(using: .utf8),
                    let event = try? decoder.decode(TokenLogLine.self, from: lineData)
                else {
                    continue
                }

                guard event.type == "event_msg", event.payload?.type == "token_count" else {
                    continue
                }

                guard let timestamp = event.timestamp,
                      let eventDate = isoFormatter.date(from: timestamp),
                      calendar.isDate(eventDate, equalTo: date, toGranularity: .month) else {
                    continue
                }

                let info = event.payload?.info
                let currentTotals = info?.totalTokenUsage
                let lastUsage = info?.lastTokenUsage

                let signature = EventSignature(timestamp: timestamp, totals: currentTotals ?? lastUsage)
                if processedSignatures.contains(signature) {
                    continue
                }
                processedSignatures.insert(signature)

                var delta: TokenTotals?

                if let lastUsage = lastUsage {
                    delta = lastUsage
                } else if let currentTotals = currentTotals {
                    if let previous = previousTotals {
                        delta = currentTotals.delta(since: previous)
                        previousTotals = currentTotals
                    } else {
                        previousTotals = currentTotals
                        continue
                    }
                }

                if let currentTotals = currentTotals {
                    previousTotals = currentTotals
                }

                guard let normalizedDelta = delta?.normalized(), normalizedDelta.isZero == false else {
                    continue
                }

                monthTotals = monthTotals.adding(normalizedDelta)
            }
        }

        return monthTotals
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
    private struct FileDescriptor {
        let url: URL
        let enforceTimestamp: Bool
    }
