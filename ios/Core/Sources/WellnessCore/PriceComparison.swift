import Foundation

/// Basket price comparison across supermarket chains (port of the web app's lib/price-comparison).
public enum PriceComparison {
    public struct Chain: Equatable, Sendable { public let key: String, name: String, column: String }
    public static let chains: [Chain] = [
        .init(key: "shufersal", name: "שופרסל", column: "price_shufersal"), .init(key: "rami_levy", name: "רמי לוי", column: "price_rami_levy"),
        .init(key: "carrefour", name: "קרפור", column: "price_carrefour"), .init(key: "super_pharm", name: "סופר פארם", column: "price_super_pharm"),
        .init(key: "osher_ad", name: "אושר עד", column: "price_osher_ad")]
    /// The general grocery list skips the pharmacy chain; lists named after it compare against everyone.
    public static func excludedChains(forSection name: String) -> Set<String> { name.trimmingCharacters(in: .whitespaces) == "קניות בסופר" ? ["super_pharm"] : [] }

    public struct Product: Equatable, Sendable {
        public let barcode: String, name: String, prices: [String: Double]
        public init(barcode: String, name: String, prices: [String: Double]) { self.barcode = barcode; self.name = name; self.prices = prices }
        public init?(_ row: JSONValue) {
            guard let barcode = row["barcode"].stringValue, let name = row["product_name"].stringValue else { return nil }
            var p: [String: Double] = [:]
            for chain in PriceComparison.chains { if let v = row[chain.column].doubleValue, v.isFinite, v >= 0 { p[chain.key] = v } }
            self.init(barcode: barcode, name: name, prices: p)
        }
    }
    public struct Item: Equatable, Sendable { public let id: String, title: String, notes: String?; public init(id: String, title: String, notes: String? = nil) { self.id = id; self.title = title; self.notes = notes } }
    public enum Status: Equatable, Sendable { case exact, similar, notFound }
    public struct ItemResult: Equatable, Sendable { public let itemID: String, title: String, status: Status, productName: String?, price: Double? }
    public struct ChainResult: Equatable, Sendable { public let chain: Chain, total: Double?, items: [ItemResult], matched: Int, count: Int }
    public struct Result: Equatable, Sendable {
        public let ranked: [ChainResult], unavailable: [ChainResult], cheapest: ChainResult?, mostExpensive: ChainResult?, savings: Double?, savingsPercent: Double?
    }
    public protocol Source: Sendable {
        func product(barcode: String) async throws -> Product?
        func search(_ query: String) async throws -> [Product]
    }

    // MARK: Text helpers
    static let fillerPrefixes = ["צריך לקנות ", "צריכה לקנות ", "לקנות ", "צריך ", "צריכה ", "תביא ", "תביאי ", "להביא ", "קנה ", "קני ", "buy ", "get ", "need ", "purchase ", "pick up "]
    public static func stripFiller(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines), changed = true
        while changed {
            changed = false
            for p in fillerPrefixes where result.lowercased().hasPrefix(p) { result = String(result.dropFirst(p.count)).trimmingCharacters(in: .whitespaces); changed = true; break }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? trimmed : result
    }
    static let synonymGroups: [[String]] = [["סבון גוף", "תחליב רחצה", "תחליב גוף"]]
    public static func expandSynonyms(_ query: String) -> [String] {
        var variants = [query]
        for group in synonymGroups {
            guard let matched = group.first(where: { query.contains($0) }) else { continue }
            for term in group where term != matched { let v = query.replacingOccurrences(of: matched, with: term); if !variants.contains(v) { variants.append(v) } }
        }
        return variants
    }
    static func barcode(in notes: String?) -> String? {
        guard let notes, let r = notes.range(of: "(?<![0-9])[0-9]{8,14}(?![0-9])", options: .regularExpression) else { return nil }
        return String(notes[r])
    }

    // MARK: Comparison
    enum Match { case exact(Product), fuzzy([Product]), none }
    static func match(_ item: Item, source: Source) async throws -> Match {
        if let code = barcode(in: item.notes), let p = try await source.product(barcode: code) { return .exact(p) }
        var seen = Set<String>(), candidates: [Product] = []
        for q in expandSynonyms(stripFiller(item.title)) { for p in try await source.search(q) where seen.insert(p.barcode).inserted { candidates.append(p) } }
        return candidates.isEmpty ? .none : .fuzzy(candidates)
    }
    /// For a fuzzy match, the single candidate priced by the most chains, so chains compare the same product.
    static func sharedCandidate(_ candidates: [Product], chains: [Chain]) -> Product? {
        var best: Product?, bestCoverage = 1
        for c in candidates { let coverage = chains.filter { c.prices[$0.key] != nil }.count; if coverage > bestCoverage { bestCoverage = coverage; best = c } }
        return best
    }
    public static func compare(_ items: [Item], excluding: Set<String> = [], source: Source) async throws -> Result {
        let activeChains = chains.filter { !excluding.contains($0.key) }
        var matches: [Match] = []
        for item in items { matches.append(try await match(item, source: source)) }
        let shared: [Product?] = matches.map { if case .fuzzy(let c) = $0 { return sharedCandidate(c, chains: activeChains) } else { return nil } }
        let results: [ChainResult] = activeChains.map { chain in
            var total = 0.0, matched = 0
            let rows: [ItemResult] = items.enumerated().map { i, item in
                var product: Product?, status = Status.notFound
                switch matches[i] {
                case .exact(let p): product = p; status = .exact
                case .fuzzy(let c): product = (shared[i].flatMap { $0.prices[chain.key] != nil ? $0 : nil }) ?? c.first { $0.prices[chain.key] != nil }; status = .similar
                case .none: break
                }
                if let product, let price = product.prices[chain.key] { total += price; matched += 1; return ItemResult(itemID: item.id, title: item.title, status: status, productName: product.name, price: price) }
                return ItemResult(itemID: item.id, title: item.title, status: .notFound, productName: nil, price: nil)
            }
            return ChainResult(chain: chain, total: matched > 0 ? (total * 100).rounded() / 100 : nil, items: rows, matched: matched, count: items.count)
        }
        let withTotals = results.filter { $0.total != nil }
        let full = withTotals.filter { $0.matched == $0.count }.sorted { $0.total! < $1.total! }
        let partial = withTotals.filter { $0.matched < $0.count }.sorted { $0.total! < $1.total! }
        let cheapest = full.first, priciest = full.last
        var savings: Double?, percent: Double?
        if let cheapest, let priciest {
            savings = max(0, ((priciest.total! - cheapest.total!) * 100).rounded() / 100)
            if priciest.total! > 0, let savings { percent = (savings / priciest.total! * 1000).rounded() / 10 }
        }
        return Result(ranked: full + partial, unavailable: results.filter { $0.total == nil }, cheapest: cheapest, mostExpensive: priciest, savings: savings, savingsPercent: percent)
    }
}

extension Backend {
    /// `search_barcode_products` RPC: trigram title search over imported chain prices.
    public func searchBarcodeProducts(_ query: String, owner: String, limit: Int = 150) async throws -> [PriceComparison.Product] {
        guard !query.isEmpty, query.count <= 200 else { return [] }
        let rows = try await rpcRows("search_barcode_products", owner: owner, args: ["p_query": .string(query), "p_limit": .number(Double(min(limit, 150)))])
        return rows.compactMap(PriceComparison.Product.init)
    }
}
