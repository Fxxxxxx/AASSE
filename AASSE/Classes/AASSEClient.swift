/// SSE 客户端核心实现
///
/// 使用 Actor 确保线程安全，封装连接管理、字节流解析和重连逻辑
/// 通过 AsyncStream 对外暴露事件流，支持 Swift Concurrency
///
/// 生命周期说明：
/// - 返回的 AsyncStream 由调用方通过 `for await` 循环消费，调用方在此上下文中天然持有实例
/// - 内部 Task 强捕获 self，确保连接期间实例不会被意外释放
/// - 强捕获不会造成永久 retain cycle：Task 完成后闭包引用自然释放，disconnect() 也会显式置 nil
/// - 如果需要主动断开连接，调用方需持有实例以调用 `disconnect()`
/// - 与 OC 桥接层 `AASSEClientOC` 的区别：OC 层采用 delegate fire-and-forget 模式，
///   调用方可能不持有实例，因此需要内部 Task 强持有；Swift 层通过 for await 循环
///   天然保证外部持有，内部强持有作为额外保障（防止外部意外释放导致静默失败）
public actor AASSEClient: Sendable {
    /// 客户端配置
    public struct Configuration: Sendable {
        /// SSE 服务端 URL
        public let url: URL
        /// 请求头（会被添加到每个请求中）
        public let headers: [String: String]
        /// URLSession 实例，默认为 .shared
        public let session: URLSession
        /// 基础重连间隔（秒），默认 3 秒
        public let retryInterval: TimeInterval
        /// 最大重连次数，默认 5 次（设为 Int.max 可无限重连）
        public let maxRetryCount: Int
        /// 是否启用指数退避，默认 true
        public let exponentialBackoff: Bool
        /// 最大重连延迟（秒），防止延迟过长，默认 60 秒
        public let maxRetryDelay: TimeInterval
        
        /// 创建配置
        /// - Parameters:
        ///   - url: SSE 服务端 URL
        ///   - headers: 请求头
        ///   - session: URLSession 实例
        ///   - retryInterval: 基础重连间隔（秒）
        ///   - maxRetryCount: 最大重连次数
        ///   - exponentialBackoff: 是否启用指数退避
        ///   - maxRetryDelay: 最大重连延迟（秒）
        public init(
            url: URL,
            headers: [String: String] = [:],
            session: URLSession = .shared,
            retryInterval: TimeInterval = 3,
            maxRetryCount: Int = 5,
            exponentialBackoff: Bool = true,
            maxRetryDelay: TimeInterval = 60
        ) {
            self.url = url
            self.headers = headers
            self.session = session
            self.retryInterval = retryInterval
            self.maxRetryCount = maxRetryCount
            self.exponentialBackoff = exponentialBackoff
            self.maxRetryDelay = maxRetryDelay
        }
    }
    
    /// 客户端配置（只读）
    private let configuration: Configuration
    /// 最后收到的事件 ID，用于重连时恢复（发送 Last-Event-ID 请求头）
    private var lastEventID: String?
    /// 当前重连次数
    private var retryCount = 0
    /// 服务器通过 retry 字段指定的重连间隔，优先级高于配置的默认值
    private var serverRetryInterval: TimeInterval?
    /// 当前连接任务，用于主动断开连接
    private var connectionTask: Task<Void, Never>?
    /// 当前任务的唯一标识，用于防止旧任务清理覆盖新任务
    private var connectionTaskID: Int = 0
    /// 当前事件流的 continuation，用于新连接建立时 finish 旧流
    private var currentContinuation: AsyncStream<AASSEClientEvent>.Continuation?
    /// 是否正在连接中（连接成功后为 true，断开后为 false）
    private var isConnecting = false
    
    /// 创建 SSE 客户端
    /// - Parameter configuration: 客户端配置
    public init(configuration: Configuration) {
        self.configuration = configuration
    }
    
    /// 是否正在连接中
    public var isConnected: Bool {
        isConnecting
    }
    
    /// 建立 SSE 连接，返回事件流
    /// - Returns: AsyncStream<AASSEClientEvent>，可通过 for await 迭代接收事件
    ///
    /// 使用示例：
    /// ```swift
    /// let stream = await client.connect()
    /// for await event in stream {
    ///     switch event {
    ///     case .open(let response): print("Connected")
    ///     case .event(let event): print("Received: \(event)")
    ///     case .error(let error): print("Error: \(error)")
    ///     case .closed: print("Closed")
    ///     }
    /// }
    /// ```
    ///
    /// 主动关闭连接：
    /// ```swift
    /// await client.disconnect()
    /// ```
    public func connect() -> AsyncStream<AASSEClientEvent> {
        AsyncStream { continuation in
            // 如果已有连接，先 finish 旧流并取消任务
            if let oldContinuation = currentContinuation {
                oldContinuation.yield(.closed)
                oldContinuation.finish()
            }
            connectionTask?.cancel()
            
            // 保存当前 continuation，用于新连接建立时 finish 旧流
            currentContinuation = continuation
            
            // 创建后台任务处理连接
            // 使用强捕获 self，因为：
            // 1. Swift async/await 语义保证调用方在 for await 循环中持有实例
            // 2. Task 完成后闭包引用会自然释放，不会造成永久 retain cycle
            // 3. disconnect() 会显式将 connectionTask 置 nil 打破循环
            // 4. [weak self] 会导致实例提前释放时静默 finish，外部无法感知异常
            connectionTaskID += 1
            let currentTaskID = connectionTaskID
            let newTask = Task {
                await self.connectWithRetry(continuation: continuation)
                // 任务完成后清理引用，释放资源
                // 仅当 connectionTaskID 仍匹配时才清理，避免覆盖新任务
                if self.connectionTaskID == currentTaskID {
                    self.isConnecting = false
                    self.connectionTask = nil
                    self.currentContinuation = nil
                }
            }
            connectionTask = newTask
            
            // 流终止时取消任务（调用方取消或流结束）
            continuation.onTermination = { @Sendable _ in
                newTask.cancel()
            }
        }
    }
    
    /// 主动断开 SSE 连接
    ///
    /// 取消当前连接任务，停止接收事件。
    /// 调用后，事件流会收到 .closed 事件后结束。
    public func disconnect() {
        connectionTask?.cancel()
        isConnecting = false
        connectionTask = nil
        currentContinuation = nil
        connectionTaskID = 0
        retryCount = 0
        serverRetryInterval = nil
    }
    
    /// 带重连的连接逻辑
    /// - Parameter continuation: AsyncStream 的 continuation，用于发送事件
    ///
    /// 连接流程：
    /// 1. 调用 connectOnce 建立单次连接
    /// 2. 如果返回错误且未达到最大重试次数，等待指数退避延迟后重试
    /// 3. 如果返回 nil（正常关闭），发送 .closed 事件并结束
    /// 4. 如果达到最大重试次数，发送 .retryLimitExceeded 错误并结束
    /// 5. 如果是任务取消（CancellationError），发送 .closed 事件并结束（用户主动断开）
    private func connectWithRetry(continuation: AsyncStream<AASSEClientEvent>.Continuation) async {
        while !Task.isCancelled {
            do {
                try await connectOnce(continuation: continuation)
                
                // 正常关闭，发送 .closed 事件并退出
                continuation.yield(.closed)
                break
                
            } catch is CancellationError {
                // 用户主动取消，发送 .closed 事件并退出
                continuation.yield(.closed)
                break
            } catch {
                // 其他错误，发送错误事件
                continuation.yield(.error(error as? AASSError ?? .networkError(error)))
                
                guard retryCount < configuration.maxRetryCount else {
                    continuation.yield(.error(.retryLimitExceeded))
                    break
                }
                
                retryCount += 1
                do {
                    try await Task.sleep(nanoseconds: UInt64(calculateRetryDelay() * 1_000_000_000))
                } catch {
                    // 任务被取消，退出循环
                    break
                }
            }
        }
        
        // 完成流
        continuation.finish()
    }
    
    /// 计算重连延迟时间
    /// - Returns: 延迟时间（秒）
    ///
    /// 指数退避算法：
    /// - 基础间隔：serverRetryInterval（服务器指定）或 configuration.retryInterval（默认）
    /// - 指数因子：2^(retryCount - 1)
    /// - 抖动：0~0.5 秒随机值，避免客户端同时重连
    /// - 上限：maxRetryDelay，防止延迟过长
    ///
    /// 示例（baseInterval = 3s）：
    /// - 第1次重试：3s + [0~0.5s]
    /// - 第2次重试：6s + [0~0.5s]
    /// - 第3次重试：12s + [0~0.5s]
    /// - 第4次重试：24s + [0~0.5s]
    /// - 第5次重试：48s + [0~0.5s]（受 maxRetryDelay 限制）
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
    
    /// 建立单次 SSE 连接
    /// - Parameter continuation: AsyncStream 的 continuation，用于发送事件
    /// - Throws: SSEError 或网络错误
    ///
    /// 连接流程：
    /// 1. 构建请求（添加 Accept、Connection、Last-Event-ID 等头）
    /// 2. 使用 URLSession.bytes 发起请求
    /// 3. 验证响应（必须是 HTTP 200，Content-Type 必须包含 text/event-stream）
    /// 4. 发送 .open 事件，重置重试计数
    /// 5. 解析字节流，处理事件
    /// 6. 正常结束（不抛出错误）
    private func connectOnce(continuation: AsyncStream<AASSEClientEvent>.Continuation) async throws {
        var request = URLRequest(url: configuration.url)
        // 指定接受 SSE 格式
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // 保持长连接
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        
        // 如果有上次事件 ID，添加到请求头用于恢复
        if let lastEventID {
            request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID")
        }
        
        // 添加自定义请求头
        configuration.headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // 使用 URLSession.bytes 发起流式请求
        let (bytes, response) = try await configuration.session.bytes(for: request)
        
        // 验证响应类型
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AASSError.invalidResponse
        }
        
        // 验证状态码（RFC 规范要求必须为 200）
        guard httpResponse.statusCode == 200 else {
            throw AASSError.invalidResponse
        }
        
        // 验证 Content-Type（必须包含 text/event-stream）
        guard let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
              contentType.contains("text/event-stream") else {
            throw AASSError.invalidContentType
        }
        
        // 连接成功，发送 .open 事件
        continuation.yield(.open(httpResponse))
        // 更新连接状态
        isConnecting = true
        // 重置重试计数
        retryCount = 0
        
        // 解析字节流
        try await parseBytes(bytes, continuation: continuation)
    }
    
    /// 解析字节流，将字节转换为文本行并交给 SSEParser 处理
    /// - Parameters:
    ///   - bytes: URLSession.AsyncBytes 字节流
    ///   - continuation: AsyncStream 的 continuation，用于发送事件
    ///
    /// 换行符处理策略（支持多种平台）：
    /// - LF (\n, 0x0A): 标准 Unix 换行
    /// - CR (\r, 0x0D): 旧版 Mac 换行
    /// - CRLF (\r\n): Windows 换行，通过 lastByteWasCR 标志位去重
    ///
    /// 注意：不使用 AsyncBytes.lines 的原因是它会丢弃连续空行，
    /// 而 SSE 协议依赖空行来分割事件。
    private func parseBytes(_ bytes: URLSession.AsyncBytes, 
                           continuation: AsyncStream<AASSEClientEvent>.Continuation) async throws {
        var parser = AASSEParser()
        var currentLine = Data()
        var lastByteWasCR = false
        
        // 逐字节读取
        for try await byte in bytes {
            if Task.isCancelled {
                // cancel 后立即退出，不处理剩余数据
                return
            }
            if byte == 0x0A { // LF (\n)
                // 如果前一个字节不是 CR，则处理当前行
                // 避免 CRLF 被处理两次
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
                // CR 立即处理当前行（旧版 Mac 换行）
                let line = String(data: currentLine, encoding: .utf8) ?? ""
                currentLine.removeAll()
                
                let events = parser.processLine(line)
                for event in events {
                    handleEvent(event, continuation: continuation)
                }
                lastByteWasCR = true
            } else {
                // 普通字节，累积到当前行
                currentLine.append(byte)
                lastByteWasCR = false
            }
        }
        
        // 处理流结束时可能剩余的未完成行
        if !currentLine.isEmpty {
            let line = String(data: currentLine, encoding: .utf8) ?? ""
            let events = parser.processLine(line)
            for event in events {
                handleEvent(event, continuation: continuation)
            }
        }
        
        // 流结束时，如果缓冲区中有累积的字段但没有空行，
        // 根据 RFC 规范应该视为完整事件并结算
        if let finalEvent = parser.flush() {
            handleEvent(finalEvent, continuation: continuation)
        }
    }
    
    /// 处理解析出的 SSE 事件
    /// - Parameters:
    ///   - event: SSE 事件
    ///   - continuation: AsyncStream 的 continuation，用于发送事件
    ///
    /// 事件处理逻辑：
    /// - message 事件：更新 lastEventID，通过 continuation 发送给调用方
    /// - retry 事件：更新 serverRetryInterval（不对外暴露）
    private func handleEvent(_ event: AASSEEvent, continuation: AsyncStream<AASSEClientEvent>.Continuation) {
        switch event {
        case .message(let id, _, _):
            // 更新最后事件 ID（用于重连恢复）
            if let id {
                self.lastEventID = id
            }
            // 发送事件给调用方
            continuation.yield(.event(event))
        case .retry(let interval):
            // 更新服务器指定的重连间隔（立即生效）
            self.serverRetryInterval = interval
        }
    }
}
