# AASSE

A modern Server-Sent Events (SSE) SDK for iOS, built with Swift 6 concurrency, URLSession.bytes streaming, and AsyncStream.

[![CI Status](https://img.shields.io/travis/AaronFeng/AASSE.svg?style=flat)](https://travis-ci.org/AaronFeng/AASSE)
[![Version](https://img.shields.io/cocoapods/v/AASSE.svg?style=flat)](https://cocoapods.org/pods/AASSE)
[![License](https://img.shields.io/cocoapods/l/AASSE.svg?style=flat)](https://cocoapods.org/pods/AASSE)
[![Platform](https://img.shields.io/cocoapods/p/AASSE.svg?style=flat)](https://cocoapods.org/pods/AASSE)

## 技术选型与设计理念

### 为什么选择 Swift 6 Concurrency？

- **Async/Await**: 简化异步代码编写，避免回调地狱
- **AsyncStream**: 天然支持事件流模式，完美匹配 SSE 的推送特性
- **Actor**: 内置线程安全保障，确保客户端状态一致性
- **Sendable**: 编译期并发安全检查，杜绝数据竞争

### 架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                      AASSE (便捷入口)                        │
│              createClient(url:) / createClient(config:)     │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                    AASSEClient (核心客户端)                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │Configuration│  │ connect()   │  │ connectWithRetry()  │  │
│  │ (配置)      │  │ (返回流)    │  │ (重连逻辑)          │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │connectOnce()│  │ parseBytes()│  │ handleEvent()       │  │
│  │ (单次连接)   │  │ (字节解析)  │  │ (事件处理)          │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                   AASSEParser (事件解析器)                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │processLine()│  │ parseField()│  │    EventBuffer      │  │
│  │ (行解析)    │  │ (字段解析)  │  │   (事件缓冲区)       │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                    类型定义 (Types)                          │
│  AASSEEvent / AASSEClientEvent / AASSError                  │
└─────────────────────────────────────────────────────────────┘
```

## 核心实现解析

### 1. 类型系统设计

```swift
// SSE 协议层面的事件类型
public enum AASSEEvent: Sendable {
    case message(id: String?, event: String?, data: String)  // 消息事件
    case retry(interval: TimeInterval)                        // 重试间隔
}

// 客户端对外暴露的事件类型
public enum AASSEClientEvent: Sendable {
    case open(HTTPURLResponse)   // 连接建立
    case event(AASSEEvent)       // 收到事件
    case error(AASSError)        // 错误发生
    case closed                  // 正常关闭
}

**设计要点：**
- 区分协议层事件 (`AASSEEvent`) 和客户端事件 (`AASSEClientEvent`)
- `Sendable` 协议确保并发安全
- 错误类型细粒度划分，便于调用方精确处理

### 2. SSE 事件解析器

```swift
public struct AASSEParser: Sendable {
    private var buffer: EventBuffer = EventBuffer()
    
    public mutating func processLine(_ line: String) -> [AASSEEvent] {
        if processedLine.isEmpty {
            // 空行触发事件结算
            if let event = buffer.buildEvent() {
                events.append(event)
            }
            buffer.reset()
            return events
        }
        
        if processedLine.hasPrefix(":") {
            return events  // 注释行直接忽略
        }
        
        let (fieldName, fieldValue) = parseField(from: processedLine)
        // 根据字段名累积到 buffer...
    }
}
```

**解析流程：**
1. **BOM 处理**: 首行检测并移除 UTF-8 BOM
2. **空行结算**: 遇到空行时将缓冲区内容组装为完整事件
3. **注释忽略**: 以 `:` 开头的行被当作注释忽略
4. **字段累积**: `event`、`id`、`data` 字段累积到 `EventBuffer`
5. **Retry 立即生效**: `retry` 字段立即返回事件，不参与累积

**字段解析实现：**

```swift
private func parseField(from line: String) -> (Substring, Substring) {
    let scanner = Scanner(string: line)
    scanner.charactersToBeSkipped = nil
    
    if let name = scanner.scanUpToString(":"), !name.isEmpty {
        _ = scanner.scanString(":")
        let rest = line[scanner.currentIndex...]
        if rest.hasPrefix(" ") {
            return (Substring(name), rest.dropFirst())  // 跳过冒号后第一个空格
        }
        return (Substring(name), rest)
    }
    return (Substring(line), "")
}
```

**RFC 规范遵循：**
> fieldname:value 格式，冒号后的第一个空格可选（会被忽略）

### 3. 字节流解析

```swift
private func parseBytes(_ bytes: URLSession.AsyncBytes, 
                       continuation: AsyncStream<AASSEClientEvent>.Continuation) async throws {
    var parser = AASSEParser()
    var currentLine = Data()
    var lastByteWasCR = false
    
    for try await byte in bytes {
        if byte == 0x0A { // LF (\n)
            if !lastByteWasCR {
                let line = String(data: currentLine, encoding: .utf8) ?? ""
                currentLine.removeAll()
                let events = parser.processLine(line)
                for event in events {
                    handleEvent(event, continuation: continuation)
                }
            }
            lastByteWasCR = false
        } else if byte == 0x0D { // CR (\r)
            let line = String(data: currentLine, encoding: .utf8) ?? ""
            currentLine.removeAll()
            // ... 处理事件
            lastByteWasCR = true
        } else {
            currentLine.append(byte)
            lastByteWasCR = false
        }
    }
}
```

**换行符处理策略：**
- **LF** (`\n`, `0x0A`): 标准 Unix 换行
- **CR** (`\r`, `0x0D`): 旧版 Mac 换行
- **CRLF** (`\r\n`): Windows 换行，通过 `lastByteWasCR` 标志位去重

**为什么不用 `AsyncBytes.lines`？**

`AsyncBytes.lines` 会丢弃连续的空行，导致 SSE 事件边界丢失。SSE 协议依赖空行来分割事件，因此必须手动解析字节流。

### 4. 重连机制

```swift
private func connectWithRetry(continuation: AsyncStream<AASSEClientEvent>.Continuation) async {
    while !Task.isCancelled {
        if let error = await connectOnce(continuation: continuation) {
            continuation.yield(.error(error))
            
            guard retryCount < configuration.maxRetryCount else {
                continuation.yield(.error(.retryLimitExceeded))
                break
            }
            
            retryCount += 1
            try await Task.sleep(nanoseconds: UInt64(calculateRetryDelay() * 1_000_000_000))
        } else {
            continuation.yield(.closed)  // 正常关闭，不重连
            break
        }
    }
    
    continuation.finish()
}
```

**指数退避算法：**

```swift
private func calculateRetryDelay() -> TimeInterval {
    let baseInterval = serverRetryInterval ?? configuration.retryInterval
    
    if configuration.exponentialBackoff {
        let exponential = pow(2.0, Double(retryCount - 1))
        let jitter = Double.random(in: 0...0.5)
        let delay = baseInterval * exponential + jitter
        return min(delay, configuration.maxRetryDelay)
    }
    
    return baseInterval
}
```

**退避序列示例** (baseInterval = 3s):

| 重试次数 | 延迟时间 |
|---------|---------|
| 1 | 3s + [0~0.5s] |
| 2 | 6s + [0~0.5s] |
| 3 | 12s + [0~0.5s] |
| 4 | 24s + [0~0.5s] |
| 5 | 48s + [0~0.5s]（受 maxRetryDelay 限制） |

**设计要点：**
- **正常关闭不重连**: `connectOnce` 返回 `nil` 表示正常结束
- **抖动机制**: 避免客户端同时重连造成服务器压力
- **服务器控制**: 支持 `retry` 字段动态调整重连间隔
- **上限保护**: `maxRetryDelay` 防止延迟过长

## 使用方法

### 基础用法

```swift
import AASSE

let url = URL(string: "https://api.example.com/events")!
let client = AASSE.createClient(url: url)

for await event in client.connect() {
    switch event {
    case .open(let response):
        print("Connected with status: \(response.statusCode)")
        
    case .event(.message(let id, let eventType, let data)):
        print("Received event: \(eventType ?? "message")")
        print("ID: \(id ?? "none")")
        print("Data: \(data)")
        
    case .error(let error):
        print("Error: \(error)")
        
    case .closed:
        print("Connection closed normally")
    }
}
```

### 自定义配置

```swift
let config = AASSEClient.Configuration(
    url: url,
    headers: ["Authorization": "Bearer token"],
    retryInterval: 5,
    maxRetryCount: 10,
    exponentialBackoff: true,
    maxRetryDelay: 120
)

let client = AASSE.createClient(configuration: config)
```

### 取消连接

```swift
let task = Task {
    for await event in client.connect() {
        // 处理事件
    }
}

// 取消连接（方式一：取消 Task）
task.cancel()

// 取消连接（方式二：调用 disconnect 方法）
await client.disconnect()
```

**判断连接状态：**

```swift
let isConnected = await client.isConnected  // true 表示正在连接中
```

### Objective-C 用法

```objc
#import <AASSE/AASSE.h>

@interface MyViewController () <AASSEClientDelegate>
@property (strong, nonatomic) AASSEClient *sseClient;
@end

@implementation MyViewController

- (void)setupSSE {
    NSURL *url = [NSURL URLWithString:@"https://api.example.com/events"];
    self.sseClient = [[AASSEClient alloc] initWithURL:url];
    self.sseClient.delegate = self;
    
    // 自定义配置（可选）
    AASSEConfiguration *config = [[AASSEConfiguration alloc]
        initWithURL:url
            headers:@{@"Authorization": @"Bearer token"}
       retryInterval:5
      maxRetryCount:10
 exponentialBackoff:YES
     maxRetryDelay:120
      callbackQueue:dispatch_get_main_queue()];
    self.sseClient = [[AASSEClient alloc] initWithConfiguration:config];
    
    [self.sseClient connect];
}

- (void)client:(AASSEClient *)client didOpen:(NSHTTPURLResponse *)response {
    NSLog(@"Connected with status: %ld", (long)response.statusCode);
}

- (void)client:(AASSEClient *)client didReceiveMessage:(NSString *)data
       eventID:(NSString *)eventID
     eventType:(NSString *)eventType {
    NSLog(@"Received event: %@", eventType ?: @"message");
    NSLog(@"ID: %@", eventID ?: @"none");
    NSLog(@"Data: %@", data);
}

- (void)client:(AASSEClient *)client didFailWithError:(NSError *)error {
    NSLog(@"Error: %@", error);
}

- (void)clientDidClose:(AASSEClient *)client {
    NSLog(@"Connection closed normally");
}

- (void)dealloc {
    [self.sseClient disconnect];
}

@end
```

## 测试验证

### 测试覆盖范围

| 测试类 | 测试数 | 覆盖内容 |
|-------|-------|---------|
| AASSEParserTests | 19 | 事件解析核心逻辑 |
| AASSEClientTests | 8 | 配置、连接、错误处理 |
| AASSEEventTests | 2 | 事件类型属性 |
| AASSEClientEventTests | 4 | 客户端事件类型 |
| AASSErrorTests | 7 | 错误类型 |
| **总计** | **40** | |

### 关键测试用例

```swift
// 多行 data 合并测试
func testMultiLineData() {
    var parser = AASSEParser()
    
    _ = parser.processLine("data:line1")
    _ = parser.processLine("data:line2")
    _ = parser.processLine("data:line3")
    let events = parser.processLine("")  // 空行结算
    
    if case .message(_, _, let data) = events[0] {
        XCTAssertEqual(data, "line1\nline2\nline3")
    }
}

// 注释行忽略测试
func testCommentLine() {
    var parser = AASSEParser()
    
    let events = parser.processLine(":this is a comment")
    
    XCTAssertEqual(events.count, 0)  // 注释行不生成事件
}

// 连续空行处理测试
func testMultipleEmptyLines() {
    var parser = AASSEParser()
    
    _ = parser.processLine("data:test")
    let events1 = parser.processLine("")  // 生成事件
    let events2 = parser.processLine("")  // buffer 已空，无事件
    let events3 = parser.processLine("")  // 仍为空，无事件
    
    XCTAssertEqual(events1.count, 1)
    XCTAssertEqual(events2.count, 0)
    XCTAssertEqual(events3.count, 0)
}
```

## 安装

### CocoaPods

```ruby
pod 'AASSE'
```

### Requirements

- iOS 15.0+
- Swift 6.0+

## 协议规范

本 SDK 完全遵循以下规范：

- **WHATWG HTML Standard**: [Server-Sent Events](https://html.spec.whatwg.org/multipage/server-sent-events.html)
- **RFC 6455**: WebSocket Protocol (参考)

## 作者

AaronFeng, aaronfeng1993@163.com

## License

AASSE is available under the MIT license. See the LICENSE file for more info.
