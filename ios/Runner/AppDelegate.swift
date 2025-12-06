import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // 注册自定义的 Music Live Activity Channel
    // 用于支持个人开发者账号（不需要 Push Notification 能力）
    if let registrar = self.registrar(forPlugin: "MusicLiveActivityChannel") {
      MusicLiveActivityChannel.register(with: registrar)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
