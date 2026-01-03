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

        // 创建容器视图（用于正确分层）
        let containerView = NSView(frame: window.contentView!.bounds)
        containerView.wantsLayer = true
        containerView.autoresizingMask = [.width, .height]

        // 直接添加内容视图（完全透明背景，只显示文字）
        contentView = DesktopLyricView(frame: containerView.bounds, settings: settings)
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
        contentView?.onControlAction = { [weak self] action in
            self?.channel?.invokeMethod("onControlAction", arguments: ["action": action])
        }
        containerView.addSubview(contentView!)

        // 设置窗口内容
        window.contentView = containerView
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
            // 使用更高的窗口层级，确保在全屏应用之上也能显示
            // .floating (3) < .statusBar (25) < .modalPanel (8)
            // 使用 statusBar 级别确保歌词窗口始终可见
            window?.level = .statusBar
        } else {
            window?.level = .floating
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

    // 右上角控制按钮
    private var closeButton: NSButton!
    private var lockButton: NSButton!
    private var controlsContainer: NSView!

    // 播放控制按钮
    private var playControlsContainer: NSView!
    private var prevButton: NSButton!
    private var playPauseButton: NSButton!
    private var nextButton: NSButton!

    private var settings: DesktopLyricSettings
    private var isPlaying: Bool = false
    private var isHovering: Bool = false

    var onClose: (() -> Void)?
    var onLockToggle: ((Bool) -> Void)?
    var onControlAction: ((String) -> Void)?

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
        // 完全透明背景
        layer?.backgroundColor = NSColor.clear.cgColor

        // 当前歌词（使用高亮色）
        currentLyricLabel = createLabel(fontSize: settings.fontSize, bold: true, color: settings.highlightColor)
        addSubview(currentLyricLabel)

        // 翻译歌词
        translationLabel = createLabel(fontSize: settings.fontSize * 0.7, bold: false)
        translationLabel.alphaValue = 0.7
        addSubview(translationLabel)

        // 下一行歌词
        nextLineLabel = createLabel(fontSize: settings.fontSize * 0.6, bold: false)
        nextLineLabel.alphaValue = 0.5
        addSubview(nextLineLabel)

        // 右上角控制按钮容器
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

        // 左侧播放控制按钮容器
        let playControlsWidth: CGFloat = 90
        playControlsContainer = NSView(frame: NSRect(x: 12, y: (bounds.height - 28) / 2, width: playControlsWidth, height: 28))
        playControlsContainer.autoresizingMask = [.maxXMargin, .minYMargin, .maxYMargin]
        playControlsContainer.isHidden = true
        addSubview(playControlsContainer)

        // 上一首按钮
        prevButton = createPlayControlButton(imageName: "backward.fill")
        prevButton.frame = NSRect(x: 0, y: 0, width: 28, height: 28)
        prevButton.target = self
        prevButton.action = #selector(prevButtonClicked)
        playControlsContainer.addSubview(prevButton)

        // 播放/暂停按钮
        playPauseButton = createPlayControlButton(imageName: "play.fill")
        playPauseButton.frame = NSRect(x: 31, y: 0, width: 28, height: 28)
        playPauseButton.target = self
        playPauseButton.action = #selector(playPauseButtonClicked)
        playControlsContainer.addSubview(playPauseButton)

        // 下一首按钮
        nextButton = createPlayControlButton(imageName: "forward.fill")
        nextButton.frame = NSRect(x: 62, y: 0, width: 28, height: 28)
        nextButton.target = self
        nextButton.action = #selector(nextButtonClicked)
        playControlsContainer.addSubview(nextButton)

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

    private func createLabel(fontSize: CGFloat, bold: Bool, color: NSColor? = nil) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: fontSize, weight: bold ? .semibold : .regular)
        label.textColor = color ?? settings.textColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.truncatesLastVisibleLine = true

        // 添加更强的阴影以确保在任何背景上可见
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.9)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 8
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

    private func createPlayControlButton(imageName: String) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 14
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor

        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            button.image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
            button.contentTintColor = .white
        }

        return button
    }

    private func updateLayout() {
        let padding: CGFloat = 24
        let labelWidth = bounds.width - padding * 2
        let spacing: CGFloat = 4

        // 计算所有可见元素的总高度
        let currentHeight = settings.fontSize + 4
        let translationHeight = settings.showTranslation ? (settings.fontSize * 0.7 + 4) : 0
        let nextLineHeight = settings.showNextLine ? (settings.fontSize * 0.6 + 4) : 0

        var totalHeight = currentHeight
        if settings.showTranslation {
            totalHeight += translationHeight + spacing
        }
        if settings.showNextLine {
            totalHeight += nextLineHeight + spacing
        }

        // 从顶部开始布局（macOS Y 坐标从底部开始，所以需要从 bounds.height 减）
        // 垂直居中：起始 Y 位置 = (总高度 - 内容高度) / 2 + 内容高度
        var yPos = (bounds.height + totalHeight) / 2

        // 当前歌词（最上方）
        yPos -= currentHeight
        currentLyricLabel.frame = NSRect(
            x: padding,
            y: yPos,
            width: labelWidth,
            height: currentHeight
        )

        // 翻译歌词（在当前歌词下方）
        if settings.showTranslation {
            yPos -= (translationHeight + spacing)
            translationLabel.frame = NSRect(
                x: padding,
                y: yPos,
                width: labelWidth,
                height: translationHeight
            )
            translationLabel.isHidden = false
        } else {
            translationLabel.isHidden = true
        }

        // 下一行歌词（最下方）
        if settings.showNextLine {
            yPos -= (nextLineHeight + spacing)
            nextLineLabel.frame = NSRect(
                x: padding,
                y: yPos,
                width: labelWidth,
                height: nextLineHeight
            )
            nextLineLabel.isHidden = false
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
        updatePlayPauseButtonImage()
    }

    func updateSettings(settings: DesktopLyricSettings) {
        self.settings = settings

        currentLyricLabel.font = NSFont.systemFont(ofSize: settings.fontSize, weight: .semibold)
        currentLyricLabel.textColor = settings.highlightColor  // 当前歌词使用高亮色
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

    @objc private func prevButtonClicked() {
        onControlAction?("previous")
    }

    @objc private func playPauseButtonClicked() {
        onControlAction?(isPlaying ? "pause" : "play")
    }

    @objc private func nextButtonClicked() {
        onControlAction?("next")
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            controlsContainer.animator().isHidden = false
            controlsContainer.animator().alphaValue = 1.0
            playControlsContainer.animator().isHidden = false
            playControlsContainer.animator().alphaValue = 1.0
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            controlsContainer.animator().alphaValue = 0.0
            playControlsContainer.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            self?.controlsContainer.isHidden = true
            self?.playControlsContainer.isHidden = true
        }
    }

    private func updatePlayPauseButtonImage() {
        if #available(macOS 11.0, *) {
            let imageName = isPlaying ? "pause.fill" : "play.fill"
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            playPauseButton.image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        }
    }
}
