import Foundation

/// Objective-C 桥接层 - SSE 客户端
///
/// 内部封装 Swift AASSEClient，通过 delegate 模式对外暴露事件回调
/// 支持 Objective-C 和 Swift 混编项目使用
///
/// 生命周期说明：
/// - 由于 OC 层采用 delegate 回调的 fire-and-forget 模式（调用方可能不持有实例），
///   内部 Task 会强持有 `self`，确保连接期间实例不会被释放
/// - 连接结束（正常关闭/错误/取消）后，Task 退出，实例自动释放
/// - 如果需要主动断开连接，调用方需要强持有实例以调用 `disconnect()`
/// - 与 Swift 层 `AASSEClient` 的区别：Swift 层返回 AsyncStream，调用方在 for await
///   循环中天然持有实例，而 OC 层无此约束，需要内部强持有保证生命周期
///
/// 回调线程：
/// - 默认在主线程执行回调，便于刷新 UI
/// - 可通过 `AASSEConfigurationOC` 的 `callbackQueue` 属性指定自定义队列
/// - 例如：后台队列处理数据，或主线程刷新 UI
@objc(AASSEClient)
public class AASSEClientOC: NSObject, @unchecked Sendable {
    
    /// 内部 Swift 客户端实例
    private let client: AASSEClient
    /// 连接任务，用于取消连接
    private var task: Task<Void, Never>?
    /// 当前任务的唯一标识，用于防止旧任务清理覆盖新任务
    private var taskID: Int = 0
    /// 回调队列，用于调度 delegate 回调
    private let callbackQueue: DispatchQueue
    
    /// 代理对象，接收事件回调
    @objc public weak var delegate: AASSEClientDelegate?
    
    /// 使用 URL 创建客户端（默认配置）
    /// - Parameter url: SSE 服务端 URL
    @objc public init(url: URL) {
        self.client = AASSE.createClient(url: url)
        self.callbackQueue = .main
        super.init()
    }
    
    /// 使用自定义配置创建客户端
    /// - Parameter configuration: 客户端配置
    @objc public init(configuration: AASSEConfigurationOC) {
        let swiftConfig = AASSEClient.Configuration(
            url: configuration.url,
            headers: configuration.headers,
            retryInterval: configuration.retryInterval,
            maxRetryCount: configuration.maxRetryCount,
            exponentialBackoff: configuration.exponentialBackoff,
            maxRetryDelay: configuration.maxRetryDelay
        )
        self.client = AASSE.createClient(configuration: swiftConfig)
        self.callbackQueue = configuration.callbackQueue
        super.init()
    }
    
    /// 建立 SSE 连接
    ///
    /// 调用此方法后，通过 delegate 接收事件回调
    ///
    /// 生命周期：连接期间内部 Task 会强持有实例，连接结束后自动释放
    @objc @MainActor public func connect() {
        // 如果已有连接，先断开
        task?.cancel()
        taskID += 1
        let currentTaskID = taskID
        let newTask = Task { [self] in
            let stream = await client.connect()
            for await event in stream {
                if Task.isCancelled { break }  // 显式检查 cancel，提前退出
                handleEvent(event)
            }
            // 连接结束后清理任务引用，释放强持有
            // 仅当 taskID 仍匹配时才清理，避免覆盖新任务
            await MainActor.run {
                if self.taskID == currentTaskID {
                    self.task = nil
                }
            }
        }
        task = newTask
    }
    
    /// 断开 SSE 连接
    ///
    /// 取消外层消费任务，通过 AsyncStream 的 onTermination 机制自动传播到底层连接任务
    @objc @MainActor public func disconnect() {
        task?.cancel()
        task = nil
        taskID = 0
    }
    
    /// 处理 Swift 层事件，转换为 OC 代理回调
    /// - Parameter event: SSE 客户端事件
    ///
    /// 回调会在配置的 callbackQueue 上执行，默认主线程
    private func handleEvent(_ event: AASSEClientEvent) {
        callbackQueue.async { [weak self] in
            guard let self else { return }
            switch event {
            case .open(let response):
                self.delegate?.client?(self, didOpen: response)
                
            case .event(let sseEvent):
                switch sseEvent {
                case .message(let id, let eventType, let data):
                    self.delegate?.client?(self, didReceiveMessage: data, eventID: id, eventType: eventType)
                case .retry:
                    break
                }
                
            case .error(let error):
                self.delegate?.client?(self, didFailWithError: error as NSError)
                
            case .closed:
                self.delegate?.clientDidClose?(self)
            }
        }
    }
}

/// Objective-C 桥接层 - SSE 客户端代理协议
///
/// 定义连接生命周期中的事件回调方法
@objc(AASSEClientDelegate)
public protocol AASSEClientDelegate: NSObjectProtocol {
    /// 连接成功建立
    /// - Parameters:
    ///   - client: 客户端实例
    ///   - response: HTTP 响应对象
    @objc optional func client(_ client: AASSEClientOC, didOpen response: HTTPURLResponse)
    
    /// 收到消息事件
    /// - Parameters:
    ///   - client: 客户端实例
    ///   - data: 事件数据内容
    ///   - eventID: 事件标识符（可能为 nil）
    ///   - eventType: 事件类型名称（可能为 nil）
    @objc optional func client(_ client: AASSEClientOC, didReceiveMessage data: String, eventID: String?, eventType: String?)
    
    /// 发生错误
    /// - Parameters:
    ///   - client: 客户端实例
    ///   - error: 错误对象
    @objc optional func client(_ client: AASSEClientOC, didFailWithError error: NSError)
    
    /// 连接正常关闭
    /// - Parameter client: 客户端实例
    @objc optional func clientDidClose(_ client: AASSEClientOC)
}

/// Objective-C 桥接层 - SSE 客户端配置
///
/// 对应 Swift SSEClient.Configuration，支持 Objective-C 使用
@objc(AASSEConfiguration)
public class AASSEConfigurationOC: NSObject, @unchecked Sendable {
    
    /// SSE 服务端 URL
    @objc public let url: URL
    /// 请求头（会被添加到每个请求中）
    @objc public let headers: [String: String]
    /// 基础重连间隔（秒），默认 3 秒
    @objc public let retryInterval: TimeInterval
    /// 最大重连次数，默认 5 次
    @objc public let maxRetryCount: Int
    /// 是否启用指数退避，默认 true
    @objc public let exponentialBackoff: Bool
    /// 最大重连延迟（秒），防止延迟过长，默认 60 秒
    @objc public let maxRetryDelay: TimeInterval
    /// 回调队列，默认为主线程队列。外部可指定自定义队列，
    /// 例如在后台队列处理数据，或在主线程刷新 UI
    @objc public let callbackQueue: DispatchQueue
    
    /// 创建配置
    /// - Parameters:
    ///   - url: SSE 服务端 URL
    ///   - headers: 请求头
    ///   - retryInterval: 基础重连间隔（秒）
    ///   - maxRetryCount: 最大重连次数
    ///   - exponentialBackoff: 是否启用指数退避
    ///   - maxRetryDelay: 最大重连延迟（秒）
    ///   - callbackQueue: 回调队列，默认为主线程
    @objc public init(url: URL,
                      headers: [String: String] = [:],
                      retryInterval: TimeInterval = 3,
                      maxRetryCount: Int = 5,
                      exponentialBackoff: Bool = true,
                      maxRetryDelay: TimeInterval = 60,
                      callbackQueue: DispatchQueue = .main) {
        self.url = url
        self.headers = headers
        self.retryInterval = retryInterval
        self.maxRetryCount = maxRetryCount
        self.exponentialBackoff = exponentialBackoff
        self.maxRetryDelay = maxRetryDelay
        self.callbackQueue = callbackQueue
        super.init()
    }
}
