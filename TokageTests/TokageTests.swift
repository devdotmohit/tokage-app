import Foundation
import Testing
@testable import Tokage

struct TokageTests {
    private struct FixtureTotals {
        let inputTokens: Int
        let cachedInputTokens: Int
        let outputTokens: Int
        let reasoningOutputTokens: Int
        let totalTokens: Int

        var jsonObject: [String: Int] {
            [
                "input_tokens": inputTokens,
                "cached_input_tokens": cachedInputTokens,
                "output_tokens": outputTokens,
                "reasoning_output_tokens": reasoningOutputTokens,
                "total_tokens": totalTokens
            ]
        }

        var tokenTotals: TokenTotals {
            TokenTotals(
                inputTokens: inputTokens,
                cachedInputTokens: cachedInputTokens,
                outputTokens: outputTokens,
                reasoningOutputTokens: reasoningOutputTokens,
                totalTokens: totalTokens
            )
        }
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private static let pricingCatalog = ModelPricingCatalog(
        defaultRates: ModelRates(input: 1.25, cachedInput: 0.125, output: 10.0),
        models: [
            "gpt-5.1-codex": ModelRates(input: 1.25, cachedInput: 0.125, output: 10.0),
            "gpt-5.3-codex": ModelRates(input: 1.75, cachedInput: 0.175, output: 14.0),
            "gpt-5.4": ModelRates(
                input: 2.5,
                cachedInput: 0.25,
                output: 15.0,
                longContextThreshold: 272_000,
                longContextInputMultiplier: 2.0,
                longContextOutputMultiplier: 1.5
            ),
            "gpt-5.5": ModelRates(
                input: 5.0,
                cachedInput: 0.5,
                output: 30.0,
                longContextThreshold: 272_000,
                longContextInputMultiplier: 2.0,
                longContextOutputMultiplier: 1.5
            ),
            "gpt-5.6-sol": ModelRates(
                input: 5.0,
                cachedInput: 0.5,
                output: 30.0,
                longContextThreshold: 272_000,
                longContextInputMultiplier: 2.0,
                longContextOutputMultiplier: 1.5
            )
        ],
        aliases: [
            "gpt-5.1-codex-max": "gpt-5.1-codex",
            "gpt-5.3-codex-spark": "gpt-5.3-codex",
            "gpt-5.6": "gpt-5.6-sol"
        ]
    )

    @Test func duplicateUsagePayloadsAreCountedOnceForDailyTotals() throws {
        let first = FixtureTotals(inputTokens: 100, cachedInputTokens: 20, outputTokens: 10, reasoningOutputTokens: 5, totalTokens: 110)
        let second = FixtureTotals(inputTokens: 50, cachedInputTokens: 10, outputTokens: 20, reasoningOutputTokens: 5, totalTokens: 70)

        let fileContents = try [
            "2026/02/22/session-a.jsonl": buildLog(events: [
                makeTokenCountEvent(timestamp: "2026-02-22T07:00:00.000Z", total: first, last: first),
                makeTokenCountEvent(timestamp: "2026-02-22T07:00:00.500Z", total: first, last: first),
                makeTokenCountEvent(timestamp: "2026-02-22T07:01:00.000Z", total: FixtureTotals(inputTokens: 150, cachedInputTokens: 30, outputTokens: 30, reasoningOutputTokens: 10, totalTokens: 180), last: second),
                makeTokenCountEvent(timestamp: "2026-02-22T07:01:00.500Z", total: FixtureTotals(inputTokens: 150, cachedInputTokens: 30, outputTokens: 30, reasoningOutputTokens: 10, totalTokens: 180), last: second)
            ])
        ]

        let (service, rootURL) = try makeService(logsByPath: fileContents)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let usage = try service.fetchDailyUsage(for: date(year: 2026, month: 2, day: 22))

        #expect(usage.count == 1)
        #expect(
            usage[0].totals == TokenTotals(
                inputTokens: 150,
                cachedInputTokens: 30,
                outputTokens: 30,
                reasoningOutputTokens: 10,
                totalTokens: 180
            )
        )
    }

    @Test func monthlyTotalsDedupeWithinFileButStillCountAcrossFiles() throws {
        let usage = FixtureTotals(inputTokens: 100, cachedInputTokens: 20, outputTokens: 10, reasoningOutputTokens: 5, totalTokens: 110)

        let fileContents = try [
            "2026/02/22/session-a.jsonl": buildLog(events: [
                makeTokenCountEvent(timestamp: "2026-02-22T07:00:00.000Z", total: usage, last: usage),
                makeTokenCountEvent(timestamp: "2026-02-22T07:00:00.500Z", total: usage, last: usage)
            ]),
            "2026/02/23/session-b.jsonl": buildLog(events: [
                makeTokenCountEvent(timestamp: "2026-02-23T08:00:00.000Z", total: usage, last: usage),
                makeTokenCountEvent(timestamp: "2026-02-23T08:00:00.500Z", total: usage, last: usage)
            ])
        ]

        let (service, rootURL) = try makeService(logsByPath: fileContents)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let aggregate = try service.fetchMonthlyTotals(for: date(year: 2026, month: 2, day: 22))
        #expect(
            aggregate.totals == TokenTotals(
                inputTokens: 200,
                cachedInputTokens: 40,
                outputTokens: 20,
                reasoningOutputTokens: 10,
                totalTokens: 220
            )
        )
    }

    @Test func currentTotalsFallbackSkipsBaselineAndIgnoresDuplicateSnapshots() throws {
        let firstCumulative = FixtureTotals(inputTokens: 120, cachedInputTokens: 20, outputTokens: 30, reasoningOutputTokens: 10, totalTokens: 150)
        let secondCumulative = FixtureTotals(inputTokens: 180, cachedInputTokens: 40, outputTokens: 50, reasoningOutputTokens: 20, totalTokens: 230)

        let fileContents = try [
            "2026/02/22/session-a.jsonl": buildLog(events: [
                makeTokenCountEvent(timestamp: "2026-02-22T07:00:00.000Z", total: firstCumulative, last: nil),
                makeTokenCountEvent(timestamp: "2026-02-22T07:00:00.500Z", total: firstCumulative, last: nil),
                makeTokenCountEvent(timestamp: "2026-02-22T07:01:00.000Z", total: secondCumulative, last: nil),
                makeTokenCountEvent(timestamp: "2026-02-22T07:01:00.500Z", total: secondCumulative, last: nil)
            ])
        ]

        let (service, rootURL) = try makeService(logsByPath: fileContents)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let usage = try service.fetchDailyUsage(for: date(year: 2026, month: 2, day: 22))
        #expect(usage.count == 1)
        #expect(
            usage[0].totals == TokenTotals(
                inputTokens: 60,
                cachedInputTokens: 20,
                outputTokens: 20,
                reasoningOutputTokens: 10,
                totalTokens: 80
            )
        )
    }

    @Test func monthLevelFallbackStillFiltersByTargetDayTimestamp() throws {
        let inDay = FixtureTotals(inputTokens: 90, cachedInputTokens: 30, outputTokens: 10, reasoningOutputTokens: 4, totalTokens: 100)
        let outOfDay = FixtureTotals(inputTokens: 40, cachedInputTokens: 10, outputTokens: 5, reasoningOutputTokens: 2, totalTokens: 45)

        let fileContents = try [
            "2026/02/fallback.jsonl": buildLog(events: [
                makeTokenCountEvent(timestamp: "2026-02-21T23:59:59.000Z", total: outOfDay, last: outOfDay),
                makeTokenCountEvent(timestamp: "2026-02-22T00:00:01.000Z", total: inDay, last: inDay)
            ])
        ]

        let (service, rootURL) = try makeService(logsByPath: fileContents)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let usage = try service.fetchDailyUsage(for: date(year: 2026, month: 2, day: 22))
        #expect(usage.count == 1)
        #expect(usage[0].totals == inDay.tokenTotals)
    }

    @Test func dailyTotalsUseEventTimestampInsteadOfFolderDate() throws {
        let firstDayUsage = FixtureTotals(inputTokens: 90, cachedInputTokens: 30, outputTokens: 10, reasoningOutputTokens: 4, totalTokens: 100)
        let secondDayUsage = FixtureTotals(inputTokens: 140, cachedInputTokens: 40, outputTokens: 20, reasoningOutputTokens: 6, totalTokens: 160)

        let fileContents = try [
            "2026/02/22/long-running-goal.jsonl": buildLog(events: [
                makeTokenCountEvent(timestamp: "2026-02-22T23:59:59.000Z", total: firstDayUsage, last: firstDayUsage),
                makeTokenCountEvent(timestamp: "2026-02-23T00:00:01.000Z", total: secondDayUsage, last: secondDayUsage)
            ])
        ]

        let (service, rootURL) = try makeService(logsByPath: fileContents)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let firstDay = try service.fetchDailyUsage(for: date(year: 2026, month: 2, day: 22))
        let secondDay = try service.fetchDailyUsage(for: date(year: 2026, month: 2, day: 23))

        #expect(firstDay[0].totals == firstDayUsage.tokenTotals)
        #expect(secondDay[0].totals == secondDayUsage.tokenTotals)
    }

    @Test func cumulativeTotalsUseOutOfDayBaselineButOnlyCountInDayDelta() throws {
        let baseline = FixtureTotals(inputTokens: 100, cachedInputTokens: 20, outputTokens: 10, reasoningOutputTokens: 4, totalTokens: 110)
        let inDayCumulative = FixtureTotals(inputTokens: 160, cachedInputTokens: 35, outputTokens: 25, reasoningOutputTokens: 9, totalTokens: 185)

        let fileContents = try [
            "2026/02/22/long-running-goal.jsonl": buildLog(events: [
                makeTokenCountEvent(timestamp: "2026-02-22T23:59:59.000Z", total: baseline, last: nil),
                makeTokenCountEvent(timestamp: "2026-02-23T00:00:01.000Z", total: inDayCumulative, last: nil)
            ])
        ]

        let (service, rootURL) = try makeService(logsByPath: fileContents)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let usage = try service.fetchDailyUsage(for: date(year: 2026, month: 2, day: 23))

        #expect(
            usage[0].totals == TokenTotals(
                inputTokens: 60,
                cachedInputTokens: 15,
                outputTokens: 15,
                reasoningOutputTokens: 5,
                totalTokens: 75
            )
        )
    }

    @Test func crossMonthGoalEventsAreAttributedToEventMonth() throws {
        let mayUsage = FixtureTotals(inputTokens: 100, cachedInputTokens: 20, outputTokens: 10, reasoningOutputTokens: 4, totalTokens: 110)
        let juneUsage = FixtureTotals(inputTokens: 200, cachedInputTokens: 30, outputTokens: 20, reasoningOutputTokens: 6, totalTokens: 220)

        let fileContents = try [
            "2026/05/31/long-running-goal.jsonl": buildLog(events: [
                makeTokenCountEvent(timestamp: "2026-05-31T23:59:59.000Z", total: mayUsage, last: mayUsage),
                makeTokenCountEvent(timestamp: "2026-06-01T00:00:01.000Z", total: juneUsage, last: juneUsage)
            ])
        ]

        let (service, rootURL) = try makeService(logsByPath: fileContents)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let juneDaily = try service.fetchDailyUsage(for: date(year: 2026, month: 6, day: 1))
        let mayTotals = try service.fetchMonthlyTotals(for: date(year: 2026, month: 5, day: 31))
        let juneTotals = try service.fetchMonthlyTotals(for: date(year: 2026, month: 6, day: 1))

        #expect(juneDaily[0].totals == juneUsage.tokenTotals)
        #expect(mayTotals.totals == mayUsage.tokenTotals)
        #expect(juneTotals.totals == juneUsage.tokenTotals)
    }

    @Test func monthlyCumulativeTotalsUseOutOfMonthBaseline() throws {
        let mayBaseline = FixtureTotals(inputTokens: 100, cachedInputTokens: 20, outputTokens: 10, reasoningOutputTokens: 4, totalTokens: 110)
        let juneCumulative = FixtureTotals(inputTokens: 180, cachedInputTokens: 35, outputTokens: 30, reasoningOutputTokens: 9, totalTokens: 210)

        let fileContents = try [
            "2026/05/31/long-running-goal.jsonl": buildLog(events: [
                makeTokenCountEvent(timestamp: "2026-05-31T23:59:59.000Z", total: mayBaseline, last: nil),
                makeTokenCountEvent(timestamp: "2026-06-01T00:00:01.000Z", total: juneCumulative, last: nil)
            ])
        ]

        let (service, rootURL) = try makeService(logsByPath: fileContents)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let juneTotals = try service.fetchMonthlyTotals(for: date(year: 2026, month: 6, day: 1))

        #expect(
            juneTotals.totals == TokenTotals(
                inputTokens: 80,
                cachedInputTokens: 15,
                outputTokens: 20,
                reasoningOutputTokens: 5,
                totalTokens: 100
            )
        )
    }

    @Test func cachedOlderFilesAreRecheckedBetweenRootScans() throws {
        var now = date(year: 2026, month: 6, day: 5)
        let currentMonthUsage = FixtureTotals(inputTokens: 20, cachedInputTokens: 5, outputTokens: 5, reasoningOutputTokens: 1, totalTokens: 25)
        let firstOlderUsage = FixtureTotals(inputTokens: 100, cachedInputTokens: 20, outputTokens: 10, reasoningOutputTokens: 4, totalTokens: 110)
        let secondOlderUsage = FixtureTotals(inputTokens: 80, cachedInputTokens: 15, outputTokens: 8, reasoningOutputTokens: 3, totalTokens: 88)

        let fileContents = try [
            "2026/06/01/current.jsonl": buildLog(events: [
                makeTokenCountEvent(timestamp: "2026-06-01T00:00:00.000Z", total: currentMonthUsage, last: currentMonthUsage)
            ]),
            "2026/05/31/long-running-goal.jsonl": buildLog(events: [
                makeTokenCountEvent(timestamp: "2026-06-01T00:00:01.000Z", total: firstOlderUsage, last: firstOlderUsage)
            ])
        ]

        let (service, rootURL) = try makeService(
            logsByPath: fileContents,
            rootScanInterval: 60 * 60,
            currentDate: { now }
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let firstUsage = try service.fetchDailyUsage(for: date(year: 2026, month: 6, day: 1))
        #expect(firstUsage[0].totals == currentMonthUsage.tokenTotals.adding(firstOlderUsage.tokenTotals))

        let olderFileURL = rootURL
            .appendingPathComponent("2026/05/31/long-running-goal.jsonl")
        try appendLog(
            events: [
                makeTokenCountEvent(timestamp: "2026-06-01T00:05:00.000Z", total: secondOlderUsage, last: secondOlderUsage)
            ],
            to: olderFileURL
        )
        try setModificationDate(date(year: 2026, month: 5, day: 31), for: olderFileURL)
        now = date(year: 2026, month: 6, day: 5)

        let secondUsage = try service.fetchDailyUsage(for: date(year: 2026, month: 6, day: 1))
        #expect(
            secondUsage[0].totals == currentMonthUsage.tokenTotals
                .adding(firstOlderUsage.tokenTotals)
                .adding(secondOlderUsage.tokenTotals)
        )
    }

    @Test func dailyTotalsIgnoreForkedSubagentLogs() throws {
        let parentUsage = FixtureTotals(inputTokens: 100, cachedInputTokens: 20, outputTokens: 10, reasoningOutputTokens: 5, totalTokens: 110)
        let childDelta = FixtureTotals(inputTokens: 60, cachedInputTokens: 10, outputTokens: 8, reasoningOutputTokens: 2, totalTokens: 68)
        let childCumulative = FixtureTotals(inputTokens: 160, cachedInputTokens: 30, outputTokens: 18, reasoningOutputTokens: 7, totalTokens: 178)

        let fileContents = try [
            "2026/02/22/session-parent.jsonl": buildLog(events: [
                makeSessionMetaEvent(timestamp: "2026-02-22T07:00:00.000Z", sessionID: "parent", forkedFromSessionID: nil),
                makeTurnContextEvent(timestamp: "2026-02-22T07:00:00.001Z", model: "gpt-5.4", turnID: "parent-turn"),
                makeTokenCountEvent(timestamp: "2026-02-22T07:00:00.002Z", total: parentUsage, last: parentUsage)
            ]),
            "2026/02/22/session-child.jsonl": buildLog(events: [
                makeSessionMetaEvent(timestamp: "2026-02-22T07:00:00.000Z", sessionID: "child", forkedFromSessionID: "parent"),
                makeSessionMetaEvent(timestamp: "2026-02-22T07:00:00.001Z", sessionID: "parent", forkedFromSessionID: nil),
                makeTurnContextEvent(timestamp: "2026-02-22T07:00:00.002Z", model: "gpt-5.4", turnID: "parent-turn"),
                makeTokenCountEvent(timestamp: "2026-02-22T07:00:00.003Z", total: parentUsage, last: parentUsage),
                makeTurnContextEvent(timestamp: "2026-02-22T07:00:01.000Z", model: "gpt-5.4", turnID: "child-turn"),
                makeTokenCountEvent(timestamp: "2026-02-22T07:00:01.001Z", total: childCumulative, last: childDelta)
            ])
        ]

        let (service, rootURL) = try makeService(logsByPath: fileContents)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let usage = try service.fetchDailyUsage(for: date(year: 2026, month: 2, day: 22))

        #expect(usage.count == 1)
        #expect(usage[0].totals == parentUsage.tokenTotals)
    }

    @Test func costsFollowCurrentModelAndAlias() throws {
        let first = FixtureTotals(inputTokens: 1_000_000, cachedInputTokens: 500_000, outputTokens: 100_000, reasoningOutputTokens: 50_000, totalTokens: 1_100_000)
        let second = FixtureTotals(inputTokens: 1_000_000, cachedInputTokens: 0, outputTokens: 100_000, reasoningOutputTokens: 20_000, totalTokens: 1_100_000)
        let third = FixtureTotals(inputTokens: 100_000, cachedInputTokens: 0, outputTokens: 10_000, reasoningOutputTokens: 0, totalTokens: 110_000)

        let fileContents = try [
            "2026/02/22/session-a.jsonl": buildLog(events: [
                makeTurnContextEvent(timestamp: "2026-02-22T07:00:00.000Z", model: "gpt-5.3-codex"),
                makeTokenCountEvent(timestamp: "2026-02-22T07:00:01.000Z", total: first, last: first),
                makeTurnContextEvent(timestamp: "2026-02-22T07:05:00.000Z", model: "gpt-5.4"),
                makeTokenCountEvent(timestamp: "2026-02-22T07:05:01.000Z", total: second, last: second),
                makeTurnContextEvent(timestamp: "2026-02-22T07:10:00.000Z", model: "gpt-5.3-codex-spark"),
                makeTokenCountEvent(timestamp: "2026-02-22T07:10:01.000Z", total: third, last: third)
            ])
        ]

        let (service, rootURL) = try makeService(logsByPath: fileContents)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let usage = try service.fetchDailyUsage(for: date(year: 2026, month: 2, day: 22))
        let totalCost = usage[0].costs.totalCost

        #expect(usage[0].totals == first.tokenTotals.adding(second.tokenTotals).adding(third.tokenTotals))
        #expect(isApproximatelyEqual(totalCost, 9.9275))
    }

    @Test func unknownModelsFallbackToDefaultPricing() throws {
        let usage = FixtureTotals(inputTokens: 1_000_000, cachedInputTokens: 500_000, outputTokens: 100_000, reasoningOutputTokens: 50_000, totalTokens: 1_100_000)

        let fileContents = try [
            "2026/02/22/session-a.jsonl": buildLog(events: [
                makeTurnContextEvent(timestamp: "2026-02-22T07:00:00.000Z", model: "gpt-5.unknown"),
                makeTokenCountEvent(timestamp: "2026-02-22T07:00:01.000Z", total: usage, last: usage)
            ])
        ]

        let (service, rootURL) = try makeService(logsByPath: fileContents)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let dailyUsage = try service.fetchDailyUsage(for: date(year: 2026, month: 2, day: 22))
        #expect(isApproximatelyEqual(dailyUsage[0].costs.totalCost, 1.6875))
    }

    @Test func gpt55PricingUsesCatalogRates() throws {
        let usage = FixtureTotals(inputTokens: 1_000_000, cachedInputTokens: 500_000, outputTokens: 100_000, reasoningOutputTokens: 50_000, totalTokens: 1_100_000)

        let fileContents = try [
            "2026/02/22/session-a.jsonl": buildLog(events: [
                makeTurnContextEvent(timestamp: "2026-02-22T07:00:00.000Z", model: "gpt-5.5"),
                makeTokenCountEvent(timestamp: "2026-02-22T07:00:01.000Z", total: usage, last: usage)
            ])
        ]

        let (service, rootURL) = try makeService(logsByPath: fileContents)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let dailyUsage = try service.fetchDailyUsage(for: date(year: 2026, month: 2, day: 22))
        #expect(isApproximatelyEqual(dailyUsage[0].costs.totalCost, 10.0))
    }

    @Test func monthlyTotalsUseModelSpecificRatesAcrossFiles() throws {
        let first = FixtureTotals(inputTokens: 1_000_000, cachedInputTokens: 0, outputTokens: 100_000, reasoningOutputTokens: 0, totalTokens: 1_100_000)
        let second = FixtureTotals(inputTokens: 1_000_000, cachedInputTokens: 0, outputTokens: 100_000, reasoningOutputTokens: 0, totalTokens: 1_100_000)

        let fileContents = try [
            "2026/02/22/session-a.jsonl": buildLog(events: [
                makeTurnContextEvent(timestamp: "2026-02-22T07:00:00.000Z", model: "gpt-5.3-codex"),
                makeTokenCountEvent(timestamp: "2026-02-22T07:00:01.000Z", total: first, last: first)
            ]),
            "2026/02/23/session-b.jsonl": buildLog(events: [
                makeTurnContextEvent(timestamp: "2026-02-23T07:00:00.000Z", model: "gpt-5.4"),
                makeTokenCountEvent(timestamp: "2026-02-23T07:00:01.000Z", total: second, last: second)
            ])
        ]

        let (service, rootURL) = try makeService(logsByPath: fileContents)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let aggregate = try service.fetchMonthlyTotals(for: date(year: 2026, month: 2, day: 22))

        #expect(aggregate.totals == first.tokenTotals.adding(second.tokenTotals))
        #expect(isApproximatelyEqual(aggregate.costs.totalCost, 10.4))
    }

    @Test func bundledCatalogIncludesGPT56FamilyAndAlias() {
        let catalog = ModelPricingCatalog.load()
        let sol = catalog.rates(for: "gpt-5.6-sol")
        let terra = catalog.rates(for: "gpt-5.6-terra")
        let luna = catalog.rates(for: "gpt-5.6-luna")

        #expect(sol == ModelRates(
            input: 5.0,
            cachedInput: 0.5,
            output: 30.0,
            longContextThreshold: 272_000,
            longContextInputMultiplier: 2.0,
            longContextOutputMultiplier: 1.5
        ))
        #expect(terra.input == 2.5)
        #expect(terra.cachedInput == 0.25)
        #expect(terra.output == 15.0)
        #expect(luna.input == 1.0)
        #expect(luna.cachedInput == 0.1)
        #expect(luna.output == 6.0)
        #expect(catalog.rates(for: "gpt-5.6") == sol)
    }

    @Test func longContextPricingStartsAbove272KInputTokens() {
        let rates = Self.pricingCatalog.rates(for: "gpt-5.6-sol")
        let atThreshold = TokenTotals(
            inputTokens: 272_000,
            cachedInputTokens: 200_000,
            outputTokens: 10_000,
            reasoningOutputTokens: 5_000,
            totalTokens: 282_000
        )
        let aboveThreshold = TokenTotals(
            inputTokens: 272_001,
            cachedInputTokens: 200_000,
            outputTokens: 10_000,
            reasoningOutputTokens: 5_000,
            totalTokens: 282_001
        )

        let standardCost = CostTotals(totals: atThreshold, rates: rates)
        let longContextCost = CostTotals(totals: aboveThreshold, rates: rates)

        #expect(isApproximatelyEqual(standardCost.totalCost, 0.76))
        #expect(isApproximatelyEqual(longContextCost.totalCost, 1.37001))
    }

    @Test func reasoningTokensAreIncludedOnceInOutputTotalsAndBreakdown() {
        let totals = TokenTotals(
            inputTokens: 100_000,
            cachedInputTokens: 50_000,
            outputTokens: 10_000,
            reasoningOutputTokens: 5_000,
            totalTokens: 110_000
        )
        let costs = CostTotals(totals: totals, rates: Self.pricingCatalog.rates(for: "gpt-5.6-sol"))
        let aggregate = UsageAggregate(totals: totals, costs: costs)
        let breakdown = TokenUsageFormatter.shared.breakdown(for: aggregate)

        #expect(aggregate.billingTokenTotal == 110_000)
        #expect(isApproximatelyEqual(costs.outputCost, 0.3))
        #expect(breakdown.map(\.kind) == [.input, .cached, .output])
        #expect(breakdown.last?.tokensText == "10K")
        #expect(breakdown.last?.costText == "$0.30")
    }

    @Test func monthlyTotalsIgnoreForkedSubagentLogs() throws {
        let parentUsage = FixtureTotals(inputTokens: 100, cachedInputTokens: 20, outputTokens: 10, reasoningOutputTokens: 5, totalTokens: 110)
        let childDelta = FixtureTotals(inputTokens: 60, cachedInputTokens: 10, outputTokens: 8, reasoningOutputTokens: 2, totalTokens: 68)
        let childCumulative = FixtureTotals(inputTokens: 160, cachedInputTokens: 30, outputTokens: 18, reasoningOutputTokens: 7, totalTokens: 178)

        let fileContents = try [
            "2026/02/22/session-parent.jsonl": buildLog(events: [
                makeSessionMetaEvent(timestamp: "2026-02-22T07:00:00.000Z", sessionID: "parent", forkedFromSessionID: nil),
                makeTurnContextEvent(timestamp: "2026-02-22T07:00:00.001Z", model: "gpt-5.4", turnID: "parent-turn"),
                makeTokenCountEvent(timestamp: "2026-02-22T07:00:00.002Z", total: parentUsage, last: parentUsage)
            ]),
            "2026/02/22/session-child.jsonl": buildLog(events: [
                makeSessionMetaEvent(timestamp: "2026-02-22T07:05:00.000Z", sessionID: "child", forkedFromSessionID: "parent"),
                makeSessionMetaEvent(timestamp: "2026-02-22T07:05:00.001Z", sessionID: "parent", forkedFromSessionID: nil),
                makeTurnContextEvent(timestamp: "2026-02-22T07:05:00.002Z", model: "gpt-5.4", turnID: "parent-turn"),
                makeTokenCountEvent(timestamp: "2026-02-22T07:05:00.003Z", total: parentUsage, last: parentUsage),
                makeTurnContextEvent(timestamp: "2026-02-22T07:05:01.000Z", model: "gpt-5.4", turnID: "child-turn"),
                makeTokenCountEvent(timestamp: "2026-02-22T07:05:01.001Z", total: childCumulative, last: childDelta)
            ])
        ]

        let (service, rootURL) = try makeService(logsByPath: fileContents)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let aggregate = try service.fetchMonthlyTotals(for: date(year: 2026, month: 2, day: 22))

        #expect(aggregate.totals == parentUsage.tokenTotals)
    }

    private func makeService(
        logsByPath: [String: String],
        rootScanInterval: TimeInterval = 30 * 60,
        currentDate: @escaping () -> Date = Date.init
    ) throws -> (TokenUsageService, URL) {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("tokage-tests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: nil)

        for (relativePath, contents) in logsByPath {
            let fileURL = rootURL.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        let service = TokenUsageService(
            fileManager: fileManager,
            calendar: Self.utcCalendar,
            sessionsRootURL: rootURL,
            pricingCatalog: Self.pricingCatalog,
            rootScanInterval: rootScanInterval,
            currentDate: currentDate
        )
        return (service, rootURL)
    }

    private func buildLog(events: [String]) -> String {
        events.joined()
    }

    private func appendLog(events: [String], to fileURL: URL) throws {
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        if let data = buildLog(events: events).data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
        try handle.close()
    }

    private func setModificationDate(_ date: Date, for fileURL: URL) throws {
        var mutableFileURL = fileURL
        var values = URLResourceValues()
        values.contentModificationDate = date
        try mutableFileURL.setResourceValues(values)
    }

    private func makeSessionMetaEvent(timestamp: String, sessionID: String, forkedFromSessionID: String?) throws -> String {
        var payload: [String: Any] = [
            "id": sessionID
        ]

        if let forkedFromSessionID {
            payload["forked_from_id"] = forkedFromSessionID
        }

        let event: [String: Any] = [
            "timestamp": timestamp,
            "type": "session_meta",
            "payload": payload
        ]

        return try encode(event: event)
    }

    private func makeTurnContextEvent(timestamp: String, model: String, turnID: String? = nil) throws -> String {
        var payload: [String: Any] = [
            "model": model
        ]

        if let turnID {
            payload["turn_id"] = turnID
        }

        let event: [String: Any] = [
            "timestamp": timestamp,
            "type": "turn_context",
            "payload": payload
        ]

        return try encode(event: event)
    }

    private func makeTokenCountEvent(
        timestamp: String,
        total: FixtureTotals?,
        last: FixtureTotals?
    ) throws -> String {
        var info: [String: Any] = [:]
        if let total {
            info["total_token_usage"] = total.jsonObject
        }
        if let last {
            info["last_token_usage"] = last.jsonObject
        }

        let event: [String: Any] = [
            "timestamp": timestamp,
            "type": "event_msg",
            "payload": [
                "type": "token_count",
                "info": info
            ]
        ]

        return try encode(event: event)
    }

    private func encode(event: [String: Any]) throws -> String {
        let json = try JSONSerialization.data(withJSONObject: event, options: [])
        guard let line = String(data: json, encoding: .utf8) else {
            throw NSError(domain: "TokageTests", code: 1, userInfo: nil)
        }

        return line + "\n"
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        guard let date = Self.utcCalendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            fatalError("Unable to build date for \(year)-\(month)-\(day)")
        }
        return date
    }

    private func isApproximatelyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.000001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }
}
