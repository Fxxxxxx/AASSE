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

### 为什么选择 URLSession.bytes 流式接口？

**与其他方案的对比：**

| 方案 | 优点 | 缺点 |
|------|------|------|
| **URLSession.bytes** ✅ | 原生支持、内存高效、与 Swift Concurrency 无缝集成 | 需手动处理换行符 |
| URLSession.dataTask | API 简单 | 一次性返回完整数据，不适合长连接流式场景 |
| URLSessionWebSocketTask | 原生支持双向通信 | WebSocket 是双向协议，SSE 是单向推送，语义不符 |
| 第三方库（Starscream 等） | 功能丰富 | 增加依赖体积、版本兼容问题、需跟进系统升级 |

**选择 URLSession.bytes 的核心原因：**

1. **原生支持**：无需引入第三方库，减少依赖体积和版本兼容风险
2. **内存高效**：逐字节处理，避免一次性加载大量数据到内存，适合长时间运行的 SSE 连接
3. **与 Swift Concurrency 无缝集成**：`AsyncBytes` 原生支持 `AsyncSequence`，可直接用 `for try await` 迭代
4. **符合 HTTP 语义**：SSE 基于 HTTP 长连接，使用 bytes 接口比 WebSocket 更直接，保持单向推送语义
5. **自动跟随系统升级**：随着 iOS 更新自动获得 URLSession 的性能优化和安全改进

**为什么不能用 `AsyncBytes.lines`？**

`AsyncBytes.lines` 会丢弃连续的空行，而 SSE 协议依赖空行来分割事件（RFC 规范）。因此必须手动逐字节解析换行符（`\n`、`\r`、`\r\n`）。

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

### 5. Cancel 响应机制

**Cancel 传播路径：**

```
调用方 task.cancel()
    → AsyncStream.onTermination 触发
    → AASSEClient 内部 Task.cancel()
    → connectWithRetry 检查 Task.isCancelled 或捕获 CancellationError
    → finish continuation
    → for await 循环退出
```

**显式 Task.isCancelled 检查的作用：**

```swift
// AASSEClient.parseBytes - 字节流解析循环
for try await byte in bytes {
    if Task.isCancelled {
        // cancel 后立即退出，不处理剩余数据
        return
    }
    // 处理字节...
}

// AASSEOCBridge - OC 桥接层事件循环
Task { [self] in
    defer {
        Task { @MainActor in
            // Task 退出时（无论 cancel 还是正常结束）都清理 task 引用
            if self.taskID == currentTaskID {
                self.task = nil
            }
        }
    }
    
    for await event in stream {
        if Task.isCancelled { return }  // cancel 后立即退出，defer 会异步清理
        handleEvent(event)
    }
}
```

**为什么需要显式检查？**

虽然 async/await 的自然传播机制会在 await 悬挂点抛出 `CancellationError`，但：
- **AsyncBytes 迭代**可能需要等待下一个字节到达才检查 cancel
- **AsyncStream 迭代**可能需要等待下一个事件才检查 cancel

添加显式检查可以：
1. **提高响应速度** - 在处理每个字节/事件前检查，立即退出
2. **避免无效处理** - cancel 后不应再处理数据
3. **降低延迟** - 从 cancel 到实际退出的时间更短

**Cancel 检查覆盖的悬挂点：**

| 悬挂点 | 检查方式 | 说明 |
|-------|---------|------|
| `connectWithRetry` 循环 | `while !Task.isCancelled` | 重连循环入口检查 |
| `Task.sleep` 等待 | `catch CancellationError` | 等待重连时被取消 |
| `parseBytes` 字节循环 | 显式 `Task.isCancelled` | 每个字节前检查 |
| OC 桥接层事件循环 | 显式 `Task.isCancelled` | 每个事件前检查 |
| `session.bytes(for:)` | 自然传播 CancellationError | async 调用自动传播 |

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

### UIViewController 集成示例

```swift
import UIKit
import AASSE

class SSEViewController: UIViewController {
    // 持有客户端实例，确保连接期间实例不被释放
    private var sseClient: AASSEClient?
    // 持有 Task，用于主动取消连接
    private var connectionTask: Task<Void, Never>?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupSSE()
    }
    
    private func setupSSE() {
        let url = URL(string: "https://api.example.com/events")!
        
        // 创建客户端
        sseClient = AASSE.createClient(url: url)
        
        // 在 Task 中处理事件流
        connectionTask = Task { [weak self] in
            guard let self, let client = self.sseClient else { return }
            
            let stream = await client.connect()
            for await event in stream {
                // 显式检查 cancel，提高响应速度
                if Task.isCancelled { return }
                
                await MainActor.run { [weak self] in
                    self?.handleEvent(event)
                }
            }
        }
    }
    
    private func handleEvent(_ event: AASSEClientEvent) {
        switch event {
        case .open(let response):
            print("Connected: \(response.statusCode)")
            // 更新 UI 显示连接状态
            
        case .event(let sseEvent):
            switch sseEvent {
            case .message(let id, let eventType, let data):
                // 处理消息事件
                print("Message: \(data)")
            case .retry(let interval):
                // retry 事件不对外暴露，SDK 内部自动更新重连间隔
                break
            }
            
        case .error(let error):
            print("Error: \(error)")
            // 处理错误，可能需要显示错误提示
            
        case .closed:
            print("Closed")
            // 连接正常关闭，更新 UI 状态
        }
    }
    
    // 主动断开连接
    private func disconnect() {
        connectionTask?.cancel()
        connectionTask = nil
        // 也可以调用: await sseClient?.disconnect()
    }
    
    deinit {
        // ViewController 销毁时自动取消连接
        connectionTask?.cancel()
        connectionTask = nil
        sseClient = nil
        print("SSEViewController deinit")
    }
}
```

**生命周期要点：**
- **强持有 client**：确保连接期间实例不被释放，避免静默失败
- **Task 的 cancel 传播**：取消 Task 会自动传播到底层连接，触发 `.closed` 事件
- **deinit 自动清理**：ViewController 销毁时取消 Task，防止内存泄漏
- **MainActor.run**：确保 UI 更新在主线程执行

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
