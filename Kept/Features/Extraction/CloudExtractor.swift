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
        try await extractDetailed(from: lines).receipt
    }

    func extractDetailed(from lines: [RecognizedLine]) async throws -> CloudExtractionPayload {
        guard !lines.isEmpty else { throw CloudExtractionError.emptyInput }

        do {
            return try await perform(lines: lines, allowRetry: true)
        } catch let error as CloudExtractionError {
            throw error
        } catch {
            throw mapTransportError(error)
        }
    }

    // MARK: - Transport

    private func perform(
        lines: [RecognizedLine],
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
        request.httpBody = try JSONEncoder().encode(CloudExtractRequest(lines: lines.map(CloudOCRLine.init)))

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
                return try await perform(lines: lines, allowRetry: false)
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
    var merchant: String?
    var itemName: String?
    var items: [CloudLineItem]?
    var total: Double?
    var currencyCode: String?
    var purchaseDate: String?
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

        let lineItems: [ReceiptLineItem] = (items ?? []).compactMap { raw in
            let name = raw.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty, let price = raw.price, price > 0 else { return nil }
            return ReceiptLineItem(name: name, price: price)
        }

        var primaryName = itemName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if primaryName.isEmpty, let top = lineItems.max(by: { $0.price < $1.price }) {
            primaryName = top.name
        }

        let receipt = ExtractedReceipt(
            merchant: merchant?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            itemName: primaryName,
            price: total ?? 0,
            currency: (currencyCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
                .flatMap { $0.isEmpty ? nil : $0 } ?? "USD",
            purchaseDate: date.isEmpty ? today : date,
            warrantyDurationMonths: 0,
            warrantyIsInferred: false,
            returnWindowDays: 0,
            returnWindowIsInferred: false,
            confidence: min(max(overall, 0), 1)
        )
        return CloudExtractionPayload(receipt: receipt, lineItems: lineItems)
    }
}

// MARK: - Merge (cloud wins money/date when present; rules keep warranty/return)

extension CloudExtractor {
    /// Prefer cloud merchant/item/total/date when the model returned a value.
    /// Rules keep return windows and any warranty they already inferred.
    static func merge(rules: ExtractedReceipt, cloud: ExtractedReceipt) -> ExtractedReceipt {
        let merchant = cloud.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? rules.merchant : cloud.merchant
        let itemName = cloud.itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? rules.itemName : cloud.itemName
        let price = cloud.price > 0 ? cloud.price : rules.price
        let currency = cloud.currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? rules.currency.uppercased() : cloud.currency.uppercased()
        let purchaseDate = cloud.purchaseDate.isEmpty ? rules.purchaseDate : cloud.purchaseDate

        return ExtractedReceipt(
            merchant: merchant,
            itemName: itemName,
            price: price,
            currency: currency,
            purchaseDate: purchaseDate,
            warrantyDurationMonths: rules.warrantyDurationMonths,
            warrantyIsInferred: rules.warrantyIsInferred,
            returnWindowDays: rules.returnWindowDays,
            returnWindowIsInferred: rules.returnWindowIsInferred,
            confidence: max(rules.confidence, cloud.confidence)
        )
    }

    static func merge(
        rules: ExtractedReceipt,
        cloud: CloudExtractionPayload
    ) -> CloudExtractionPayload {
        CloudExtractionPayload(
            receipt: merge(rules: rules, cloud: cloud.receipt),
            lineItems: cloud.lineItems
        )
    }
}
