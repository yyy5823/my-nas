import Flutter
import UIKit
import AVFoundation

/**
 原生 AVPlayer 视图工厂

 用于在 Flutter 中嵌入原生 AVPlayerLayer
 */
class NativeAVPlayerViewFactory: NSObject, FlutterPlatformViewFactory {

    private weak var channel: NativeAVPlayerChannel?

    init(channel: NativeAVPlayerChannel) {
        self.channel = channel
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return NativeAVPlayerPlatformView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            channel: channel
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

/**
 原生 AVPlayer Platform View

 在 Flutter widget 树中显示 AVPlayerLayer
 */
class NativeAVPlayerPlatformView: NSObject, FlutterPlatformView {

    private let containerView: UIView
    private let playerLayer: AVPlayerLayer
    private weak var controller: NativeAVPlayerController?

    /// 视频填充模式
    private var videoGravity: AVLayerVideoGravity = .resizeAspect

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        channel: NativeAVPlayerChannel?
    ) {
        // 创建容器视图
        containerView = UIView(frame: frame)
        containerView.backgroundColor = .black
        containerView.clipsToBounds = true

        // 创建播放器图层
        playerLayer = AVPlayerLayer()
        playerLayer.frame = containerView.bounds
        playerLayer.videoGravity = videoGravity
        playerLayer.backgroundColor = UIColor.black.cgColor

        super.init()

        // 解析参数
        if let argsDict = args as? [String: Any] {
            // 获取播放器 ID
            if let playerId = argsDict["playerId"] as? Int64,
               let playerController = channel?.getPlayer(playerId) {
                self.controller = playerController
                playerLayer.player = playerController.player

                // 注册 playerLayer 到控制器（用于画中画）
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

        // 添加图层
        containerView.layer.addSublayer(playerLayer)

        // 监听布局变化
        containerView.addObserver(self, forKeyPath: "bounds", options: [.new], context: nil)
    }

    deinit {
        containerView.removeObserver(self, forKeyPath: "bounds")
    }

    func view() -> UIView {
        return containerView
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == "bounds" {
            // 更新播放器图层大小
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = containerView.bounds
            CATransaction.commit()
        }
    }
}

// MARK: - 扩展：支持安全区域

extension NativeAVPlayerPlatformView {
    /// 更新视频填充模式
    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        videoGravity = gravity
        playerLayer.videoGravity = gravity
    }
}
