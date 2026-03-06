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

struct CostTotals: Equatable, Hashable {
    let inputCost: Double
    let cachedInputCost: Double
    let outputCost: Double
    let reasoningCost: Double

    init(inputCost: Double, cachedInputCost: Double, outputCost: Double, reasoningCost: Double) {
        self.inputCost = inputCost
        self.cachedInputCost = cachedInputCost
        self.outputCost = outputCost
        self.reasoningCost = reasoningCost
    }

    init(totals: TokenTotals, rates: ModelRates) {
        self.init(
            inputCost: CostTotals.cost(tokens: totals.billedInputTokens, rate: rates.input),
            cachedInputCost: CostTotals.cost(tokens: totals.cachedInputTokens, rate: rates.cachedInputRate),
            outputCost: CostTotals.cost(tokens: totals.outputTokens, rate: rates.output),
            reasoningCost: CostTotals.cost(tokens: totals.reasoningOutputTokens, rate: rates.output)
        )
    }

    static let zero = CostTotals(inputCost: 0, cachedInputCost: 0, outputCost: 0, reasoningCost: 0)

    var totalCost: Double {
        inputCost + cachedInputCost + outputCost + reasoningCost
    }

    var isZero: Bool {
        totalCost == 0
    }

    func adding(_ other: CostTotals) -> CostTotals {
        CostTotals(
            inputCost: inputCost + other.inputCost,
            cachedInputCost: cachedInputCost + other.cachedInputCost,
            outputCost: outputCost + other.outputCost,
            reasoningCost: reasoningCost + other.reasoningCost
        )
    }

    private static func cost(tokens: Int, rate: Double) -> Double {
        (Double(tokens) * rate) / 1_000_000
    }
}

struct UsageAggregate: Equatable, Hashable {
    let totals: TokenTotals
    let costs: CostTotals

    static let zero = UsageAggregate(totals: .zero, costs: .zero)

    var isZero: Bool {
        totals.isZero && costs.isZero
    }

    var billingTokenTotal: Int {
        totals.billingTokenTotal
    }

    func adding(_ other: UsageAggregate) -> UsageAggregate {
        UsageAggregate(
            totals: totals.adding(other.totals),
            costs: costs.adding(other.costs)
        )
    }
}

struct DailyTokenUsage: Identifiable {
    let id: String
    let date: Date
    let displayDate: String
    let aggregate: UsageAggregate

    init(dayIdentifier: String, date: Date, displayDate: String, aggregate: UsageAggregate) {
        self.id = dayIdentifier
        self.date = date
        self.displayDate = displayDate
        self.aggregate = aggregate
    }

    var totals: TokenTotals {
        aggregate.totals
    }

    var costs: CostTotals {
        aggregate.costs
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
        var aggregate: UsageAggregate = .zero
        var hasTargetDayData: Bool = false
        var fileIdentifier: UInt64?
        var previousTotals: TokenTotals?
        var lastUsageSignature: UsageSignature?
        var lastModel: String?
        var replayState = SessionReplayState()
    }

    private struct UsageSignature: Hashable {
        let totalTokenUsage: TokenTotals?
        let lastTokenUsage: TokenTotals?
    }

    private struct SessionReplayState {
        var currentSessionID: String?
        var forkedFromSessionID: String?
        var sawInheritedParentSession = false
        var inheritedTurnID: String?
        var ownTurnStarted = false

        var isForkedSession: Bool {
            guard let forkedFromSessionID else {
                return false
            }

            return forkedFromSessionID.isEmpty == false
        }

        var shouldSkipTokenCounts: Bool {
            sawInheritedParentSession && ownTurnStarted == false
        }

        mutating func consume(_ event: TokenLogLine) {
            switch event.type {
            case "session_meta":
                guard let sessionID = event.payload?.sessionID, sessionID.isEmpty == false else {
                    return
                }

                if currentSessionID == nil {
                    currentSessionID = sessionID
                    if let forkedFromSessionID = event.payload?.forkedFromSessionID,
                       forkedFromSessionID.isEmpty == false {
                        self.forkedFromSessionID = forkedFromSessionID
                    }
                    return
                }

                if let forkedFromSessionID, sessionID == forkedFromSessionID {
                    sawInheritedParentSession = true
                }

            case "turn_context":
                guard shouldSkipTokenCounts,
                      let turnID = event.payload?.turnID,
                      turnID.isEmpty == false else {
                    return
                }

                if let inheritedTurnID {
                    if inheritedTurnID != turnID {
                        ownTurnStarted = true
                    }
                } else {
                    inheritedTurnID = turnID
                }

            default:
                return
            }
        }
    }

    private struct FileDescriptor {
        let url: URL
        let enforceTimestamp: Bool
    }

    private let fileManager: FileManager
    private let calendar: Calendar
    private let sessionsRootURL: URL?
    private let pricingCatalog: ModelPricingCatalog
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

    init(
        fileManager: FileManager = .default,
        calendar: Calendar = .current,
        sessionsRootURL: URL? = nil,
        pricingCatalog: ModelPricingCatalog = ModelPricingCatalog.load()
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.sessionsRootURL = sessionsRootURL
        self.pricingCatalog = pricingCatalog
        self.isoFormatter = ISO8601DateFormatter()
        self.isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func fetchDailyUsage(for date: Date = Date()) throws -> [DailyTokenUsage] {
        let key = makeCacheKey(for: date)
        let rootURL = resolvedRootURL()

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

    func fetchMonthlyTotals(for date: Date = Date()) throws -> UsageAggregate {
        let key = makeCacheKey(for: date)
        let rootURL = resolvedRootURL()

        guard fileManager.fileExists(atPath: rootURL.path) else {
            throw TokenUsageError.missingSessionsDirectory
        }

        guard let monthDirectory = monthDirectory(for: key, rootURL: rootURL) else {
            throw TokenUsageError.missingMonthDirectory
        }

        guard let enumerator = fileManager.enumerator(at: monthDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            throw TokenUsageError.missingMonthDirectory
        }

        var monthAggregate: UsageAggregate = .zero

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            var previousTotals: TokenTotals?
            var lastUsageSignature: UsageSignature?
            var lastModel: String?
            var replayState = SessionReplayState()

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

                replayState.consume(event)

                if event.type == "turn_context" {
                    lastModel = resolvedModel(from: event.payload?.model, fallback: lastModel)
                    continue
                }

                guard event.type == "event_msg", event.payload?.type == "token_count" else {
                    continue
                }

                if replayState.isForkedSession {
                    continue
                }

                if replayState.shouldSkipTokenCounts {
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
                let signature = UsageSignature(totalTokenUsage: currentTotals, lastTokenUsage: lastUsage)

                if let priorSignature = lastUsageSignature, priorSignature == signature {
                    if let currentTotals = currentTotals {
                        previousTotals = currentTotals
                    }
                    continue
                }
                lastUsageSignature = signature

                var deltaTotals: TokenTotals?

                if let lastUsage = lastUsage {
                    deltaTotals = lastUsage
                } else if let currentTotals = currentTotals {
                    if let previous = previousTotals {
                        deltaTotals = currentTotals.delta(since: previous)
                    } else {
                        previousTotals = currentTotals
                        continue
                    }
                }

                if let currentTotals = currentTotals {
                    previousTotals = currentTotals
                }

                guard let deltaTotals else {
                    continue
                }

                let normalizedDelta = deltaTotals.normalized()
                guard normalizedDelta.isZero == false else {
                    continue
                }

                monthAggregate = monthAggregate.adding(makeUsageAggregate(for: normalizedDelta, model: lastModel))
            }
        }

        return monthAggregate
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

    private func processFile(
        at url: URL,
        previousState: FileState?,
        targetDay: Date,
        enforceTimestamp: Bool
    ) -> (FileState, Bool) {
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

        var aggregate = state.aggregate
        var hasUsage = state.hasTargetDayData
        var previousTotals = state.previousTotals
        var lastModel = state.lastModel
        var replayState = state.replayState

        for line in lines {
            if line.isEmpty {
                continue
            }

            let lineString = String(line)
            guard let lineData = lineString.data(using: .utf8),
                  let event = try? decoder.decode(TokenLogLine.self, from: lineData) else {
                continue
            }

            replayState.consume(event)

            if event.type == "turn_context" {
                lastModel = resolvedModel(from: event.payload?.model, fallback: lastModel)
                continue
            }

            guard event.type == "event_msg" else { continue }
            guard event.payload?.type == "token_count" else { continue }
            if replayState.isForkedSession { continue }
            if replayState.shouldSkipTokenCounts { continue }
            let info = event.payload?.info
            let currentTotals = info?.totalTokenUsage
            let lastUsage = info?.lastTokenUsage
            guard let timestamp = event.timestamp else { continue }
            guard let eventDate = isoFormatter.date(from: timestamp) else { continue }

            let signature = UsageSignature(totalTokenUsage: currentTotals, lastTokenUsage: lastUsage)
            if let lastSignature = state.lastUsageSignature, lastSignature == signature {
                if let currentTotals = currentTotals {
                    previousTotals = currentTotals
                }
                continue
            }
            state.lastUsageSignature = signature

            var deltaTotals: TokenTotals?

            if let lastUsage = lastUsage {
                deltaTotals = lastUsage
            } else if let currentTotals = currentTotals {
                if let previous = previousTotals {
                    deltaTotals = currentTotals.delta(since: previous)
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

            guard let deltaTotals else {
                continue
            }

            if enforceTimestamp, calendar.isDate(eventDate, inSameDayAs: targetDay) == false {
                continue
            }

            let normalizedDelta = deltaTotals.normalized()
            guard normalizedDelta.isZero == false else {
                continue
            }

            aggregate = aggregate.adding(makeUsageAggregate(for: normalizedDelta, model: lastModel))
            hasUsage = true
            changed = true
        }

        state.aggregate = aggregate
        state.hasTargetDayData = hasUsage
        state.previousTotals = previousTotals
        state.lastModel = lastModel
        state.replayState = replayState

        return (state, changed)
    }

    private func buildUsage(for targetDay: Date) throws -> [DailyTokenUsage] {
        var aggregate: UsageAggregate = .zero
        var sawUsage = false

        for state in fileStates.values {
            aggregate = aggregate.adding(state.aggregate)
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
            aggregate: aggregate
        )

        return [usage]
    }

    private func makeUsageAggregate(for totals: TokenTotals, model: String?) -> UsageAggregate {
        let rates = pricingCatalog.rates(for: model)
        return UsageAggregate(totals: totals, costs: CostTotals(totals: totals, rates: rates))
    }

    private func resolvedModel(from model: String?, fallback: String?) -> String? {
        guard let model, model.isEmpty == false else {
            return fallback
        }
        return model
    }

    private func resolvedRootURL() -> URL {
        if let sessionsRootURL {
            return sessionsRootURL
        }

        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }
}

private struct TokenLogLine: Decodable {
    let type: String
    let timestamp: String?
    let payload: Payload?

    struct Payload: Decodable {
        let type: String?
        let model: String?
        let info: Info?
        let sessionID: String?
        let forkedFromSessionID: String?
        let turnID: String?

        enum CodingKeys: String, CodingKey {
            case type
            case model
            case info
            case sessionID = "id"
            case forkedFromSessionID = "forked_from_id"
            case turnID = "turn_id"
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
