/// SSE 协议层面的事件类型
///
/// 遵循 WHATWG HTML Standard 中 Server-Sent Events 规范
public enum AASSEEvent: Sendable {
    /// 消息事件，包含事件 ID、事件类型和数据内容
    /// - Parameters:
    ///   - id: 事件标识符，用于重连时恢复（Last-Event-ID）
    ///   - event: 事件类型名称，默认为 nil 表示通用消息
    ///   - data: 事件数据内容，多行 data 会被合并为带换行符的字符串
    case message(id: String?, event: String?, data: String)
    
    /// 服务器指定的重连间隔（秒）
    /// 收到此事件后立即更新重连延迟配置
    ///
    /// 注意：RFC 规范中 retry 字段值为毫秒，解析时已转换为秒
    case retry(interval: TimeInterval)
}

/// 客户端对外暴露的事件类型
/// 封装连接生命周期中的各种状态变化
public enum AASSEClientEvent: Sendable {
    /// 连接成功建立，返回 HTTP 响应对象
    case open(HTTPURLResponse)
    
    /// 收到服务器推送的事件
    case event(AASSEEvent)
    
    /// 发生错误（网络错误、协议错误等）
    case error(AASSError)
    
    /// 连接正常关闭（服务器主动断开或流结束）
    case closed
}

/// SSE 客户端错误类型
public enum AASSError: Error, Sendable {
    /// URL 无效
    case invalidURL
    
    /// 网络层错误，包装底层 Error
    case networkError(Error)
    
    /// HTTP 响应无效（非 HTTPURLResponse 或非 200 状态码）
    case invalidResponse
    
    /// Content-Type 不正确（必须为 text/event-stream）
    case invalidContentType
    
    /// 解析错误，包含错误描述信息
    case parsingError(String)
    
    /// 已达到最大重试次数，停止重连
    case retryLimitExceeded
}
