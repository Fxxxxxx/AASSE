import XCTest
import AASSE

// MARK: - AASSEParser Tests
final class AASSEParserTests: XCTestCase {
    func testSingleEvent() {
        var parser = AASSEParser()
        
        let events1 = parser.processLine("event:message")
        XCTAssertEqual(events1.count, 0)
        
        let events2 = parser.processLine("data:hello")
        XCTAssertEqual(events2.count, 0)
        
        let events3 = parser.processLine("")
        XCTAssertEqual(events3.count, 1)
        
        if case .message(let id, let event, let data) = events3[0] {
            XCTAssertNil(id)
            XCTAssertEqual(event, "message")
            XCTAssertEqual(data, "hello")
        } else {
            XCTFail("Expected message event")
        }
    }
    
    func testEventWithId() {
        var parser = AASSEParser()
        
        _ = parser.processLine("id:123")
        _ = parser.processLine("event:update")
        _ = parser.processLine("data:world")
        let events = parser.processLine("")
        
        XCTAssertEqual(events.count, 1)
        
        if case .message(let id, let event, let data) = events[0] {
            XCTAssertEqual(id, "123")
            XCTAssertEqual(event, "update")
            XCTAssertEqual(data, "world")
        } else {
            XCTFail("Expected message event")
        }
        
        XCTAssertEqual(parser.lastEventID, "123")
    }
    
    func testMultiLineData() {
        var parser = AASSEParser()
        
        _ = parser.processLine("data:line1")
        _ = parser.processLine("data:line2")
        _ = parser.processLine("data:line3")
        let events = parser.processLine("")
        
        XCTAssertEqual(events.count, 1)
        
        if case .message(_, _, let data) = events[0] {
            XCTAssertEqual(data, "line1\nline2\nline3")
        } else {
            XCTFail("Expected message event")
        }
    }
    
    func testRetryEvent() {
        var parser = AASSEParser()
        
        // RFC 规范中 retry 值为毫秒，解析后转换为秒
        let events = parser.processLine("retry:5000")
        
        XCTAssertEqual(events.count, 1)
        
        if case .retry(let interval) = events[0] {
            XCTAssertEqual(interval, 5.0)
        } else {
            XCTFail("Expected retry event")
        }
    }
    
    func testCommentLine() {
        var parser = AASSEParser()
        
        let events = parser.processLine(":this is a comment")
        
        XCTAssertEqual(events.count, 0)
    }
    
    func testEmptyEvent() {
        var parser = AASSEParser()
        
        let events = parser.processLine("")
        
        XCTAssertEqual(events.count, 0)
    }
    
    func testMultipleEvents() {
        var parser = AASSEParser()
        
        _ = parser.processLine("event:first")
        _ = parser.processLine("data:1")
        let events1 = parser.processLine("")
        XCTAssertEqual(events1.count, 1)
        
        _ = parser.processLine("event:second")
        _ = parser.processLine("data:2")
        let events2 = parser.processLine("")
        XCTAssertEqual(events2.count, 1)
        
        if case .message(_, let event1, let data1) = events1[0] {
            XCTAssertEqual(event1, "first")
            XCTAssertEqual(data1, "1")
        }
        
        if case .message(_, let event2, let data2) = events2[0] {
            XCTAssertEqual(event2, "second")
            XCTAssertEqual(data2, "2")
        }
    }
    
    func testEventWithNullCharacterInId() {
        var parser = AASSEParser()
        
        _ = parser.processLine("id:abc\0def")
        _ = parser.processLine("data:test")
        let events = parser.processLine("")
        
        XCTAssertEqual(events.count, 1)
        
        if case .message(let id, _, _) = events[0] {
            XCTAssertNil(id)
        }
    }
    
    func testDefaultEventName() {
        var parser = AASSEParser()
        
        _ = parser.processLine("data:hello")
        let events = parser.processLine("")
        
        XCTAssertEqual(events.count, 1)
        
        if case .message(_, let event, _) = events[0] {
            XCTAssertNil(event)
        }
    }
    
    func testBOMHandling() {
        var parser = AASSEParser()
        
        let events1 = parser.processLine("\u{FEFF}event:test")
        XCTAssertEqual(events1.count, 0)
        
        _ = parser.processLine("data:bom")
        let events2 = parser.processLine("")
        
        XCTAssertEqual(events2.count, 1)
        
        if case .message(_, let event, let data) = events2[0] {
            XCTAssertEqual(event, "test")
            XCTAssertEqual(data, "bom")
        }
    }
    
    func testCustomFieldIgnored() {
        var parser = AASSEParser()
        
        _ = parser.processLine("custom:value")
        _ = parser.processLine("data:test")
        let events = parser.processLine("")
        
        XCTAssertEqual(events.count, 1)
        
        if case .message(_, _, let data) = events[0] {
            XCTAssertEqual(data, "test")
        }
    }
    
    func testFieldWithSpace() {
        var parser = AASSEParser()
        
        _ = parser.processLine("data: hello world")
        let events = parser.processLine("")
        
        XCTAssertEqual(events.count, 1)
        
        if case .message(_, _, let data) = events[0] {
            XCTAssertEqual(data, "hello world")
        }
    }
    
    func testFieldWithMultipleSpaces() {
        var parser = AASSEParser()
        
        _ = parser.processLine("data:  two spaces")
        let events = parser.processLine("")
        
        XCTAssertEqual(events.count, 1)
        
        if case .message(_, _, let data) = events[0] {
            XCTAssertEqual(data, " two spaces")
        }
    }
    
    func testFieldWithoutSpace() {
        var parser = AASSEParser()
        
        _ = parser.processLine("data:nospace")
        let events = parser.processLine("")
        
        XCTAssertEqual(events.count, 1)
        
        if case .message(_, _, let data) = events[0] {
            XCTAssertEqual(data, "nospace")
        }
    }
    
    func testFieldEmptyValue() {
        var parser = AASSEParser()
        
        _ = parser.processLine("data:")
        let events = parser.processLine("")
        
        XCTAssertEqual(events.count, 1)
        
        if case .message(_, _, let data) = events[0] {
            XCTAssertEqual(data, "")
        }
    }
    
    func testFieldEmptyName() {
        var parser = AASSEParser()
        
        // Empty name fields (starting with :) are treated as comments and ignored
        _ = parser.processLine(":value without name")
        let events = parser.processLine("data:test")
        let finalEvents = parser.processLine("")
        
        // The colon-prefixed line is treated as a comment, not triggering an event
        XCTAssertEqual(events.count, 0)
        XCTAssertEqual(finalEvents.count, 1)
        
        if case .message(_, _, let data) = finalEvents[0] {
            XCTAssertEqual(data, "test")
        }
    }
    
    func testMultipleEmptyLines() {
        var parser = AASSEParser()
        
        _ = parser.processLine("data:test")
        let events1 = parser.processLine("")
        XCTAssertEqual(events1.count, 1)
        
        let events2 = parser.processLine("")
        XCTAssertEqual(events2.count, 0)
        
        let events3 = parser.processLine("")
        XCTAssertEqual(events3.count, 0)
    }
    
    func testEventIdInheritance() {
        var parser = AASSEParser()
        
        // First event with id
        _ = parser.processLine("id:123")
        _ = parser.processLine("data:first")
        let events1 = parser.processLine("")
        XCTAssertEqual(events1.count, 1)
        
        if case .message(let id1, _, let data1) = events1[0] {
            XCTAssertEqual(id1, "123")
            XCTAssertEqual(data1, "first")
        }
        
        // Second event without id should inherit the previous id
        _ = parser.processLine("data:second")
        let events2 = parser.processLine("")
        XCTAssertEqual(events2.count, 1)
        
        if case .message(let id2, _, let data2) = events2[0] {
            XCTAssertEqual(id2, "123")
            XCTAssertEqual(data2, "second")
        }
        
        // Third event with new id
        _ = parser.processLine("id:456")
        _ = parser.processLine("data:third")
        let events3 = parser.processLine("")
        XCTAssertEqual(events3.count, 1)
        
        if case .message(let id3, _, let data3) = events3[0] {
            XCTAssertEqual(id3, "456")
            XCTAssertEqual(data3, "third")
        }
        
        // Verify the new id is stored
        XCTAssertEqual(parser.lastEventID, "456")
    }
    
    func testInvalidRetryValue() {
        var parser = AASSEParser()
        
        // Invalid retry value (not a number)
        let events1 = parser.processLine("retry:not_a_number")
        XCTAssertEqual(events1.count, 0)
        
        // Empty retry value
        let events2 = parser.processLine("retry:")
        XCTAssertEqual(events2.count, 0)
        
        // Negative retry value
        let events3 = parser.processLine("retry:-5000")
        XCTAssertEqual(events3.count, 0)
        
        // Valid retry value should work (3000ms = 3s)
        let events4 = parser.processLine("retry:3000")
        XCTAssertEqual(events4.count, 1)
        
        if case .retry(let interval) = events4[0] {
            XCTAssertEqual(interval, 3.0)
        }
    }
}

// MARK: - AASSEClient Tests
final class AASSEClientTests: XCTestCase {
    
    // MARK: - Configuration Tests
    func testConfigurationDefaultValues() {
        let url = URL(string: "https://example.com/sse")!
        let config = AASSEClient.Configuration(url: url)
        
        XCTAssertEqual(config.url, url)
        XCTAssertEqual(config.headers, [:])
        XCTAssertEqual(config.session, .shared)
        XCTAssertEqual(config.retryInterval, 3)
        XCTAssertEqual(config.maxRetryCount, 5)
        XCTAssertEqual(config.exponentialBackoff, true)
        XCTAssertEqual(config.maxRetryDelay, 60)
    }
    
    func testConfigurationCustomValues() {
        let url = URL(string: "https://example.com/sse")!
        let session = URLSession.shared
        let config = AASSEClient.Configuration(
            url: url,
            headers: ["Authorization": "Bearer token"],
            session: session,
            retryInterval: 5,
            maxRetryCount: 10,
            exponentialBackoff: false,
            maxRetryDelay: 120
        )
        
        XCTAssertEqual(config.url, url)
        XCTAssertEqual(config.headers, ["Authorization": "Bearer token"])
        XCTAssertEqual(config.session, session)
        XCTAssertEqual(config.retryInterval, 5)
        XCTAssertEqual(config.maxRetryCount, 10)
        XCTAssertEqual(config.exponentialBackoff, false)
        XCTAssertEqual(config.maxRetryDelay, 120)
    }
    
    // MARK: - Mock URL Protocol
    class MockSSEURLProtocol: URLProtocol {
        static var mockResponseData: Data?
        static var mockResponse: URLResponse?
        static var mockError: Error?
        
        override class func canInit(with request: URLRequest) -> Bool {
            return true
        }
        
        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            return request
        }
        
        override func startLoading() {
            if let error = Self.mockError {
                client?.urlProtocol(self, didFailWithError: error)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            
            if let response = Self.mockResponse {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            
            if let data = Self.mockResponseData {
                client?.urlProtocol(self, didLoad: data)
            }
            
            client?.urlProtocolDidFinishLoading(self)
        }
        
        override func stopLoading() {}
        
        static func reset() {
            mockResponseData = nil
            mockResponse = nil
            mockError = nil
        }
    }
    
    // MARK: - SSEClient Integration Tests
    func testClientReceivesSingleEvent() async throws {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [MockSSEURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        
        // Use LF-only line endings for reliable parsing
        let mockData = "event:message\ndata:hello\n\n".data(using: .utf8)!
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com/sse")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        
        MockSSEURLProtocol.mockResponseData = mockData
        MockSSEURLProtocol.mockResponse = mockResponse
        
        let client = AASSEClient(configuration: .init(
            url: URL(string: "https://example.com/sse")!,
            session: session,
            maxRetryCount: 0
        ))
        
        var events: [AASSEClientEvent] = []
        let stream = await client.connect()
        for await event in stream {
            events.append(event)
        }
        
        XCTAssertTrue(events.contains { event in
            if case .open = event { return true }
            return false
        }, "Should receive .open event")
        
        XCTAssertTrue(events.contains { event in
            if case .event(.message(_, "message", "hello")) = event { return true }
            return false
        }, "Should receive message event with data 'hello'")
        
        XCTAssertTrue(events.contains { event in
            if case .closed = event { return true }
            return false
        }, "Should receive .closed event")
        
        MockSSEURLProtocol.reset()
    }
    
    func testClientHandlesNetworkError() async throws {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [MockSSEURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        
        MockSSEURLProtocol.mockError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        MockSSEURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com/sse")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/event-stream"]
        )
        
        let client = AASSEClient(configuration: .init(
            url: URL(string: "https://example.com/sse")!,
            session: session,
            maxRetryCount: 1
        ))
        
        var events: [AASSEClientEvent] = []
        let stream = await client.connect()
        for await event in stream {
            events.append(event)
        }
        
        // Should receive error and retryLimitExceeded
        let errorEvents = events.filter { event in
            if case .error = event { return true }
            return false
        }
        
        XCTAssertTrue(errorEvents.count >= 1, "Should receive at least one error event")
        
        MockSSEURLProtocol.reset()
    }
    
    func testClientHandlesInvalidContentType() async throws {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [MockSSEURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        
        let mockData = "data:test\n\n".data(using: .utf8)!
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com/sse")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        
        MockSSEURLProtocol.mockResponseData = mockData
        MockSSEURLProtocol.mockResponse = mockResponse
        
        let client = AASSEClient(configuration: .init(
            url: URL(string: "https://example.com/sse")!,
            session: session,
            maxRetryCount: 0
        ))
        
        var events: [AASSEClientEvent] = []
        let stream = await client.connect()
        for await event in stream {
            events.append(event)
        }
        
        // Should receive error for invalid content type
        XCTAssertTrue(events.contains { event in
            if case .error(.invalidContentType) = event { return true }
            return false
        }, "Should receive invalidContentType error")
        
        MockSSEURLProtocol.reset()
    }
    
    func testClientHandlesNon200StatusCode() async throws {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [MockSSEURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com/sse")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: [:]
        )!
        
        MockSSEURLProtocol.mockResponse = mockResponse
        
        let client = AASSEClient(configuration: .init(
            url: URL(string: "https://example.com/sse")!,
            session: session,
            maxRetryCount: 0
        ))
        
        var events: [AASSEClientEvent] = []
        let stream = await client.connect()
        for await event in stream {
            events.append(event)
        }
        
        XCTAssertTrue(events.contains { event in
            if case .error = event { return true }
            return false
        }, "Should receive error for non-200 status code")
        
        MockSSEURLProtocol.reset()
    }
    
    func testClientDisconnect() async throws {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [MockSSEURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        
        let mockData = "event:message\ndata:hello\n\n".data(using: .utf8)!
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com/sse")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        
        MockSSEURLProtocol.mockResponseData = mockData
        MockSSEURLProtocol.mockResponse = mockResponse
        
        let client = AASSEClient(configuration: .init(
            url: URL(string: "https://example.com/sse")!,
            session: session,
            maxRetryCount: 0
        ))
        
        var events: [AASSEClientEvent] = []
        let stream = await client.connect()
        
        // Wait for initial events
        for await event in stream {
            events.append(event)
            if case .closed = event {
                break
            }
        }
        
        XCTAssertTrue(events.contains { event in
            if case .open = event { return true }
            return false
        }, "Should receive .open event")
        
        XCTAssertTrue(events.contains { event in
            if case .closed = event { return true }
            return false
        }, "Should receive .closed event after disconnect")
        
        MockSSEURLProtocol.reset()
    }
    
    func testClientReconnect() async throws {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [MockSSEURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        
        let mockData = "event:message\ndata:first\n\n".data(using: .utf8)!
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com/sse")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        
        MockSSEURLProtocol.mockResponseData = mockData
        MockSSEURLProtocol.mockResponse = mockResponse
        
        let client = AASSEClient(configuration: .init(
            url: URL(string: "https://example.com/sse")!,
            session: session,
            retryInterval: 0.1,
            maxRetryCount: 2,
            maxRetryDelay: 0.1
        ))
        
        var events: [AASSEClientEvent] = []
        let stream = await client.connect()
        
        // Wait for a few events with timeout
        let timeout = Date().addingTimeInterval(2)
        for await event in stream {
            events.append(event)
            if Date() > timeout {
                break
            }
        }
        
        let openEvents = events.filter { event in
            if case .open = event { return true }
            return false
        }
        
        XCTAssertTrue(openEvents.count >= 1, "Should receive at least one .open event")
        
        MockSSEURLProtocol.reset()
    }
    
    func testClientConnectWhileConnected() async throws {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [MockSSEURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        
        let mockData = "event:message\ndata:first\n\n".data(using: .utf8)!
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com/sse")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        
        MockSSEURLProtocol.mockResponseData = mockData
        MockSSEURLProtocol.mockResponse = mockResponse
        
        let client = AASSEClient(configuration: .init(
            url: URL(string: "https://example.com/sse")!,
            session: session,
            maxRetryCount: 0
        ))
        
        // First connection
        var firstStreamEvents: [AASSEClientEvent] = []
        let firstStream = await client.connect()
        
        // Start second connection while first is still active
        var secondStreamEvents: [AASSEClientEvent] = []
        let secondStream = await client.connect()
        
        // Wait for first stream to close
        for await event in firstStream {
            firstStreamEvents.append(event)
        }
        
        // Wait for second stream
        for await event in secondStream {
            secondStreamEvents.append(event)
        }
        
        // First stream should receive .closed
        XCTAssertTrue(firstStreamEvents.contains { event in
            if case .closed = event { return true }
            return false
        }, "First stream should receive .closed")
        
        // Second stream should receive .open and events
        XCTAssertTrue(secondStreamEvents.contains { event in
            if case .open = event { return true }
            return false
        }, "Second stream should receive .open")
        
        MockSSEURLProtocol.reset()
    }
}

// MARK: - AASSEEvent Tests
final class AASSEEventTests: XCTestCase {
    func testMessageEventProperties() {
        let event = AASSEEvent.message(id: "123", event: "update", data: "content")
        
        if case .message(let id, let eventType, let data) = event {
            XCTAssertEqual(id, "123")
            XCTAssertEqual(eventType, "update")
            XCTAssertEqual(data, "content")
        } else {
            XCTFail("Expected message event")
        }
    }
    
    func testRetryEventProperties() {
        let event = AASSEEvent.retry(interval: 5)
        
        if case .retry(let interval) = event {
            XCTAssertEqual(interval, 5)
        } else {
            XCTFail("Expected retry event")
        }
    }
}

// MARK: - AASSEClientEvent Tests
final class AASSEClientEventTests: XCTestCase {
    func testOpenEventWithResponse() {
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let event = AASSEClientEvent.open(response)
        
        if case .open(let httpResponse) = event {
            XCTAssertEqual(httpResponse.statusCode, 200)
        } else {
            XCTFail("Expected open event")
        }
    }
    
    func testEventVariant() {
        let sseEvent = AASSEEvent.message(id: nil, event: nil, data: "test")
        let clientEvent = AASSEClientEvent.event(sseEvent)
        
        if case .event(.message(_, _, "test")) = clientEvent {
            // pass
        } else {
            XCTFail("Expected event variant")
        }
    }
    
    func testErrorVariant() {
        let clientError = AASSEClientEvent.error(.invalidURL)
        
        if case .error(.invalidURL) = clientError {
            // pass
        } else {
            XCTFail("Expected error variant")
        }
    }
    
    func testClosedVariant() {
        let event = AASSEClientEvent.closed
        
        if case .closed = event {
            // pass
        } else {
            XCTFail("Expected closed variant")
        }
    }
}

// MARK: - AASSError Tests
final class AASSErrorTests: XCTestCase {
    func testInvalidURL() {
        let error = AASSError.invalidURL
        
        if case .invalidURL = error {
            // pass
        } else {
            XCTFail("Expected invalidURL error")
        }
    }
    
    func testNetworkError() {
        let underlyingError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let error = AASSError.networkError(underlyingError)
        
        if case .networkError(let nsError) = error,
           let nsErr = nsError as? NSError {
            XCTAssertEqual(nsErr.domain, NSURLErrorDomain)
            XCTAssertEqual(nsErr.code, NSURLErrorNotConnectedToInternet)
        } else {
            XCTFail("Expected networkError")
        }
    }
    
    func testInvalidResponse() {
        let error = AASSError.invalidResponse
        
        if case .invalidResponse = error {
            // pass
        } else {
            XCTFail("Expected invalidResponse error")
        }
    }
    
    func testInvalidContentType() {
        let error = AASSError.invalidContentType
        
        if case .invalidContentType = error {
            // pass
        } else {
            XCTFail("Expected invalidContentType error")
        }
    }
    
    func testParsingError() {
        let error = AASSError.parsingError("test error")
        
        if case .parsingError(let message) = error {
            XCTAssertEqual(message, "test error")
        } else {
            XCTFail("Expected parsingError")
        }
    }
    
    func testRetryLimitExceeded() {
        let error = AASSError.retryLimitExceeded
        
        if case .retryLimitExceeded = error {
            // pass
        } else {
            XCTFail("Expected retryLimitExceeded error")
        }
    }
}
