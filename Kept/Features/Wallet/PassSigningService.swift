import Foundation
import PassKit

enum PassSigningError: Error, LocalizedError, Sendable, Equatable {
    case notConfigured
    case missingCoverage
    case offline
    case timedOut
    case unauthorized
    case rateLimited
    case serverUnavailable
    case invalidPass
    case underlying

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Wallet signing isn't set up yet."
        case .missingCoverage:
            "Add a warranty or return window before creating a pass."
        case .offline:
            "You're offline. Try again when you're back on the network."
        case .timedOut:
            "That took too long. Try again in a moment."
        case .unauthorized:
            "Couldn't reach the pass signing service."
        case .rateLimited:
            "Too many requests just now. Try again in a minute."
        case .serverUnavailable:
            "Pass signing is temporarily unavailable."
        case .invalidPass:
            "Couldn't build a Wallet pass from this purchase."
        case .underlying:
            "Something went wrong creating the Wallet pass."
        }
    }
}

struct PassSigningService: Sendable {
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
            config.timeoutIntervalForRequest = max(configuration.timeout, 15)
            config.timeoutIntervalForResource = max(configuration.timeout, 15)
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }

    static func makeDefault() -> PassSigningService? {
        if let config = CloudExtractConfiguration.fromBundle() {
            return PassSigningService(configuration: config)
        }
        if let config = CloudExtractConfiguration.fromEnvironment() {
            return PassSigningService(configuration: config)
        }
        return nil
    }

    /// Downloads a signed `.pkpass` for the purchase and returns a `PKPass`.
    func fetchPass(for purchase: Purchase, serialNumber: String) async throws -> PKPass {
        guard let coverageEndsAt = purchase.coverageEndsAt ?? purchase.nextDeadline?.expiryDate else {
            throw PassSigningError.missingCoverage
        }

        let url = configuration.baseURL.appendingPathComponent("pass")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.secret)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = max(configuration.timeout, 15)

        let body = PassSignRequestBody(
            merchant: purchase.merchant,
            itemName: purchase.itemName.isEmpty ? "Purchase" : purchase.itemName,
            total: NSDecimalNumber(decimal: purchase.price).doubleValue,
            currencyCode: purchase.currency.uppercased(),
            purchaseDate: isoDay(purchase.purchaseDate),
            coverageEndsAt: isoTimestamp(coverageEndsAt),
            serialNumber: serialNumber
        )
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw mapTransportError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw PassSigningError.invalidPass
        }

        switch http.statusCode {
        case 200:
            do {
                return try PKPass(data: data)
            } catch {
                throw PassSigningError.invalidPass
            }
        case 401, 403:
            throw PassSigningError.unauthorized
        case 429:
            throw PassSigningError.rateLimited
        case 500...599:
            throw PassSigningError.serverUnavailable
        default:
            throw PassSigningError.invalidPass
        }
    }

    private func mapTransportError(_ error: Error) -> PassSigningError {
        switch (error as? URLError)?.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .offline
        case .timedOut:
            return .timedOut
        default:
            return .underlying
        }
    }

    private func isoDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func isoTimestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

private struct PassSignRequestBody: Encodable {
    var merchant: String
    var itemName: String
    var total: Double
    var currencyCode: String
    var purchaseDate: String
    var coverageEndsAt: String
    var serialNumber: String
}
