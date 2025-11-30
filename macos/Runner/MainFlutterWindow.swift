import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    // Set larger default window size for desktop
    if let screen = NSScreen.main {
      let screenFrame = screen.visibleFrame
      let windowWidth: CGFloat = min(1400, screenFrame.width * 0.85)
      let windowHeight: CGFloat = min(900, screenFrame.height * 0.85)
      let originX = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
      let originY = screenFrame.origin.y + (screenFrame.height - windowHeight) / 2
      let newFrame = NSRect(x: originX, y: originY, width: windowWidth, height: windowHeight)
      self.setFrame(newFrame, display: true)
    }
  }
}
