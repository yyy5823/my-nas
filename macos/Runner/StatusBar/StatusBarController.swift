import Cocoa
import FlutterMacOS

/// 状态栏控制器
class StatusBarController: NSObject {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var popoverContentView: StatusBarPopoverView?
    private var eventMonitor: Any?
    private var animationTimer: Timer?

    private var settings: MenuBarSettings = MenuBarSettings()
    private var currentMusicInfo: MusicInfo?
    private var currentLyric: String?
    private var isPlaying: Bool = false
    private var animationFrame: Int = 0

    weak var channel: FlutterMethodChannel?

    private override init() {
        super.init()
    }

    func initialize(settings: MenuBarSettings) {
        self.settings = settings

        if settings.enabled {
            setupStatusItem()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            updateButtonIcon(isPlaying: false)
            button.action = #selector(togglePopover)
            button.target = self
        }

        setupPopover()
    }

    private func setupPopover() {
        popover = NSPopover()
        popover?.behavior = .transient
        popover?.animates = true

        popoverContentView = StatusBarPopoverView(frame: NSRect(x: 0, y: 0, width: 320, height: 400))
        popoverContentView?.onControlAction = { [weak self] action in
            self?.channel?.invokeMethod("onControlAction", arguments: ["action": action])
        }

        let viewController = NSViewController()
        viewController.view = popoverContentView!
        popover?.contentViewController = viewController
        popover?.contentSize = NSSize(width: 320, height: 400)
    }

    @objc private func togglePopover() {
        guard let popover = popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
            removeEventMonitor()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            setupEventMonitor()
        }
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let popover = self?.popover, popover.isShown {
                popover.performClose(nil)
                self?.removeEventMonitor()
            }
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    func updatePlayingState(isPlaying: Bool) {
        self.isPlaying = isPlaying
        updateButtonIcon(isPlaying: isPlaying)
        popoverContentView?.updatePlayingState(isPlaying: isPlaying)

        if isPlaying && settings.showPlayingAnimation {
            startIconAnimation()
        } else {
            stopIconAnimation()
        }
    }

    func updateMusicInfo(info: MusicInfo) {
        currentMusicInfo = info
        popoverContentView?.updateMusicInfo(info: info)
        updatePlayingState(isPlaying: info.isPlaying)
    }

    func updateLyric(currentLine: String?, nextLine: String?) {
        currentLyric = currentLine
        popoverContentView?.updateLyric(currentLine: currentLine, nextLine: nextLine)
    }

    func setVisible(visible: Bool) {
        if visible {
            if statusItem == nil {
                setupStatusItem()
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
            stopIconAnimation()
        }
    }

    private func updateButtonIcon(isPlaying: Bool) {
        guard let button = statusItem?.button else { return }

        if #available(macOS 11.0, *) {
            let iconName = isPlaying ? "music.note" : "music.note"
            button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Music")

            // 播放时使用强调色
            if isPlaying {
                button.contentTintColor = .controlAccentColor
            } else {
                button.contentTintColor = nil
            }
        }
    }

    private func startIconAnimation() {
        guard settings.showPlayingAnimation else { return }

        stopIconAnimation()

        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.animateIcon()
        }
    }

    private func stopIconAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        animationFrame = 0
    }

    private func animateIcon() {
        guard let button = statusItem?.button else { return }

        animationFrame = (animationFrame + 1) % 3

        if #available(macOS 11.0, *) {
            let iconNames = ["music.note", "music.note.list", "music.quarternote.3"]
            let iconName = iconNames[animationFrame]
            button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Music")
        }
    }

    deinit {
        stopIconAnimation()
        removeEventMonitor()
    }
}

/// 状态栏弹窗内容视图
class StatusBarPopoverView: NSView {
    private var coverImageView: NSImageView!
    private var titleLabel: NSTextField!
    private var artistLabel: NSTextField!
    private var progressBar: NSProgressIndicator!
    private var currentTimeLabel: NSTextField!
    private var totalTimeLabel: NSTextField!
    private var prevButton: NSButton!
    private var playPauseButton: NSButton!
    private var nextButton: NSButton!
    private var lyricLabel: NSTextField!

    private var isPlaying: Bool = false

    var onControlAction: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true

        // 封面图片
        coverImageView = NSImageView(frame: NSRect(x: 20, y: frame.height - 200, width: 180, height: 180))
        coverImageView.imageScaling = .scaleProportionallyUpOrDown
        coverImageView.wantsLayer = true
        coverImageView.layer?.cornerRadius = 8
        coverImageView.layer?.masksToBounds = true
        coverImageView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        addSubview(coverImageView)

        // 标题
        titleLabel = createLabel(fontSize: 16, bold: true)
        titleLabel.frame = NSRect(x: 210, y: frame.height - 60, width: 100, height: 24)
        titleLabel.stringValue = "未在播放"
        addSubview(titleLabel)

        // 艺术家
        artistLabel = createLabel(fontSize: 13, bold: false)
        artistLabel.frame = NSRect(x: 210, y: frame.height - 85, width: 100, height: 20)
        artistLabel.alphaValue = 0.7
        addSubview(artistLabel)

        // 进度条
        progressBar = NSProgressIndicator(frame: NSRect(x: 20, y: frame.height - 230, width: frame.width - 40, height: 4))
        progressBar.style = .bar
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.doubleValue = 0
        addSubview(progressBar)

        // 时间标签
        currentTimeLabel = createLabel(fontSize: 11, bold: false)
        currentTimeLabel.frame = NSRect(x: 20, y: frame.height - 250, width: 50, height: 16)
        currentTimeLabel.stringValue = "0:00"
        currentTimeLabel.alphaValue = 0.5
        addSubview(currentTimeLabel)

        totalTimeLabel = createLabel(fontSize: 11, bold: false)
        totalTimeLabel.frame = NSRect(x: frame.width - 70, y: frame.height - 250, width: 50, height: 16)
        totalTimeLabel.alignment = .right
        totalTimeLabel.stringValue = "0:00"
        totalTimeLabel.alphaValue = 0.5
        addSubview(totalTimeLabel)

        // 控制按钮
        let buttonY = frame.height - 300
        let buttonWidth: CGFloat = 44
        let buttonSpacing: CGFloat = 20
        let totalButtonWidth = buttonWidth * 3 + buttonSpacing * 2
        let buttonStartX = (frame.width - totalButtonWidth) / 2

        prevButton = createControlButton(imageName: "backward.fill", x: buttonStartX)
        prevButton.frame.origin.y = buttonY
        prevButton.target = self
        prevButton.action = #selector(prevButtonClicked)
        addSubview(prevButton)

        playPauseButton = createControlButton(imageName: "play.fill", x: buttonStartX + buttonWidth + buttonSpacing)
        playPauseButton.frame.origin.y = buttonY
        playPauseButton.target = self
        playPauseButton.action = #selector(playPauseButtonClicked)
        addSubview(playPauseButton)

        nextButton = createControlButton(imageName: "forward.fill", x: buttonStartX + (buttonWidth + buttonSpacing) * 2)
        nextButton.frame.origin.y = buttonY
        nextButton.target = self
        nextButton.action = #selector(nextButtonClicked)
        addSubview(nextButton)

        // 歌词
        lyricLabel = createLabel(fontSize: 12, bold: false)
        lyricLabel.frame = NSRect(x: 20, y: 20, width: frame.width - 40, height: 60)
        lyricLabel.alignment = .center
        lyricLabel.maximumNumberOfLines = 2
        lyricLabel.alphaValue = 0.6
        addSubview(lyricLabel)
    }

    private func createLabel(fontSize: CGFloat, bold: Bool) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: fontSize, weight: bold ? .semibold : .regular)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func createControlButton(imageName: String, x: CGFloat) -> NSButton {
        let button = NSButton(frame: NSRect(x: x, y: 0, width: 44, height: 44))
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 22

        if #available(macOS 11.0, *) {
            button.image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)
            button.contentTintColor = .labelColor
            button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        }

        return button
    }

    func updateMusicInfo(info: MusicInfo) {
        titleLabel.stringValue = info.title.isEmpty ? "未在播放" : info.title
        artistLabel.stringValue = info.artist

        if let image = info.coverImage {
            coverImageView.image = image
        } else {
            coverImageView.image = nil
        }

        progressBar.doubleValue = info.progress
        currentTimeLabel.stringValue = info.currentTimeText
        totalTimeLabel.stringValue = info.totalTimeText
    }

    func updatePlayingState(isPlaying: Bool) {
        self.isPlaying = isPlaying

        if #available(macOS 11.0, *) {
            let iconName = isPlaying ? "pause.fill" : "play.fill"
            playPauseButton.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
        }
    }

    func updateLyric(currentLine: String?, nextLine: String?) {
        var lyricText = ""
        if let current = currentLine, !current.isEmpty {
            lyricText = current
            if let next = nextLine, !next.isEmpty {
                lyricText += "\n" + next
            }
        }
        lyricLabel.stringValue = lyricText
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
}
