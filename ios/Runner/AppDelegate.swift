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

    // 注册 Widget 数据通道
    // 用于将 Flutter 数据同步到 Home Screen Widgets
    if let registrar = self.registrar(forPlugin: "WidgetDataChannel") {
      WidgetDataChannel.register(with: registrar)
    }

    // 注册显示能力检测通道 (HDR)
    if let registrar = self.registrar(forPlugin: "DisplayCapabilityChannel") {
      DisplayCapabilityChannel.register(with: registrar)
    }

    // 注册音频能力检测通道 (直通)
    if let registrar = self.registrar(forPlugin: "AudioCapabilityChannel") {
      AudioCapabilityChannel.register(with: registrar)
    }

    // 注册原生模糊视图 Platform View
    // 用于实现真正的 iOS 系统级毛玻璃效果
    if let registrar = self.registrar(forPlugin: "NativeBlurViewPlugin") {
      NativeBlurViewPlugin.register(with: registrar)
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
    print("AppDelegate: App entered background")

    // 重要：重新启用远程控制事件接收
    // 当 app 从前台返回后台时，需要重新"声明"我们是活跃的音频播放器
    // 这有助于 iOS 在灵动岛中正确显示 Now Playing 信息
    application.beginReceivingRemoteControlEvents()
    print("AppDelegate: Re-enabled remote control events")
  }

  /// App 即将返回前台
  override func applicationWillEnterForeground(_ application: UIApplication) {
    super.applicationWillEnterForeground(application)
    print("AppDelegate: App will enter foreground")
  }

  /// App 已激活（返回前台）
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    print("AppDelegate: App did become active")

    // 确保远程控制事件仍然激活
    application.beginReceivingRemoteControlEvents()
  }
}
