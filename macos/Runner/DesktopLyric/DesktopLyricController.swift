import Cocoa
import FlutterMacOS

/// 桌面歌词窗口控制器
class DesktopLyricController: NSObject, NSWindowDelegate {
    static let shared = DesktopLyricController()

    private var window: NSWindow?
    private var contentView: DesktopLyricView?
    private var settings: DesktopLyricSettings = DesktopLyricSettings()

    weak var channel: FlutterMethodChannel?

    private override init() {
        super.init()
    }

    func initialize(settings: DesktopLyricSettings) {
        self.settings = settings
    }

    func show() {
        if window == nil {
            createWindow()
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    func updateLyric(currentLine: LyricLine?, nextLine: LyricLine?, isPlaying: Bool) {
        contentView?.updateLyric(currentLine: currentLine, nextLine: nextLine, isPlaying: isPlaying)
    }

    func updatePlayingState(isPlaying: Bool) {
        contentView?.updatePlayingState(isPlaying: isPlaying)
    }

    func setPosition(_ position: NSPoint) {
        window?.setFrameOrigin(position)
    }

    func getPosition() -> NSPoint? {
        return window?.frame.origin
    }

    func updateSettings(settings: DesktopLyricSettings) {
        self.settings = settings
        contentView?.updateSettings(settings: settings)
        updateWindowProperties()
    }

    private func createWindow() {
        // 计算初始位置
        var origin: NSPoint
        if let x = settings.windowX, let y = settings.windowY {
            origin = NSPoint(x: x, y: y)
        } else {
            // 默认在屏幕底部中央
            origin = getDefaultPosition()
        }

        let frame = NSRect(
            x: origin.x,
            y: origin.y,
            width: settings.windowWidth,
            height: settings.windowHeight
        )

        // 创建无边框透明窗口
        window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        guard let window = window else { return }

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = !settings.lockPosition
        window.delegate = self

        // 设置窗口层级
        updateWindowLevel()

        // 设置窗口行为（在所有桌面可见）
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        // 创建内容视图
        contentView = DesktopLyricView(frame: window.contentView!.bounds, settings: settings)
        contentView?.autoresizingMask = [.width, .height]
        contentView?.onClose = { [weak self] in
            self?.hide()
            self?.channel?.invokeMethod("onWindowClosed", arguments: nil)
        }
        contentView?.onLockToggle = { [weak self] isLocked in
            self?.settings.lockPosition = isLocked
            self?.window?.isMovableByWindowBackground = !isLocked
            self?.channel?.invokeMethod("onLockToggled", arguments: ["isLocked": isLocked])
        }

        window.contentView = contentView

        // 添加毛玻璃效果
        addVisualEffectView()
    }

    private func addVisualEffectView() {
        guard let contentView = window?.contentView else { return }

        let visualEffectView = NSVisualEffectView(frame: contentView.bounds)
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 12
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.autoresizingMask = [.width, .height]

        contentView.addSubview(visualEffectView, positioned: .below, relativeTo: nil)
    }

    private func getDefaultPosition() -> NSPoint {
        guard let screen = NSScreen.main else {
            return NSPoint(x: 100, y: 100)
        }

        let screenFrame = screen.visibleFrame
        let x = (screenFrame.width - settings.windowWidth) / 2 + screenFrame.origin.x
        let y = screenFrame.origin.y + 100

        return NSPoint(x: x, y: y)
    }

    private func updateWindowLevel() {
        if settings.alwaysOnTop {
            window?.level = .floating
        } else {
            window?.level = .normal
        }
    }

    private func updateWindowProperties() {
        window?.isMovableByWindowBackground = !settings.lockPosition
        updateWindowLevel()
        window?.alphaValue = settings.opacity
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard let origin = window?.frame.origin else { return }
        channel?.invokeMethod("onPositionChanged", arguments: ["x": origin.x, "y": origin.y])
    }
}

/// 桌面歌词内容视图
class DesktopLyricView: NSView {
    private var currentLyricLabel: NSTextField!
    private var translationLabel: NSTextField!
    private var nextLineLabel: NSTextField!
    private var closeButton: NSButton!
    private var lockButton: NSButton!
    private var controlsContainer: NSView!

    private var settings: DesktopLyricSettings
    private var isPlaying: Bool = false
    private var isHovering: Bool = false

    var onClose: (() -> Void)?
    var onLockToggle: ((Bool) -> Void)?

    init(frame frameRect: NSRect, settings: DesktopLyricSettings) {
        self.settings = settings
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        self.settings = DesktopLyricSettings()
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true

        // 当前歌词
        currentLyricLabel = createLabel(fontSize: settings.fontSize, bold: true)
        addSubview(currentLyricLabel)

        // 翻译歌词
        translationLabel = createLabel(fontSize: settings.fontSize * 0.7, bold: false)
        translationLabel.alphaValue = 0.7
        addSubview(translationLabel)

        // 下一行歌词
        nextLineLabel = createLabel(fontSize: settings.fontSize * 0.6, bold: false)
        nextLineLabel.alphaValue = 0.4
        addSubview(nextLineLabel)

        // 控制按钮容器
        controlsContainer = NSView(frame: NSRect(x: bounds.width - 60, y: bounds.height - 30, width: 50, height: 24))
        controlsContainer.autoresizingMask = [.minXMargin, .minYMargin]
        controlsContainer.isHidden = true
        addSubview(controlsContainer)

        // 锁定按钮
        lockButton = createControlButton(imageName: settings.lockPosition ? "lock.fill" : "lock.open.fill")
        lockButton.frame = NSRect(x: 0, y: 0, width: 24, height: 24)
        lockButton.target = self
        lockButton.action = #selector(lockButtonClicked)
        controlsContainer.addSubview(lockButton)

        // 关闭按钮
        closeButton = createControlButton(imageName: "xmark")
        closeButton.frame = NSRect(x: 26, y: 0, width: 24, height: 24)
        closeButton.target = self
        closeButton.action = #selector(closeButtonClicked)
        controlsContainer.addSubview(closeButton)

        // 添加鼠标追踪
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)

        updateLayout()
    }

    private func createLabel(fontSize: CGFloat, bold: Bool) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: fontSize, weight: bold ? .semibold : .regular)
        label.textColor = settings.textColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.truncatesLastVisibleLine = true

        // 添加阴影
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = 4
        label.shadow = shadow

        return label
    }

    private func createControlButton(imageName: String) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 4
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor

        if #available(macOS 11.0, *) {
            button.image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)
            button.contentTintColor = .white
        }

        return button
    }

    private func updateLayout() {
        let padding: CGFloat = 48
        let labelWidth = bounds.width - padding * 2
        let centerY = bounds.height / 2

        // 当前歌词居中
        currentLyricLabel.frame = NSRect(
            x: padding,
            y: centerY - settings.fontSize / 2,
            width: labelWidth,
            height: settings.fontSize + 4
        )

        // 翻译歌词在下方
        if settings.showTranslation {
            translationLabel.isHidden = false
            translationLabel.frame = NSRect(
                x: padding,
                y: currentLyricLabel.frame.minY - settings.fontSize * 0.7 - 4,
                width: labelWidth,
                height: settings.fontSize * 0.7 + 4
            )
        } else {
            translationLabel.isHidden = true
        }

        // 下一行歌词在更下方
        if settings.showNextLine {
            nextLineLabel.isHidden = false
            let baseY = settings.showTranslation ? translationLabel.frame.minY : currentLyricLabel.frame.minY
            nextLineLabel.frame = NSRect(
                x: padding,
                y: baseY - settings.fontSize * 0.6 - 8,
                width: labelWidth,
                height: settings.fontSize * 0.6 + 4
            )
        } else {
            nextLineLabel.isHidden = true
        }
    }

    func updateLyric(currentLine: LyricLine?, nextLine: LyricLine?, isPlaying: Bool) {
        self.isPlaying = isPlaying

        if let current = currentLine {
            currentLyricLabel.stringValue = current.text
            if settings.showTranslation && current.hasTranslation {
                translationLabel.stringValue = current.translation!
                translationLabel.isHidden = false
            } else {
                translationLabel.stringValue = ""
                translationLabel.isHidden = true
            }
        } else {
            currentLyricLabel.stringValue = isPlaying ? "♪ ♪ ♪" : "暂无歌词"
            translationLabel.stringValue = ""
            translationLabel.isHidden = true
        }

        if settings.showNextLine, let next = nextLine {
            nextLineLabel.stringValue = next.text
            nextLineLabel.isHidden = false
        } else {
            nextLineLabel.stringValue = ""
            nextLineLabel.isHidden = true
        }
    }

    func updatePlayingState(isPlaying: Bool) {
        self.isPlaying = isPlaying
    }

    func updateSettings(settings: DesktopLyricSettings) {
        self.settings = settings

        currentLyricLabel.font = NSFont.systemFont(ofSize: settings.fontSize, weight: .semibold)
        currentLyricLabel.textColor = settings.textColor
        translationLabel.font = NSFont.systemFont(ofSize: settings.fontSize * 0.7, weight: .regular)
        translationLabel.textColor = settings.textColor
        nextLineLabel.font = NSFont.systemFont(ofSize: settings.fontSize * 0.6, weight: .regular)
        nextLineLabel.textColor = settings.textColor

        updateLockButtonImage()
        updateLayout()
    }

    private func updateLockButtonImage() {
        if #available(macOS 11.0, *) {
            lockButton.image = NSImage(
                systemSymbolName: settings.lockPosition ? "lock.fill" : "lock.open.fill",
                accessibilityDescription: nil
            )
        }
    }

    @objc private func closeButtonClicked() {
        onClose?()
    }

    @objc private func lockButtonClicked() {
        settings.lockPosition = !settings.lockPosition
        updateLockButtonImage()
        onLockToggle?(settings.lockPosition)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            controlsContainer.animator().isHidden = false
            controlsContainer.animator().alphaValue = 1.0
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            controlsContainer.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            self?.controlsContainer.isHidden = true
        }
    }
}
