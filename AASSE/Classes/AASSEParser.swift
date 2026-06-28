/// SSE 事件解析器
///
/// 负责将文本行解析为 SSE 事件，遵循 WHATWG HTML Standard 规范
/// 核心逻辑：逐行累积字段（event、id、data），遇到空行时结算为完整事件
public struct AASSEParser: Sendable {
    /// 事件缓冲区，用于累积未完成的事件字段
    private var buffer: EventBuffer = EventBuffer()
    /// 是否已遇到非 BOM 字符，用于处理首行 BOM
    private var hasSeenNonBOM = false
    /// 最后收到的事件 ID，用于重连时恢复（Last-Event-ID）
    private(set) public var lastEventID: String? = nil
    
    public init() {}
    
    /// 事件缓冲区，累积 event、id、data 字段直到遇到空行结算
    private struct EventBuffer: Sendable {
        /// 事件 ID，可能为空
        var id: String?
        /// 事件类型名称，可能为空（默认为通用消息）
        var event: String?
        /// 数据行数组，多行 data 会用换行符合并
        var data: [String] = []
        
        /// 重置缓冲区，准备接收下一个事件
        ///
        /// RFC 规范：ID 在事件间继承，直到被新的 id 字段覆盖
        mutating func reset() {
            event = nil
            data = []
        }
        
        /// 将缓冲区内的字段组装为完整事件
        /// - Returns: 如果 data 为空则返回 nil（空事件不生成），否则返回消息事件
        func buildEvent() -> AASSEEvent? {
            guard !data.isEmpty else { return nil }
            return .message(id: id, event: event, data: data.joined(separator: "\n"))
        }
    }
    
    /// 结算缓冲区内累积的最后一个事件（用于流结束时）
    /// - Returns: 如果缓冲区内有数据则返回事件，否则返回 nil
    ///
    /// 根据 RFC 规范，当流结束时，如果缓冲区中有累积的字段但没有空行，
    /// 应该视为完整事件并结算。
    public mutating func flush() -> AASSEEvent? {
        if let event = buffer.buildEvent() {
            // 更新最后事件 ID，与空行结算行为一致
            if let id = buffer.id {
                lastEventID = id
            }
            buffer.reset()
            return event
        }
        return nil
    }
    
    /// 处理一行文本，返回解析出的事件数组
    /// - Parameter line: 单行文本（不含换行符）
    /// - Returns: 解析出的事件数组，可能为空（注释行或空行无数据时）
    public mutating func processLine(_ line: String) -> [AASSEEvent] {
        var processedLine = line
        var events: [AASSEEvent] = []
        
        // 首行 BOM 处理：移除 UTF-8 BOM 标记（\u{FEFF}）
        if !hasSeenNonBOM {
            if processedLine.hasPrefix("\u{FEFF}") {
                processedLine = String(processedLine.dropFirst())
            }
            hasSeenNonBOM = true
        }
        
        // 空行触发事件结算：将缓冲区内容组装为完整事件
        if processedLine.isEmpty {
            if let event = buffer.buildEvent() {
                events.append(event)
                // 更新最后事件 ID（用于重连）
                if let id = buffer.id {
                    lastEventID = id
                }
            }
            buffer.reset()
            return events
        }
        
        // 注释行：以冒号开头的行直接忽略（RFC 规范）
        if processedLine.hasPrefix(":") {
            return events
        }
        
        // 解析字段名和字段值
        let (fieldName, fieldValue) = parseField(from: processedLine)
        
        // 根据字段名累积到缓冲区或立即返回事件
        switch fieldName {
        case "event":
            buffer.event = String(fieldValue)
        case "id":
            // ID 中包含空字符（\0）时忽略整行（RFC 规范）
            if !fieldValue.contains("\0") {
                buffer.id = String(fieldValue)
            }
        case "data":
            buffer.data.append(String(fieldValue))
        case "retry":
            // retry 事件立即生效，不参与缓冲区累积
            // RFC 规范中 retry 值为毫秒，转换为秒
            // 仅接受非负整数值
            if let milliseconds = TimeInterval(fieldValue), milliseconds >= 0 {
                events.append(.retry(interval: milliseconds / 1000.0))
            }
        default:
            // 未知字段忽略（RFC 规范允许自定义字段）
            break
        }
        
        return events
    }
    
    /// 解析字段名和字段值
    /// - Parameter line: 单行文本
    /// - Returns: (字段名, 字段值) 元组
    ///
    /// RFC 规范：fieldname:value 格式，冒号后的第一个空格可选（会被忽略）
    /// 示例：
    /// - "data:hello" → ("data", "hello")
    /// - "data: hello" → ("data", "hello")
    /// - "data:  two spaces" → ("data", " two spaces")
    private func parseField(from line: String) -> (Substring, Substring) {
        let scanner = Scanner(string: line)
        scanner.charactersToBeSkipped = nil
        
        if let name = scanner.scanUpToString(":"), !name.isEmpty {
            _ = scanner.scanString(":")
            let rest = line[scanner.currentIndex...]
            if rest.hasPrefix(" ") {
                // 跳过冒号后的第一个空格（RFC 规范）
                return (Substring(name), rest.dropFirst())
            }
            return (Substring(name), rest)
        }
        
        return (Substring(line), "")
    }
}
