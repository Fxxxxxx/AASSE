import XCTest
@testable import AASSE

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
}