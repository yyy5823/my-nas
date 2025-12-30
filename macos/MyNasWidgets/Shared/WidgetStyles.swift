import SwiftUI
import WidgetKit
import AppKit

// MARK: - Widget Theme
/// 动态读取应用配色方案，支持主题同步

struct WidgetTheme {
    /// 获取当前主题数据
    private static var theme: ThemeData {
        WidgetDataManager.shared.getThemeData()
    }

    // 主色调 - 动态
    static var primaryColor: Color { theme.primaryColor }
    static var primaryLightColor: Color { theme.primaryLightColor }
    static var primaryDarkColor: Color { theme.primaryDarkColor }
    static var secondaryColor: Color { theme.secondaryColor }
    static var accentColor: Color { theme.accentColor }

    // 背景色 - 动态
    static var backgroundColor: Color { theme.darkBackgroundColor }
    static var surfaceColor: Color { theme.darkSurfaceColor }
    static var surfaceVariantColor: Color { theme.darkSurfaceVariantColor }

    // 功能性颜色 - 动态
    static var musicColor: Color { theme.musicColor }
    static var videoColor: Color { theme.videoColor }
    static var photoColor: Color { theme.photoColor }
    static var readingColor: Color { theme.bookColor }
    static var downloadColor: Color { theme.downloadColor }

    // 状态颜色 - 动态
    static var successColor: Color { theme.successColor }
    static var warningColor: Color { theme.warningColor }
    static var errorColor: Color { theme.errorColor }

    // 背景渐变 - 动态
    static var backgroundGradient: LinearGradient {
        theme.backgroundGradient
    }

    /// 根据快捷访问类型获取颜色
    static func color(for type: String) -> Color {
        switch type {
        case "music": return musicColor
        case "video": return videoColor
        case "photo": return photoColor
        case "reading": return readingColor
        case "files": return downloadColor
        default: return primaryColor
        }
    }
}

// MARK: - Common Views

struct WidgetHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(WidgetTheme.secondaryColor)
            Text(title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(WidgetTheme.secondaryColor)
            Spacer()
        }
    }
}

struct CircularProgressView: View {
    let progress: Double
    let lineWidth: CGFloat
    let foregroundColor: Color
    let backgroundColor: Color

    init(
        progress: Double,
        lineWidth: CGFloat = 8,
        foregroundColor: Color = WidgetTheme.primaryColor,
        backgroundColor: Color = WidgetTheme.secondaryColor.opacity(0.3)
    ) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(backgroundColor, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: CGFloat(min(progress, 1.0)))
                .stroke(
                    foregroundColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)
        }
    }
}

struct LinearProgressView: View {
    let progress: Double
    let height: CGFloat
    let foregroundColor: Color
    let backgroundColor: Color

    init(
        progress: Double,
        height: CGFloat = 4,
        foregroundColor: Color = WidgetTheme.primaryColor,
        backgroundColor: Color = WidgetTheme.secondaryColor.opacity(0.3)
    ) {
        self.progress = progress
        self.height = height
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(backgroundColor)

                RoundedRectangle(cornerRadius: height / 2)
                    .fill(foregroundColor)
                    .frame(width: geometry.size.width * CGFloat(min(progress, 1.0)))
                    .animation(.easeInOut, value: progress)
            }
        }
        .frame(height: height)
    }
}

struct QuickAccessButton: View {
    let type: QuickAccessType
    let size: CGFloat

    var body: some View {
        Link(destination: type.deepLink) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(buttonColor.opacity(0.2))

                    Image(systemName: type.iconName)
                        .font(.system(size: size * 0.4))
                        .foregroundColor(buttonColor)
                }
                .frame(width: size, height: size)

                Text(type.displayName)
                    .font(.caption2)
                    .foregroundColor(.primary)
            }
        }
    }

    private var buttonColor: Color {
        switch type {
        case .music: return WidgetTheme.musicColor
        case .video: return WidgetTheme.videoColor
        case .reading: return WidgetTheme.readingColor
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(WidgetTheme.secondaryColor)

            Text(message)
                .font(.caption)
                .foregroundColor(WidgetTheme.secondaryColor)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Widget Container

struct WidgetContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding()
            .background(WidgetTheme.backgroundColor)
    }
}
