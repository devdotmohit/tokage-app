import Foundation

struct ModelRates: Decodable, Equatable {
    let input: Double
    let cachedInput: Double?
    let output: Double
    let longContextThreshold: Int?
    let longContextInputMultiplier: Double?
    let longContextOutputMultiplier: Double?

    init(
        input: Double,
        cachedInput: Double? = nil,
        output: Double,
        longContextThreshold: Int? = nil,
        longContextInputMultiplier: Double? = nil,
        longContextOutputMultiplier: Double? = nil
    ) {
        self.input = input
        self.cachedInput = cachedInput
        self.output = output
        self.longContextThreshold = longContextThreshold
        self.longContextInputMultiplier = longContextInputMultiplier
        self.longContextOutputMultiplier = longContextOutputMultiplier
    }

    var cachedInputRate: Double {
        cachedInput ?? input
    }

    func effectiveRates(forInputTokens inputTokens: Int) -> (input: Double, cachedInput: Double, output: Double) {
        guard let longContextThreshold, inputTokens > longContextThreshold else {
            return (input, cachedInputRate, output)
        }

        let inputMultiplier = longContextInputMultiplier ?? 1
        let outputMultiplier = longContextOutputMultiplier ?? 1
        return (
            input * inputMultiplier,
            cachedInputRate * inputMultiplier,
            output * outputMultiplier
        )
    }
}

struct ModelPricingCatalog: Decodable {
    let defaultRates: ModelRates
    let models: [String: ModelRates]
    let aliases: [String: String]

    enum CodingKeys: String, CodingKey {
        case defaultRates
        case models
        case aliases
    }

    static let fallback = ModelPricingCatalog(
        defaultRates: ModelRates(input: 1.25, cachedInput: 0.125, output: 10.0),
        models: [:],
        aliases: [:]
    )

    init(defaultRates: ModelRates, models: [String: ModelRates], aliases: [String: String]) {
        self.defaultRates = defaultRates
        self.models = models
        self.aliases = aliases
    }

    static func load(bundle: Bundle = .main) -> ModelPricingCatalog {
        let bundles = [bundle, Bundle(for: BundleLocator.self)]

        for candidate in bundles {
            guard let url = candidate.url(forResource: "ModelPricing", withExtension: "json") else {
                continue
            }

            guard
                let data = try? Data(contentsOf: url),
                let catalog = try? JSONDecoder().decode(ModelPricingCatalog.self, from: data)
            else {
                continue
            }

            return catalog
        }

        return fallback
    }

    func rates(for model: String?) -> ModelRates {
        guard let model, model.isEmpty == false else {
            return defaultRates
        }

        if let exact = models[model] {
            return exact
        }

        if let alias = aliases[model], let aliased = models[alias] {
            return aliased
        }

        return defaultRates
    }
}

private final class BundleLocator {}
