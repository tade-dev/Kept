import Foundation

/// Shared secret + base URL for the Cloudflare extract worker.
/// Values come from xcconfig → Info.plist (`KeptExtractBaseURL`, `KeptExtractSecret`).
struct CloudExtractConfiguration: Sendable, Equatable {
    var baseURL: URL
    var secret: String
    /// Per-request timeout. Spec: 10s.
    var timeout: TimeInterval = 10

    /// Reads from the app (or test) bundle Info.plist.
    static func fromBundle(_ bundle: Bundle = .main) -> CloudExtractConfiguration? {
        guard
            let base = bundle.object(forInfoDictionaryKey: "KeptExtractBaseURL") as? String,
            let url = URL(string: base.trimmingCharacters(in: .whitespacesAndNewlines)),
            !base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        guard
            let secret = bundle.object(forInfoDictionaryKey: "KeptExtractSecret") as? String
        else { return nil }

        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "REPLACE_ME" else { return nil }

        return CloudExtractConfiguration(baseURL: url, secret: trimmed)
    }

    /// Harness / CI: `KEPT_EXTRACT_BASE_URL` + `KEPT_EXTRACT_SECRET` env vars.
    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CloudExtractConfiguration? {
        guard
            let base = environment["KEPT_EXTRACT_BASE_URL"],
            let url = URL(string: base),
            let secret = environment["KEPT_EXTRACT_SECRET"],
            !secret.isEmpty
        else { return nil }
        return CloudExtractConfiguration(baseURL: url, secret: secret)
    }
}

/// Plain-language errors for cloud extraction. Never expose HTTP status codes in UI copy.
enum CloudExtractionError: Error, LocalizedError, Sendable, Equatable {
    case notConfigured
    case emptyInput
    case offline
    case timedOut
    case unauthorized
    case rateLimited
    case serverUnavailable
    case invalidResponse
    case underlying

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Cloud extraction isn't set up yet."
        case .emptyInput:
            "No text was recognized on the receipt."
        case .offline:
            "You're offline. We'll try again later."
        case .timedOut:
            "That took too long. We'll try again later."
        case .unauthorized:
            "Couldn't reach the extraction service."
        case .rateLimited:
            "Too many scans just now. Try again in a minute."
        case .serverUnavailable:
            "Extraction is temporarily unavailable."
        case .invalidResponse:
            "Couldn't read the extraction result."
        case .underlying:
            "Something went wrong extracting this receipt."
        }
    }
}

/// POSTs OCR lines to the Kept extract worker and maps the JSON into `ExtractedReceipt`.
/// Auth context passed from the app to the worker so the Pro-tier
/// extraction model can be served on verified requests. The worker cross-
/// checks `appUserID` against RevenueCat before honouring `isProClaimed`,
/// so the client sending `true` on its own doesn't earn the premium model.
struct ExtractionProContext: Equatable, Sendable {
    var appUserID: String
    var isProClaimed: Bool

    /// Nil when we don't know the customer's identity yet (e.g. RC not
    /// configured in this build). Falls back to the free model server-side.
    static func from(isPro: Bool, appUserID: String) -> ExtractionProContext? {
        guard !appUserID.isEmpty else { return nil }
        return ExtractionProContext(appUserID: appUserID, isProClaimed: isPro)
    }
}

struct CloudExtractor: ExtractionService {
    var configuration: CloudExtractConfiguration
    var session: URLSession

    init(
        configuration: CloudExtractConfiguration,
        session: URLSession? = nil
    ) {
        self.configuration = configuration
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = configuration.timeout
            config.timeoutIntervalForResource = configuration.timeout
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }

    /// Bundle config first, then environment (useful for tests / simulator).
    static func makeDefault() -> CloudExtractor? {
        if let config = CloudExtractConfiguration.fromBundle() {
            return CloudExtractor(configuration: config)
        }
        if let config = CloudExtractConfiguration.fromEnvironment() {
            return CloudExtractor(configuration: config)
        }
        return nil
    }

    func extract(from lines: [RecognizedLine]) async throws -> ExtractedReceipt {
        try await extractDetailed(from: lines, proContext: nil).receipt
    }

    func extract(
        from lines: [RecognizedLine],
        proContext: ExtractionProContext?
    ) async throws -> ExtractedReceipt {
        try await extractDetailed(from: lines, proContext: proContext).receipt
    }

    func extractDetailed(from lines: [RecognizedLine]) async throws -> CloudExtractionPayload {
        try await extractDetailed(from: lines, proContext: nil)
    }

    func extractDetailed(
        from lines: [RecognizedLine],
        proContext: ExtractionProContext?
    ) async throws -> CloudExtractionPayload {
        guard !lines.isEmpty else { throw CloudExtractionError.emptyInput }

        do {
            return try await perform(lines: lines, proContext: proContext, allowRetry: true)
        } catch let error as CloudExtractionError {
            throw error
        } catch {
            throw mapTransportError(error)
        }
    }

    // MARK: - Transport

    private func perform(
        lines: [RecognizedLine],
        proContext: ExtractionProContext?,
        allowRetry: Bool
    ) async throws -> CloudExtractionPayload {
        let url = configuration.baseURL.appendingPathComponent("extract")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Bearer \(configuration.secret)",
            forHTTPHeaderField: "Authorization"
        )
        request.timeoutInterval = configuration.timeout
        request.httpBody = try JSONEncoder().encode(CloudExtractRequest(
            lines: lines.map(CloudOCRLine.init),
            appUserID: proContext?.appUserID,
            isProClaimed: proContext?.isProClaimed
        ))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw mapTransportError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw CloudExtractionError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            return try decodePayload(from: data)
        case 401, 403:
            throw CloudExtractionError.unauthorized
        case 429:
            throw CloudExtractionError.rateLimited
        case 500...599:
            if allowRetry {
                return try await perform(lines: lines, proContext: proContext, allowRetry: false)
            }
            throw CloudExtractionError.serverUnavailable
        default:
            // 4xx (except auth/rate) — never retry.
            throw CloudExtractionError.invalidResponse
        }
    }

    private func decodePayload(from data: Data) throws -> CloudExtractionPayload {
        let decoded: CloudExtractResponse
        do {
            decoded = try JSONDecoder().decode(CloudExtractResponse.self, from: data)
        } catch {
            throw CloudExtractionError.invalidResponse
        }
        return decoded.asPayload()
    }

    private func mapTransportError(_ error: Error) -> CloudExtractionError {
        let urlError = error as? URLError
        switch urlError?.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .offline
        case .timedOut:
            return .timedOut
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .offline
        default:
            return .underlying
        }
    }
}

// MARK: - Wire DTOs

private struct CloudExtractRequest: Encodable {
    var lines: [CloudOCRLine]
    var appUserID: String?
    var isProClaimed: Bool?
}

private struct CloudOCRLine: Encodable {
    var text: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ line: RecognizedLine) {
        text = line.text
        x = line.boundingBox.origin.x
        y = line.boundingBox.origin.y
        width = line.boundingBox.size.width
        height = line.boundingBox.size.height
    }
}

private struct CloudExtractResponse: Decodable {
    /// Server-side classification. When != "receipt", every other field is null.
    /// Nil / missing = treat as receipt (server pre-2026-08-15 didn't send it).
    var documentType: String?
    var merchant: String?
    var itemName: String?
    var items: [CloudLineItem]?
    var total: Double?
    var currencyCode: String?
    var purchaseDate: String?
    var returnWindowDays: Double?
    var returnWindowIsInferred: Bool?
    var warrantyDurationMonths: Double?
    var warrantyIsInferred: Bool?
    var confidence: Confidence?

    struct CloudLineItem: Decodable {
        var name: String?
        var price: Double?
    }

    struct Confidence: Decodable {
        var merchant: Double?
        var total: Double?
        var purchaseDate: Double?
    }

    func asPayload() -> CloudExtractionPayload {
        let confidences = [
            confidence?.merchant,
            confidence?.total,
            confidence?.purchaseDate,
        ].compactMap { $0 }
        let overall: Double
        if confidences.isEmpty {
            overall = 0.5
        } else {
            overall = confidences.reduce(0, +) / Double(confidences.count)
        }

        let date = purchaseDate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let today: String = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: .now)
        }()

        let lineItems = CloudExtractor.dedupeLineItems(
            (items ?? []).compactMap { raw in
                let name = raw.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !name.isEmpty, let price = raw.price, price > 0 else { return nil }
                return ReceiptLineItem(name: name, price: price)
            }
        )

        var primaryName = itemName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        primaryName = CloudExtractor.refineItemName(primaryName, lineItems: lineItems)

        let returnDays = positiveInt(returnWindowDays)
        let warrantyMonths = positiveInt(warrantyDurationMonths)
        let reconciledTotal = CloudExtractor.reconcileTotal(total ?? 0, lineItems: lineItems)

        let receipt = ExtractedReceipt(
            merchant: merchant?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            itemName: primaryName,
            price: reconciledTotal,
            currency: (currencyCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
                .flatMap { $0.isEmpty ? nil : $0 } ?? "USD",
            purchaseDate: date.isEmpty ? today : date,
            warrantyDurationMonths: warrantyMonths,
            warrantyIsInferred: false,
            returnWindowDays: returnDays,
            returnWindowIsInferred: false,
            confidence: min(max(overall, 0), 1)
        )
        let fieldConfidences = FieldConfidences(
            merchant: confidence?.merchant,
            total: confidence?.total,
            purchaseDate: confidence?.purchaseDate
        )
        return CloudExtractionPayload(
            receipt: receipt,
            lineItems: lineItems,
            fieldConfidences: fieldConfidences,
            documentType: DocumentType.from(documentType)
        )
    }

    private func positiveInt(_ value: Double?) -> Int {
        guard let value, value > 0, value.isFinite else { return 0 }
        return Int(value.rounded())
    }
}

// MARK: - Merge (cloud wins money/date + printed coverage; rules fill gaps / inferences)

extension CloudExtractor {
    static func merge(
        rules: ExtractedReceipt,
        cloud: ExtractedReceipt,
        lineItems: [ReceiptLineItem] = []
    ) -> ExtractedReceipt {
        let merchant = cloud.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? rules.merchant : cloud.merchant
        var itemName = cloud.itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? rules.itemName : cloud.itemName
        itemName = refineItemName(itemName, lineItems: lineItems)

        let price = pickTotal(rules: rules.price, cloud: cloud.price, lineItems: lineItems)
        let currency = cloud.currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? rules.currency.uppercased() : cloud.currency.uppercased()
        let purchaseDate = cloud.purchaseDate.isEmpty ? rules.purchaseDate : cloud.purchaseDate

        let warrantyMonths: Int
        let warrantyInferred: Bool
        if cloud.warrantyDurationMonths > 0 {
            warrantyMonths = cloud.warrantyDurationMonths
            warrantyInferred = false
        } else {
            warrantyMonths = rules.warrantyDurationMonths
            warrantyInferred = rules.warrantyIsInferred
        }

        let returnDays: Int
        let returnInferred: Bool
        if cloud.returnWindowDays > 0 {
            returnDays = cloud.returnWindowDays
            returnInferred = false
        } else if rules.returnWindowDays > 0 {
            returnDays = rules.returnWindowDays
            returnInferred = rules.returnWindowIsInferred
        } else {
            returnDays = 0
            returnInferred = false
        }

        return ExtractedReceipt(
            merchant: merchant,
            itemName: itemName,
            price: price,
            currency: currency,
            purchaseDate: purchaseDate,
            warrantyDurationMonths: warrantyMonths,
            warrantyIsInferred: warrantyMonths > 0 ? warrantyInferred : false,
            returnWindowDays: returnDays,
            returnWindowIsInferred: returnDays > 0 ? returnInferred : false,
            confidence: max(rules.confidence, cloud.confidence)
        )
    }

    static func merge(
        rules: ExtractedReceipt,
        cloud: CloudExtractionPayload
    ) -> CloudExtractionPayload {
        let items = dedupeLineItems(cloud.lineItems)
        return CloudExtractionPayload(
            receipt: merge(rules: rules, cloud: cloud.receipt, lineItems: items),
            lineItems: items,
            fieldConfidences: cloud.fieldConfidences,
            documentType: cloud.documentType
        )
    }

    /// Prefer cloud total unless it undercuts a line item / rules found a better amount.
    static func pickTotal(
        rules: Double,
        cloud: Double,
        lineItems: [ReceiptLineItem]
    ) -> Double {
        let maxItem = lineItems.map(\.price).max() ?? 0
        let itemSum = lineItems.reduce(0) { $0 + $1.price }

        if cloud > 0, maxItem > 0, cloud + 0.009 < maxItem {
            if rules > 0, rules + 0.009 >= maxItem { return rules }
            if itemSum > 0 { return itemSum }
        }
        if cloud > 0 { return cloud }
        if rules > 0 { return rules }
        return itemSum
    }

    /// Drop postage/total rows and identical packing-slip duplicates (Price Paid + line Total).
    static func dedupeLineItems(_ items: [ReceiptLineItem]) -> [ReceiptLineItem] {
        var seen = Set<String>()
        var out: [ReceiptLineItem] = []
        for item in items {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, item.price > 0 else { continue }
            if isNonProductLineName(name) { continue }
            let key = "\(name.lowercased())|\(String(format: "%.2f", item.price))"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(ReceiptLineItem(id: item.id, name: name, price: item.price))
            if out.count >= 40 { break }
        }
        return out
    }

    static func isNonProductLineName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        let blocked = [
            "total", "grand total", "subtotal", "postage", "shipping", "delivery",
            "tax", "vat", "gst", "qty", "quantity", "balance", "amount due",
            "change", "cash", "card", "paid",
        ]
        return blocked.contains(lowered)
    }

    /// If a labeled total is smaller
    static func reconcileTotal(_ total: Double, lineItems: [ReceiptLineItem]) -> Double {
        guard !lineItems.isEmpty else { return max(total, 0) }
        let sum = lineItems.reduce(0) { $0 + $1.price }
        let maxItem = lineItems.map(\.price).max() ?? 0
        if total <= 0 { return sum }
        if total + 0.009 < maxItem { return sum }
        return total
    }

    static func refineItemName(_ name: String, lineItems: [ReceiptLineItem]) -> String {
        guard let top = lineItems.max(by: { $0.price < $1.price }) else { return name }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return top.name }
        let generics: Set<String> = ["grocery shop", "restaurant meal", "fuel", "shopping"]
        // Only replace basket summaries when the slip is clearly a single product
        // (packing slips / fashion). Multi-item groceries keep "Grocery shop".
        if generics.contains(trimmed.lowercased()), lineItems.count == 1 {
            return top.name
        }
        return trimmed
    }
}
