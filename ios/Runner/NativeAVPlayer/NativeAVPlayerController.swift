import Foundation
import AVFoundation
import AVKit
import UIKit

/**
 AVPlayer 控制器

 封装 AVPlayer 提供完整的播放控制功能
 */
class NativeAVPlayerController: NSObject {

    let playerId: Int64
    let player: AVPlayer
    private(set) var playerItem: AVPlayerItem?

    /// 事件回调
    private let eventCallback: ([String: Any]) -> Void

    /// 观察器
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var durationObserver: NSKeyValueObservation?
    private var bufferObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?

    /// 画中画控制器
    private var pipController: AVPictureInPictureController?
    private var pipPossibleObserver: NSKeyValueObservation?

    /// 当前状态
    private var isPlaying = false
    private var isBuffering = false
    private var currentPosition: Int64 = 0
    private var totalDuration: Int64 = 0
    private var currentVolume: Float = 1.0
    private var currentSpeed: Float = 1.0
    private var videoWidth: Int = 0
    private var videoHeight: Int = 0

    /// PlayerLayer (用于视图和画中画)
    private(set) var playerLayer: AVPlayerLayer?

    init(playerId: Int64, eventCallback: @escaping ([String: Any]) -> Void) {
        self.playerId = playerId
        self.player = AVPlayer()
        self.eventCallback = eventCallback
        super.init()

        setupRateObserver()
    }

    // MARK: - 生命周期

    func open(url urlString: String, headers: [String: String]?, completion: @escaping (Error?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(NSError(domain: "NativeAVPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }

        // 清理之前的 playerItem
        cleanupPlayerItem()

        // 配置 HTTP 请求头
        var assetOptions: [String: Any] = [:]
        if let headers = headers, !headers.isEmpty {
            assetOptions["AVURLAssetHTTPHeaderFieldsKey"] = headers
        }

        // 创建 Asset 并配置 Dolby Vision 支持
        let asset = AVURLAsset(url: url, options: assetOptions)

        // 异步加载资源
        asset.loadValuesAsynchronously(forKeys: ["playable", "tracks", "duration"]) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }

                var error: NSError?
                let status = asset.statusOfValue(forKey: "playable", error: &error)

                if status == .failed {
                    completion(error ?? NSError(domain: "NativeAVPlayer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to load asset"]))
                    return
                }

                // 创建 PlayerItem
                self.playerItem = AVPlayerItem(asset: asset)
                self.player.replaceCurrentItem(with: self.playerItem)

                // 设置观察器
                self.setupObservers()

                // 获取视频尺寸
                self.updateVideoSize()

                // 发送初始化事件
                self.sendEvent("initialized", data: [:])

                completion(nil)
            }
        }
    }

    func play() {
        player.play()
        player.rate = currentSpeed
    }

    func pause() {
        player.pause()
    }

    func seek(to positionMs: Int64) {
        let time = CMTime(value: positionMs, timescale: 1000)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.sendEvent("seekCompleted", data: [:])
        }
    }

    func setSpeed(_ speed: Float) {
        currentSpeed = speed
        if isPlaying {
            player.rate = speed
        }
    }

    func setVolume(_ volume: Float) {
        currentVolume = volume
        player.volume = volume
    }

    func dispose() {
        cleanupPlayerItem()
        cleanupPiP()
        player.replaceCurrentItem(with: nil)
    }

    // MARK: - 音轨管理

    func getAudioTracks() -> [[String: Any]] {
        guard let item = playerItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else {
            return []
        }

        return group.options.enumerated().map { index, option in
            var track: [String: Any] = [
                "index": index,
                "id": option.displayName,
                "title": option.displayName
            ]

            if let locale = option.locale {
                track["language"] = locale.identifier
            }

            return track
        }
    }

    func setAudioTrack(index: Int) {
        guard let item = playerItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible),
              index >= 0 && index < group.options.count else {
            return
        }

        item.select(group.options[index], in: group)
        sendEvent("audioTrackChanged", data: ["index": index])
    }

    // MARK: - 字幕管理

    func getSubtitleTracks() -> [[String: Any]] {
        guard let item = playerItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else {
            return []
        }

        return group.options.enumerated().map { index, option in
            var track: [String: Any] = [
                "index": index,
                "id": option.displayName,
                "title": option.displayName
            ]

            if let locale = option.locale {
                track["language"] = locale.identifier
            }

            // 检查是否是强制字幕
            if option.hasMediaCharacteristic(.containsOnlyForcedSubtitles) {
                track["isForced"] = true
            }

            return track
        }
    }

    func setSubtitleTrack(index: Int) {
        guard let item = playerItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible),
              index >= 0 && index < group.options.count else {
            return
        }

        item.select(group.options[index], in: group)
        sendEvent("subtitleTrackChanged", data: ["index": index])
    }

    func disableSubtitle() {
        guard let item = playerItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else {
            return
        }

        item.select(nil, in: group)
        sendEvent("subtitleTrackChanged", data: ["index": -1])
    }

    // MARK: - 状态获取

    func getState() -> [String: Any] {
        return [
            "isPlaying": isPlaying,
            "isBuffering": isBuffering,
            "position": currentPosition,
            "duration": totalDuration,
            "volume": currentVolume,
            "speed": currentSpeed,
            "width": videoWidth,
            "height": videoHeight,
            "isPiPActive": pipController?.isPictureInPictureActive ?? false
        ]
    }

    // MARK: - 截图

    func screenshot(completion: @escaping (FlutterStandardTypedData?) -> Void) {
        guard let item = playerItem else {
            completion(nil)
            return
        }

        let time = item.currentTime()
        let imageGenerator = AVAssetImageGenerator(asset: item.asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero

        imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, _ in
            DispatchQueue.main.async {
                guard let cgImage = cgImage else {
                    completion(nil)
                    return
                }

                let uiImage = UIImage(cgImage: cgImage)
                if let pngData = uiImage.pngData() {
                    completion(FlutterStandardTypedData(bytes: pngData))
                } else {
                    completion(nil)
                }
            }
        }
    }

    // MARK: - 画中画

    func setupPlayerLayer(_ layer: AVPlayerLayer) {
        self.playerLayer = layer
        layer.player = player

        // 配置画中画
        if AVPictureInPictureController.isPictureInPictureSupported() {
            pipController = AVPictureInPictureController(playerLayer: layer)
            pipController?.delegate = self

            pipPossibleObserver = pipController?.observe(\.isPictureInPicturePossible) { [weak self] controller, _ in
                self?.sendEvent("pipPossibleChanged", data: ["possible": controller.isPictureInPicturePossible])
            }
        }
    }

    func enterPictureInPicture() -> Bool {
        guard let pip = pipController, pip.isPictureInPicturePossible else {
            return false
        }
        pip.startPictureInPicture()
        return true
    }

    func exitPictureInPicture() -> Bool {
        guard let pip = pipController, pip.isPictureInPictureActive else {
            return false
        }
        pip.stopPictureInPicture()
        return true
    }

    // MARK: - 私有方法

    private func setupObservers() {
        guard let item = playerItem else { return }

        // 状态观察
        statusObserver = item.observe(\.status) { [weak self] item, _ in
            self?.handleStatusChange(item.status)
        }

        // 时长观察
        durationObserver = item.observe(\.duration) { [weak self] item, _ in
            guard let self = self else { return }
            if item.duration.isValid && !item.duration.isIndefinite {
                self.totalDuration = Int64(CMTimeGetSeconds(item.duration) * 1000)
                self.sendEvent("durationChanged", data: ["duration": self.totalDuration])
            }
        }

        // 缓冲观察
        bufferObserver = item.observe(\.isPlaybackBufferEmpty) { [weak self] item, _ in
            self?.handleBufferingChange(item.isPlaybackBufferEmpty)
        }

        // 时间观察 (30Hz)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }
            self.currentPosition = Int64(CMTimeGetSeconds(time) * 1000)
            self.sendEvent("positionChanged", data: ["position": self.currentPosition])
        }

        // 播放完成通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
    }

    private func setupRateObserver() {
        rateObserver = player.observe(\.rate) { [weak self] player, _ in
            guard let self = self else { return }
            let newIsPlaying = player.rate > 0
            if newIsPlaying != self.isPlaying {
                self.isPlaying = newIsPlaying
                self.sendEvent("playingChanged", data: ["isPlaying": newIsPlaying])
            }
        }
    }

    private func handleStatusChange(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            sendEvent("ready", data: [:])
        case .failed:
            let error = playerItem?.error?.localizedDescription ?? "Unknown error"
            sendEvent("error", data: ["message": error])
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func handleBufferingChange(_ isEmpty: Bool) {
        if isEmpty != isBuffering {
            isBuffering = isEmpty
            sendEvent("bufferingChanged", data: ["isBuffering": isEmpty])
        }
    }

    @objc private func playerDidFinishPlaying() {
        sendEvent("completed", data: [:])
    }

    private func updateVideoSize() {
        guard let item = playerItem else { return }

        for track in item.asset.tracks(withMediaType: .video) {
            let size = track.naturalSize.applying(track.preferredTransform)
            videoWidth = Int(abs(size.width))
            videoHeight = Int(abs(size.height))

            sendEvent("videoSizeChanged", data: [
                "width": videoWidth,
                "height": videoHeight
            ])
            break
        }
    }

    private func cleanupPlayerItem() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }

        statusObserver?.invalidate()
        statusObserver = nil

        durationObserver?.invalidate()
        durationObserver = nil

        bufferObserver?.invalidate()
        bufferObserver = nil

        if let item = playerItem {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)
        }

        playerItem = nil
    }

    private func cleanupPiP() {
        pipPossibleObserver?.invalidate()
        pipPossibleObserver = nil
        pipController = nil
    }

    private func sendEvent(_ type: String, data: [String: Any]) {
        var event = data
        event["playerId"] = playerId
        event["event"] = type
        eventCallback(event)
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension NativeAVPlayerController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        sendEvent("pipWillStart", data: [:])
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        sendEvent("pipDidStart", data: [:])
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        sendEvent("pipWillStop", data: [:])
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        sendEvent("pipDidStop", data: [:])
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        sendEvent("pipError", data: ["message": error.localizedDescription])
    }
}
