import Cocoa
import FlutterMacOS
import AVFoundation

/**
 原生 AVPlayer 视图工厂 (macOS)

 用于在 Flutter 中嵌入原生 AVPlayerLayer
 */
class NativeAVPlayerViewFactory: NSObject, FlutterPlatformViewFactory {

    private weak var channel: NativeAVPlayerChannel?

    init(channel: NativeAVPlayerChannel) {
        self.channel = channel
        super.init()
    }

    func create(
        withViewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> NSView {
        return NativeAVPlayerPlatformView(
            viewIdentifier: viewId,
            arguments: args,
            channel: channel
        )
    }

    func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

/**
 原生 AVPlayer Platform View (macOS)

 在 Flutter widget 树中显示 AVPlayerLayer
 */
class NativeAVPlayerPlatformView: NSView {

    private let playerLayer: AVPlayerLayer
    private weak var controller: NativeAVPlayerController?

    /// 视频填充模式
    private var videoGravity: AVLayerVideoGravity = .resizeAspect

    init(
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        channel: NativeAVPlayerChannel?
    ) {
        // 创建播放器图层
        playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = videoGravity
        playerLayer.backgroundColor = NSColor.black.cgColor

        super.init(frame: .zero)

        // 设置视图属性
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        // 添加播放器图层
        layer?.addSublayer(playerLayer)

        // 解析参数
        if let argsDict = args as? [String: Any] {
            // 获取播放器 ID
            if let playerId = argsDict["playerId"] as? Int64,
               let playerController = channel?.getPlayer(playerId) {
                self.controller = playerController
                playerLayer.player = playerController.player

                // 注册 playerLayer 到控制器
                playerController.setupPlayerLayer(playerLayer)
            }

            // 设置填充模式
            if let fitMode = argsDict["fit"] as? String {
                switch fitMode {
                case "contain":
                    videoGravity = .resizeAspect
                case "cover":
                    videoGravity = .resizeAspectFill
                case "fill":
                    videoGravity = .resize
                default:
                    videoGravity = .resizeAspect
                }
                playerLayer.videoGravity = videoGravity
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        // 更新播放器图层大小
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    /// 更新视频填充模式
    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        videoGravity = gravity
        playerLayer.videoGravity = gravity
    }
}
