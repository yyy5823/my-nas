import ActivityKit
import Foundation

/// 音乐播放器 Live Activity 的属性定义
/// 用于在灵动岛和锁屏上显示音乐播放状态
struct MusicActivityAttributes: ActivityAttributes {
    /// 动态内容状态 - 会随播放状态变化
    public struct ContentState: Codable, Hashable {
        /// 是否正在播放
        var isPlaying: Bool
        /// 当前播放进度 (0.0 - 1.0)
        var progress: Double
        /// 当前播放时间（秒）
        var currentTime: Int
        /// 总时长（秒）
        var totalTime: Int
    }

    // 必需的类型别名，用于 Live Activity 显示
    public typealias LiveDeliveryData = ContentState

    /// 歌曲标题
    var title: String
    /// 艺术家名称
    var artist: String
    /// 专辑名称
    var album: String
    /// 封面图片的 App Group 共享路径 key
    var coverImageKey: String?
}
