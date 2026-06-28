/// AASSE SDK 便捷入口
///
/// 提供简洁的工厂方法创建 SSE 客户端
public struct AASSE {
    /// 使用默认配置创建 SSE 客户端
    /// - Parameter url: SSE 服务端 URL
    /// - Returns: AASSEClient 实例
    public static func createClient(url: URL) -> AASSEClient {
        AASSEClient(configuration: .init(url: url))
    }
    
    /// 使用自定义配置创建 SSE 客户端
    /// - Parameter configuration: 客户端配置
    /// - Returns: AASSEClient 实例
    public static func createClient(configuration: AASSEClient.Configuration) -> AASSEClient {
        AASSEClient(configuration: configuration)
    }
}
