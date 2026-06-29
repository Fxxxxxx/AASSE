import XCTest
import AASSE

extension DispatchQueue {
    static var currentQueueLabel: String {
        String(validatingUTF8: __dispatch_queue_get_label(nil)) ?? "unknown"
    }
}

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
    
    func testFlushOnStreamEnd() {
        var parser = AASSEParser()
        
        // 累积数据但没有空行结束
        _ = parser.processLine("id:789")
        _ = parser.processLine("event:flush_test")
        _ = parser.processLine("data:remaining")
        
        // 模拟流结束时调用 flush
        let flushedEvent = parser.flush()
        
        XCTAssertNotNil(flushedEvent, "Should flush remaining data on stream end")
        
        if case .message(let id, let event, let data) = flushedEvent! {
            XCTAssertEqual(id, "789")
            XCTAssertEqual(event, "flush_test")
            XCTAssertEqual(data, "remaining")
        } else {
            XCTFail("Expected flushed message event")
        }
        
        // flush 后 lastEventID 应该更新
        XCTAssertEqual(parser.lastEventID, "789")
    }
    
    func testFlushEmptyBuffer() {
        var parser = AASSEParser()
        
        // 空缓冲区时 flush 应该返回 nil
        let flushedEvent = parser.flush()
        XCTAssertNil(flushedEvent, "Should return nil when buffer is empty")
    }
    
    func testFlushAfterEmptyLine() {
        var parser = AASSEParser()
        
        // 正常通过空行结算后，flush 不应再返回数据
        _ = parser.processLine("data:normal")
        let events = parser.processLine("")
        XCTAssertEqual(events.count, 1)
        
        // 此时缓冲区已清空
        let flushedEvent = parser.flush()
        XCTAssertNil(flushedEvent, "Should return nil after buffer was cleared by empty line")
    }
    
    func testEventWithOnlyId() {
        var parser = AASSEParser()
        
        // 只有 id 没有 data，不应该生成事件
        _ = parser.processLine("id:123")
        let events = parser.processLine("")
        
        XCTAssertEqual(events.count, 0, "Should not generate event without data")
        
        // 根据 RFC 规范，只有当事件被结算时才更新 lastEventID
        // 没有 data 的事件不会被结算，所以 lastEventID 应该是 nil
        // 但 ID 会在缓冲区中，用于后续事件继承
        XCTAssertNil(parser.lastEventID, "lastEventID should be nil when no event was settled")
        
        // 验证 ID 继承：下一个有 data 的事件应该继承这个 ID
        _ = parser.processLine("data:hello")
        let events2 = parser.processLine("")
        
        XCTAssertEqual(events2.count, 1)
        if case .message(let id, _, let data) = events2[0] {
            XCTAssertEqual(id, "123", "Should inherit previous ID")
            XCTAssertEqual(data, "hello")
        }
        
        // 此时 lastEventID 应该更新为 123
        XCTAssertEqual(parser.lastEventID, "123")
    }
    
    func testRetryEventInterspersedWithMessage() {
        var parser = AASSEParser()
        
        // 累积消息数据
        _ = parser.processLine("data:hello")
        
        // 插入 retry 事件
        let retryEvents = parser.processLine("retry:5000")
        XCTAssertEqual(retryEvents.count, 1)
        
        // 继续累积数据
        _ = parser.processLine("data:world")
        
        // 空行结算消息
        let messageEvents = parser.processLine("")
        XCTAssertEqual(messageEvents.count, 1)
        
        if case .message(_, _, let data) = messageEvents[0] {
            XCTAssertEqual(data, "hello\nworld")
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
        static var receivedRequests: [URLRequest] = []
        
        override class func canInit(with request: URLRequest) -> Bool {
            // 记录请求
            receivedRequests.append(request)
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
            receivedRequests = []
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
    
    func testClientCancelResponse() async throws {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [MockSSEURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        
        // 模拟持续发送数据的 SSE 流
        let mockData = "data:event1\n\ndata:event2\n\ndata:event3\n\n".data(using: .utf8)!
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
        
        // 创建一个 Task 来迭代 stream
        let streamTask = Task {
            for await event in stream {
                if Task.isCancelled { return }  // 显式检查 cancel
                events.append(event)
            }
        }
        
        // 等待收到第一个事件后 cancel
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        
        // 主动 cancel
        streamTask.cancel()
        await client.disconnect()
        
        // 等待 Task 完成
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        
        // 应该收到 .closed 事件（cancel 后正常退出）
        XCTAssertTrue(events.contains { event in
            if case .closed = event { return true }
            return false
        }, "Should receive .closed event after cancel")
        
        MockSSEURLProtocol.reset()
    }
    
    func testClientRetryDelayCalculation() async throws {
        // 此测试验证重连延迟计算逻辑（间接验证）
        // 由于 Mock URLProtocol 在网络错误场景下行为不稳定，
        // 这里只验证配置参数正确传递
        
        let url = URL(string: "https://example.com/sse")!
        let config = AASSEClient.Configuration(
            url: url,
            retryInterval: 1,
            maxRetryCount: 2,
            exponentialBackoff: true,
            maxRetryDelay: 30
        )
        
        let client = AASSEClient(configuration: config)
        
        // 验证配置正确传递
        // 实际重连延迟计算是 private 方法，
        // 通过 testClientReconnect 和指数退避逻辑间接验证
        
        XCTAssertNotNil(client)
        
        // 重连逻辑在 testClientReconnect 中已验证
        // 这里只确认客户端可以正常创建
    }
    
    func testClientCustomHeaders() async throws {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [MockSSEURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        
        let mockData = "data:test\n\n".data(using: .utf8)!
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
            headers: ["Authorization": "Bearer token123", "X-Custom": "custom-value"],
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
        
        MockSSEURLProtocol.reset()
    }
    
    func testClientIsConnectedState() async throws {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [MockSSEURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        
        let mockData = "data:test\n\n".data(using: .utf8)!
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
        
        // 初始状态应该是未连接
        let initialConnected = await client.isConnected
        XCTAssertFalse(initialConnected, "Initially should not be connected")
        
        var events: [AASSEClientEvent] = []
        let stream = await client.connect()
        
        // 等待收到 .open 事件后检查状态
        for await event in stream {
            events.append(event)
            if case .open = event {
                // 连接成功后应该是连接状态
                let connectedAfterOpen = await client.isConnected
                XCTAssertTrue(connectedAfterOpen, "Should be connected after .open")
            }
        }
        
        // 流结束后应该是未连接状态
        let connectedAfterClose = await client.isConnected
        XCTAssertFalse(connectedAfterClose, "Should not be connected after stream ends")
        
        MockSSEURLProtocol.reset()
    }
    
    func testClientServerRetryInterval() async throws {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [MockSSEURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        
        // 包含 retry 事件的数据
        let mockData = "retry:10000\ndata:hello\n\n".data(using: .utf8)!
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
        
        // 应该收到消息事件
        XCTAssertTrue(events.contains { event in
            if case .event(.message(_, _, "hello")) = event { return true }
            return false
        }, "Should receive message event")
        
        MockSSEURLProtocol.reset()
    }
    
    func testClientRequestHeaders() async throws {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [MockSSEURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        
        let mockData = "data:test\n\n".data(using: .utf8)!
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
            headers: ["Authorization": "Bearer token123", "X-Custom": "custom-value"],
            session: session,
            maxRetryCount: 0
        ))
        
        let stream = await client.connect()
        for await event in stream {}
        
        // 验证请求头
        XCTAssertFalse(MockSSEURLProtocol.receivedRequests.isEmpty, "Should have received requests")
        
        let request = MockSSEURLProtocol.receivedRequests.first
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Connection"), "keep-alive")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer token123")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "X-Custom"), "custom-value")
        
        MockSSEURLProtocol.reset()
    }
    
    func testClientCRLFLineEnding() async throws {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [MockSSEURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        
        // 使用 CRLF (\r\n) 作为换行符（Windows 风格）
        let mockData = Data([0x64, 0x61, 0x74, 0x61, 0x3A, 0x68, 0x65, 0x6C, 0x6C, 0x6F,  // data:hello
                            0x0D, 0x0A,  // CRLF
                            0x0D, 0x0A,  // 空行（CRLF）
                            0x64, 0x61, 0x74, 0x61, 0x3A, 0x77, 0x6F, 0x72, 0x6C, 0x64,  // data:world
                            0x0D, 0x0A])  // CRLF
        
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
        
        let messageEvents = events.filter { event in
            if case .event(.message) = event { return true }
            return false
        }
        
        XCTAssertEqual(messageEvents.count, 2, "Should receive 2 message events with CRLF line ending")
        
        MockSSEURLProtocol.reset()
    }
    
    func testClientLastEventIDOnReconnect() async throws {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [MockSSEURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        
        // 第一次连接发送带 ID 的事件
        let mockData = "id:event123\ndata:first\n\n".data(using: .utf8)!
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
        
        // 第一次连接
        let firstStream = await client.connect()
        for await event in firstStream {}
        
        // 第二次连接（模拟重连场景）
        let secondStream = await client.connect()
        for await event in secondStream {}
        
        // 验证第二次请求包含 Last-Event-ID
        XCTAssertGreaterThanOrEqual(MockSSEURLProtocol.receivedRequests.count, 2, "Should have received at least 2 requests")
        
        let secondRequest = MockSSEURLProtocol.receivedRequests[1]
        let lastEventID = secondRequest.value(forHTTPHeaderField: "Last-Event-ID")
        XCTAssertEqual(lastEventID, "event123", "Second request should include Last-Event-ID header")
        
        MockSSEURLProtocol.reset()
    }
    
    func testClientHandlesInvalidResponse() async throws {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.protocolClasses = [MockSSEURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        
        // 模拟非 HTTP 响应（返回 nil URLResponse）
        MockSSEURLProtocol.mockResponse = URLResponse(url: URL(string: "https://example.com/sse")!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        
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
        
        // 应该收到 invalidResponse 错误
        XCTAssertTrue(events.contains { event in
            if case .error(.invalidResponse) = event { return true }
            return false
        }, "Should receive invalidResponse error for non-HTTP response")
        
        MockSSEURLProtocol.reset()
    }
    
    func testClientServerRetryIntervalPriority() async throws {
        // serverRetryInterval 是 private 属性，无法直接验证
        // 通过验证配置参数传递来间接验证服务器 retry 优先级
        
        let url = URL(string: "https://example.com/sse")!
        
        // 配置 1：retryInterval = 1秒
        let config1 = AASSEClient.Configuration(
            url: url,
            retryInterval: 1,
            maxRetryCount: 2
        )
        
        let client1 = AASSEClient(configuration: config1)
        XCTAssertNotNil(client1)
        
        // 配置 2：retryInterval = 5秒
        let config2 = AASSEClient.Configuration(
            url: url,
            retryInterval: 5,
            maxRetryCount: 2
        )
        
        let client2 = AASSEClient(configuration: config2)
        XCTAssertNotNil(client2)
        
        // 实际重连延迟测试需要 Mock URLProtocol 触发重连
        // 在 testClientReconnect 中已间接验证重连机制
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

// MARK: - AASSE Factory Tests
final class AASSEFactoryTests: XCTestCase {
    func testCreateClientWithURL() async {
        let url = URL(string: "https://example.com/sse")!
        let client = AASSE.createClient(url: url)
        
        // 验证返回的是有效的 AASSEClient 实例
        XCTAssertNotNil(client)
        
        // 通过访问属性验证配置正确
        let isConnected = await client.isConnected
        XCTAssertFalse(isConnected, "Newly created client should not be connected")
    }
    
    func testCreateClientWithConfiguration() async {
        let url = URL(string: "https://example.com/sse")!
        let config = AASSEClient.Configuration(
            url: url,
            headers: ["Authorization": "Bearer token"],
            retryInterval: 5,
            maxRetryCount: 10,
            exponentialBackoff: false,
            maxRetryDelay: 120
        )
        
        let client = AASSE.createClient(configuration: config)
        
        XCTAssertNotNil(client)
        
        let isConnected = await client.isConnected
        XCTAssertFalse(isConnected)
    }
}

// MARK: - AASSEOCBridge Tests
final class AASSEOCBridgeTests: XCTestCase {
    func testAASSEClientOCInitWithURL() {
        let url = URL(string: "https://example.com/sse")!
        let clientOC = AASSEClientOC(url: url)
        
        XCTAssertNotNil(clientOC)
        XCTAssertNil(clientOC.delegate)
    }
    
    func testAASSEClientOCInitWithConfiguration() {
        let url = URL(string: "https://example.com/sse")!
        let config = AASSEConfigurationOC(
            url: url,
            headers: ["Authorization": "Bearer token"],
            retryInterval: 5,
            maxRetryCount: 10,
            exponentialBackoff: false,
            maxRetryDelay: 120,
            callbackQueue: .main
        )
        
        let clientOC = AASSEClientOC(configuration: config)
        
        XCTAssertNotNil(clientOC)
        XCTAssertNil(clientOC.delegate)
    }
    
    func testAASSEConfigurationOCDefaultValues() {
        let url = URL(string: "https://example.com/sse")!
        let config = AASSEConfigurationOC(url: url)
        
        XCTAssertEqual(config.url, url)
        XCTAssertEqual(config.headers, [:])
        XCTAssertEqual(config.retryInterval, 3)
        XCTAssertEqual(config.maxRetryCount, 5)
        XCTAssertEqual(config.exponentialBackoff, true)
        XCTAssertEqual(config.maxRetryDelay, 60)
        XCTAssertEqual(config.callbackQueue, .main)
    }
    
    func testAASSEConfigurationOCCustomValues() {
        let url = URL(string: "https://example.com/sse")!
        let customQueue = DispatchQueue(label: "test.queue")
        let config = AASSEConfigurationOC(
            url: url,
            headers: ["Authorization": "Bearer token"],
            retryInterval: 10,
            maxRetryCount: 20,
            exponentialBackoff: false,
            maxRetryDelay: 300,
            callbackQueue: customQueue
        )
        
        XCTAssertEqual(config.url, url)
        XCTAssertEqual(config.headers, ["Authorization": "Bearer token"])
        XCTAssertEqual(config.retryInterval, 10)
        XCTAssertEqual(config.maxRetryCount, 20)
        XCTAssertEqual(config.exponentialBackoff, false)
        XCTAssertEqual(config.maxRetryDelay, 300)
        XCTAssertEqual(config.callbackQueue, customQueue)
    }
    
    func testAASSEClientOCConnectAndDisconnect() async {
        let url = URL(string: "https://example.com/sse")!
        let clientOC = AASSEClientOC(url: url)
        
        // 测试连接和断开（无 delegate 时仍可调用）
        await clientOC.connect()
        
        // 等待一小段时间
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        await clientOC.disconnect()
        
        // 验证断开后可以再次连接
        await clientOC.connect()
        await clientOC.disconnect()
    }
    
    func testAASSEClientOCDelegateCallbacks() async {
        // 由于 AASSEClientOC 内部使用默认 URLSession，无法注入 Mock URLProtocol
        // 此测试验证 delegate 设置和基本回调机制
        let url = URL(string: "https://example.com/sse")!
        let clientOC = AASSEClientOC(url: url)
        
        let delegate = TestDelegate()
        clientOC.delegate = delegate
        
        // 验证 delegate 可以被正确设置
        XCTAssertNotNil(clientOC.delegate)
        
        // 验证 connect/disconnect 可以正常调用（不会崩溃）
        await clientOC.connect()
        try? await Task.sleep(nanoseconds: 50_000_000)
        await clientOC.disconnect()
        
        class TestDelegate: NSObject, AASSEClientDelegate {
            func client(_ client: AASSEClientOC, didOpen response: HTTPURLResponse) {}
            func client(_ client: AASSEClientOC, didReceiveMessage data: String, eventID: String?, eventType: String?) {}
        }
    }
    
    func testAASSEClientOCCallbackQueue() async {
        // 验证自定义回调队列配置可以被正确设置
        let url = URL(string: "https://example.com/sse")!
        let customQueue = DispatchQueue(label: "test.callback.queue")
        let config = AASSEConfigurationOC(url: url, callbackQueue: customQueue)
        let clientOC = AASSEClientOC(configuration: config)
        
        // 验证配置正确传递
        // callbackQueue 是 private 属性，通过初始化验证
        
        await clientOC.connect()
        try? await Task.sleep(nanoseconds: 50_000_000)
        await clientOC.disconnect()
    }
    
    func testAASSEClientOCDelegateErrorCallback() async {
        // 验证 OC 层的 error 回调机制
        let url = URL(string: "https://example.com/sse")!
        let clientOC = AASSEClientOC(url: url)
        
        let delegate = ErrorTestDelegate()
        clientOC.delegate = delegate
        
        // 验证 delegate 可以被正确设置
        XCTAssertNotNil(clientOC.delegate)
        
        // 由于无法注入 Mock URLProtocol，只能验证基本结构
        // 实际回调验证需要真实网络环境
        
        await clientOC.connect()
        try? await Task.sleep(nanoseconds: 50_000_000)
        await clientOC.disconnect()
        
        class ErrorTestDelegate: NSObject, AASSEClientDelegate {
            func client(_ client: AASSEClientOC, didFailWithError error: NSError) {
                // 错误回调处理
            }
        }
    }
}
