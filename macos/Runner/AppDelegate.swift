import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    // 注册自定义 MethodChannel 插件
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return
    }

    // 注册 Widget 数据通道
    _ = WidgetDataChannel(messenger: controller.engine.binaryMessenger)

    // 注册显示能力检测通道 (HDR)
    DisplayCapabilityChannel.register(
      with: controller.engine.registrar(forPlugin: "DisplayCapabilityChannel")
    )

    // 注册音频能力检测通道 (直通)
    AudioCapabilityChannel.register(
      with: controller.engine.registrar(forPlugin: "AudioCapabilityChannel")
    )

    // 注册原生模糊视图 Platform View
    // 用于实现真正的 macOS 系统级毛玻璃效果
    NativeBlurViewPlugin.register(
      with: controller.engine.registrar(forPlugin: "NativeBlurViewPlugin")
    )

    // 注册原生 AVPlayer 通道
    // 用于播放 Dolby Vision 等需要原生支持的视频格式
    NativeAVPlayerChannel.register(
      with: controller.engine.registrar(forPlugin: "NativeAVPlayerChannel")
    )

    // 注册桌面歌词通道
    // 用于在独立窗口显示歌词
    DesktopLyricChannel.register(
      with: controller.engine.registrar(forPlugin: "DesktopLyricChannel")
    )

    // 注册状态栏播放器通道
    // 用于在菜单栏显示迷你播放器
    StatusBarChannel.register(
      with: controller.engine.registrar(forPlugin: "StatusBarChannel")
    )
  }
}
