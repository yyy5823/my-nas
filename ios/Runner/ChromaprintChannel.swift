import Flutter
import AVFoundation
import Accelerate

/**
 Chromaprint 指纹生成 Flutter 插件

 使用 AVFoundation 解码音频，然后调用 Chromaprint 静态库生成指纹
 需要链接 Chromaprint.xcframework
 */
class ChromaprintChannel: NSObject, FlutterPlugin {

    static let channelName = "com.mynas.fingerprint/chromaprint"

    /// 是否链接了 Chromaprint 库
    #if CHROMAPRINT_AVAILABLE
    private static let frameworkLoaded: Bool = true
    #else
    private static let frameworkLoaded: Bool = false
    #endif

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = ChromaprintChannel()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAvailable":
            result(Self.frameworkLoaded)

        case "generateFingerprint":
            guard let args = call.arguments as? [String: Any],
                  let filePath = args["filePath"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                    message: "filePath is required",
                                    details: nil))
                return
            }

            let maxDuration = args["maxDuration"] as? Int ?? 120

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let fpResult = try self.generateFingerprint(
                        filePath: filePath,
                        maxDuration: maxDuration
                    )
                    DispatchQueue.main.async {
                        result(fpResult)
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "FINGERPRINT_ERROR",
                                            message: error.localizedDescription,
                                            details: nil))
                    }
                }
            }

        case "getVersion":
            if Self.frameworkLoaded {
                result(getChromaprintVersion())
            } else {
                result(nil)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// 生成音频指纹
    private func generateFingerprint(filePath: String, maxDuration: Int) throws -> [String: Any] {
        let url = URL(fileURLWithPath: filePath)

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw FingerprintError.fileNotFound(filePath)
        }

        guard Self.frameworkLoaded else {
            throw FingerprintError.frameworkNotLoaded
        }

        // 使用 AVAudioFile 读取音频
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let sampleRate = Int(format.sampleRate)
        let channelCount = Int(format.channelCount)
        let frameCount = AVAudioFrameCount(audioFile.length)

        // 计算要处理的帧数
        let maxFrames = AVAudioFrameCount(maxDuration * sampleRate)
        let framesToProcess = min(frameCount, maxFrames)

        // 读取音频数据
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToProcess) else {
            throw FingerprintError.bufferCreationFailed
        }

        try audioFile.read(into: buffer, frameCount: framesToProcess)

        // 转换为 Chromaprint 需要的格式 (16-bit signed integer, 44100 Hz, stereo)
        let pcmData = convertToPCM16(
            buffer: buffer,
            srcSampleRate: sampleRate,
            srcChannels: channelCount,
            dstSampleRate: 44100,
            dstChannels: 2
        )

        // 调用 Chromaprint 生成指纹
        let fingerprint = try chromaprintFingerprint(
            samples: pcmData,
            sampleRate: 44100,
            channels: 2
        )

        let duration = min(Int(framesToProcess) / sampleRate, maxDuration)

        return [
            "fingerprint": fingerprint,
            "duration": duration
        ]
    }

    /// 转换为 16-bit PCM
    private func convertToPCM16(
        buffer: AVAudioPCMBuffer,
        srcSampleRate: Int,
        srcChannels: Int,
        dstSampleRate: Int,
        dstChannels: Int
    ) -> [Int16] {
        guard let floatChannelData = buffer.floatChannelData else {
            return []
        }

        let frameCount = Int(buffer.frameLength)

        // 如果采样率和声道数相同，直接转换
        if srcSampleRate == dstSampleRate && srcChannels == dstChannels {
            var result = [Int16](repeating: 0, count: frameCount * srcChannels)

            for frame in 0..<frameCount {
                for channel in 0..<srcChannels {
                    let sample = floatChannelData[channel][frame]
                    result[frame * srcChannels + channel] = Int16(max(-1, min(1, sample)) * 32767)
                }
            }

            return result
        }

        // 重采样和声道转换
        let ratio = Double(srcSampleRate) / Double(dstSampleRate)
        let dstFrameCount = Int(Double(frameCount) / ratio)
        var result = [Int16](repeating: 0, count: dstFrameCount * dstChannels)

        for dstFrame in 0..<dstFrameCount {
            let srcFrame = min(Int(Double(dstFrame) * ratio), frameCount - 1)

            for dstChannel in 0..<dstChannels {
                let srcChannel = min(dstChannel, srcChannels - 1)
                let sample = floatChannelData[srcChannel][srcFrame]
                result[dstFrame * dstChannels + dstChannel] = Int16(max(-1, min(1, sample)) * 32767)
            }
        }

        return result
    }

    /// 调用 Chromaprint 生成指纹
    private func chromaprintFingerprint(samples: [Int16], sampleRate: Int, channels: Int) throws -> String {
        #if CHROMAPRINT_AVAILABLE
        // 创建 Chromaprint 上下文
        guard let ctx = chromaprint_new(Int32(CHROMAPRINT_ALGORITHM_DEFAULT)) else {
            throw FingerprintError.contextCreationFailed
        }
        defer { chromaprint_free(ctx) }

        // 开始指纹计算
        guard chromaprint_start(ctx, Int32(sampleRate), Int32(channels)) == 1 else {
            throw FingerprintError.startFailed
        }

        // 喂入音频数据
        let result = samples.withUnsafeBufferPointer { ptr -> Int32 in
            guard let baseAddress = ptr.baseAddress else { return 0 }
            return chromaprint_feed(ctx, baseAddress, Int32(samples.count))
        }

        guard result == 1 else {
            throw FingerprintError.feedFailed
        }

        // 结束指纹计算
        guard chromaprint_finish(ctx) == 1 else {
            throw FingerprintError.finishFailed
        }

        // 获取指纹字符串
        var fingerprintPtr: UnsafeMutablePointer<CChar>?
        guard chromaprint_get_fingerprint(ctx, &fingerprintPtr) == 1,
              let fp = fingerprintPtr else {
            throw FingerprintError.getFingerprintFailed
        }
        defer { chromaprint_dealloc(fp) }

        return String(cString: fp)
        #else
        throw FingerprintError.frameworkNotLoaded
        #endif
    }

    /// 获取 Chromaprint 版本
    private func getChromaprintVersion() -> String? {
        #if CHROMAPRINT_AVAILABLE
        if let version = chromaprint_get_version() {
            return String(cString: version)
        }
        return nil
        #else
        return nil
        #endif
    }
}

// MARK: - Errors

enum FingerprintError: LocalizedError {
    case fileNotFound(String)
    case frameworkNotLoaded
    case bufferCreationFailed
    case contextCreationFailed
    case startFailed
    case feedFailed
    case finishFailed
    case getFingerprintFailed

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "文件不存在: \(path)"
        case .frameworkNotLoaded:
            return "Chromaprint 框架未加载"
        case .bufferCreationFailed:
            return "创建音频缓冲区失败"
        case .contextCreationFailed:
            return "创建 Chromaprint 上下文失败"
        case .startFailed:
            return "启动指纹计算失败"
        case .feedFailed:
            return "喂入音频数据失败"
        case .finishFailed:
            return "结束指纹计算失败"
        case .getFingerprintFailed:
            return "获取指纹失败"
        }
    }
}
