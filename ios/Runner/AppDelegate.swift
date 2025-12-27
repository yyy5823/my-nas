import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // 启用远程控制事件接收
    // 这是 iOS Now Playing / 灵动岛显示的关键
    // 必须在 app 启动时调用，否则系统可能不会正确显示控制中心的媒体控件
    application.beginReceivingRemoteControlEvents()

    // 注册自定义的 Music Live Activity Channel
    // 用于支持个人开发者账号（不需要 Push Notification 能力）
    if let registrar = self.registrar(forPlugin: "MusicLiveActivityChannel") {
      MusicLiveActivityChannel.register(with: registrar)
    }

    // 注册原生日志桥接通道
    // 用于将 Swift 端日志（包括 Widget Extension）上传到 RabbitMQ
    if let registrar = self.registrar(forPlugin: "NativeLogBridge") {
      NativeLogBridge.register(with: registrar)
    }

    // 注册 Chromaprint 音频指纹通道
    if let registrar = self.registrar(forPlugin: "ChromaprintChannel") {
      ChromaprintChannel.register(with: registrar)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// App 即将终止时清理 Live Activity
  override func applicationWillTerminate(_ application: UIApplication) {
    super.applicationWillTerminate(application)

    // 结束所有 Live Activities
    if #available(iOS 16.1, *) {
      print("AppDelegate: App terminating, ending all Live Activities")
      MusicLiveActivityManager.shared.endAllActivities()
    }
  }

  /// App 进入后台时的处理
  /// 注意：不在这里结束 Live Activity，因为用户可能希望在后台继续显示
  /// 只有在 app 完全终止时才清理
  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    // 可以在这里添加日志或其他后台处理
    print("AppDelegate: App entered background")
  }
}
