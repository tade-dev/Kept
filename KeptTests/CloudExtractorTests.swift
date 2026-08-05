import CoreGraphics
import Foundation
import Testing
@testable import Kept

@Suite("CloudExtractor", .serialized)
struct CloudExtractorTests {
    @Test("maps a successful JSON response into ExtractedReceipt")
    func decodesSuccess() async throws {
        let json = """
        {
          "merchant": "ASDA STORES LTD",
          "itemName": "Grocery shop",
          "items": [
            { "name": "Milk", "price": 1.45 },
            { "name": "Bread", "price": 1.20 }
          ],
          "total": 18.13,
          "currencyCode": "GBP",
          "purchaseDate": "2026-06-16",
          "confidence": { "merchant": 1, "total": 1, "purchaseDate": 0.9 }
        }
        """
        nonisolated(unsafe) var seenMethod: String?
        nonisolated(unsafe) var seenAuth: String?
        nonisolated(unsafe) var seenPath: String?
        MockURLProtocol.requestHandler = { request in
            seenMethod = request.httpMethod
            seenAuth = request.value(forHTTPHeaderField: "Authorization")
            seenPath = request.url?.path
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(json.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let payload = try await makeExtractor().extractDetailed(from: sampleLines)
        #expect(seenMethod == "POST")
        #expect(seenAuth == "Bearer test-secret")
        #expect(seenPath?.hasSuffix("/extract") == true)
        #expect(payload.receipt.merchant == "ASDA STORES LTD")
        #expect(payload.receipt.itemName == "Grocery shop")
        #expect(abs(payload.receipt.price - 18.13) < 0.001)
        #expect(payload.receipt.currency == "GBP")
        #expect(payload.receipt.purchaseDate == "2026-06-16")
        #expect(payload.receipt.confidence > 0.9)
        #expect(payload.lineItems.count == 2)
        #expect(payload.lineItems[0].name == "Milk")
        #expect(abs(payload.lineItems[0].price - 1.45) < 0.001)
    }

    @Test("retries once on 5xx then succeeds")
    func retriesServerErrorOnce() async throws {
        let state = RequestCounter()
        MockURLProtocol.requestHandler = { request in
            let n = state.bump()
            if n == 1 {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, Data())
            }
            let body = Data(
                #"{"merchant":"X","itemName":null,"items":[],"total":1,"currencyCode":"GBP","purchaseDate":"2026-01-01","confidence":{"merchant":1,"total":1,"purchaseDate":1}}"#.utf8
            )
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, body)
        }
        defer { MockURLProtocol.requestHandler = nil }

        let result = try await makeExtractor().extract(from: sampleLines)
        #expect(result.merchant == "X")
        #expect(state.value == 2)
    }

    @Test("does not retry on 4xx")
    func noRetryOnClientError() async throws {
        let state = RequestCounter()
        MockURLProtocol.requestHandler = { request in
            _ = state.bump()
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"error":"bad"}"#.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        do {
            _ = try await makeExtractor().extract(from: sampleLines)
            Issue.record("expected CloudExtractionError.invalidResponse")
        } catch let error as CloudExtractionError {
            #expect(error == .invalidResponse)
        }
        #expect(state.value == 1)
    }

    @Test("plain-language errors never include status codes")
    func errorCopyHasNoStatusCodes() {
        let cases: [CloudExtractionError] = [
            .unauthorized, .rateLimited, .serverUnavailable, .offline, .timedOut,
        ]
        for error in cases {
            let text = error.errorDescription ?? ""
            #expect(!text.contains("401"))
            #expect(!text.contains("403"))
            #expect(!text.contains("429"))
            #expect(!text.contains("500"))
            #expect(!text.contains("HTTP"))
            #expect(!text.isEmpty)
        }
    }

    @Test("merge prefers cloud total when present")
    func mergePrefersCloudMoney() {
        let rules = ExtractedReceipt(
            merchant: "Wrong Shop",
            itemName: "Thing",
            price: 999,
            currency: "USD",
            purchaseDate: "2020-01-01",
            warrantyDurationMonths: 0,
            warrantyIsInferred: false,
            returnWindowDays: 28,
            returnWindowIsInferred: true,
            confidence: 0.5
        )
        let cloud = ExtractedReceipt(
            merchant: "ASDA STORES LTD",
            itemName: "Grocery shop",
            price: 18.13,
            currency: "GBP",
            purchaseDate: "2026-06-16",
            warrantyDurationMonths: 0,
            warrantyIsInferred: false,
            returnWindowDays: 0,
            returnWindowIsInferred: false,
            confidence: 0.95
        )
        let merged = CloudExtractor.merge(rules: rules, cloud: cloud)
        #expect(merged.merchant == "ASDA STORES LTD")
        #expect(merged.price == 18.13)
        #expect(merged.currency == "GBP")
        #expect(merged.purchaseDate == "2026-06-16")
        #expect(merged.returnWindowDays == 28)
    }

    // MARK: - Helpers

    private var sampleLines: [RecognizedLine] {
        [
            RecognizedLine(
                text: "ASDA",
                confidence: 1,
                boundingBox: CGRect(x: 0.1, y: 0.9, width: 0.5, height: 0.04)
            )
        ]
    }

    private func makeExtractor() -> CloudExtractor {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        let session = URLSession(configuration: config)
        return CloudExtractor(
            configuration: CloudExtractConfiguration(
                baseURL: URL(string: "http://extract.test")!,
                secret: "test-secret",
                timeout: 10
            ),
            session: session
        )
    }
}

// MARK: - Helpers
private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var count = 0

    nonisolated var value: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    nonisolated func bump() -> Int {
        lock.lock(); defer { lock.unlock() }
        count += 1
        return count
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler:
        (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
