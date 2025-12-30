//
//  WidgetStyles.swift
//  MyNasWidgets
//
//  Shared styles and theme for all widgets
//

import SwiftUI
import WidgetKit

/// 小组件主题颜色
/// 动态读取应用配色方案，支持主题同步
struct WidgetTheme {
    /// 获取当前主题数据
    private static var theme: WidgetDataManager.ThemeData {
        WidgetDataManager.shared.getThemeData()
    }

    // 主色调 - 动态
    static var primaryColor: Color { theme.primaryColor }
    static var primaryLightColor: Color { theme.primaryLightColor }
    static var primaryDarkColor: Color { theme.primaryDarkColor }
    static var secondaryColor: Color { theme.secondaryColor }
    static var accentColor: Color { theme.accentColor }

    // 功能性颜色 - 动态
    static var musicColor: Color { theme.musicColor }
    static var videoColor: Color { theme.videoColor }
    static var photoColor: Color { theme.photoColor }
    static var bookColor: Color { theme.bookColor }
    static var downloadColor: Color { theme.downloadColor }

    // 背景色 - 动态
    static var darkBackgroundColor: Color { theme.darkBackgroundColor }
    static var darkSurfaceColor: Color { theme.darkSurfaceColor }
    static var darkSurfaceVariantColor: Color { theme.darkSurfaceVariantColor }

    // 文字颜色 - 固定
    static let textPrimary = Color.white
    static let textSecondary = Color.gray

    // 状态颜色 - 动态
    static var successColor: Color { theme.successColor }
    static var warningColor: Color { theme.warningColor }
    static var errorColor: Color { theme.errorColor }

    // 背景渐变 - 动态
    static var backgroundGradient: LinearGradient {
        theme.backgroundGradient
    }

    // 卡片背景
    static var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.1))
    }

    /// 根据快捷访问类型获取颜色
    static func color(for type: String) -> Color {
        switch type {
        case "music": return musicColor
        case "video": return videoColor
        case "photo": return photoColor
        case "reading": return bookColor
        case "files": return downloadColor
        default: return primaryColor
        }
    }
}

/// 快捷访问项目样式
struct QuickAccessItemStyle: ViewModifier {
    let isSmall: Bool

    func body(content: Content) -> some View {
        content
            .frame(width: isSmall ? 50 : 60, height: isSmall ? 50 : 60)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.15))
            )
    }
}

/// 进度环样式
struct ProgressRingStyle: ViewModifier {
    let progress: Double
    let lineWidth: CGFloat
    let backgroundColor: Color
    let foregroundColor: Color

    func body(content: Content) -> some View {
        content
            .overlay(
                ZStack {
                    Circle()
                        .stroke(backgroundColor, lineWidth: lineWidth)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            foregroundColor,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
            )
    }
}

// MARK: - View Extensions

extension View {
    func quickAccessItemStyle(isSmall: Bool = false) -> some View {
        modifier(QuickAccessItemStyle(isSmall: isSmall))
    }

    func progressRing(
        progress: Double,
        lineWidth: CGFloat = 6,
        backgroundColor: Color = Color.gray.opacity(0.3),
        foregroundColor: Color = WidgetTheme.primaryColor
    ) -> some View {
        modifier(ProgressRingStyle(
            progress: progress,
            lineWidth: lineWidth,
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor
        ))
    }

    /// iOS 16 及以下版本的 Widget 背景包装器
    /// iOS 17+ 使用 containerBackground API（在 Widget Configuration 中设置）
    @ViewBuilder
    func widgetBackgroundCompat<S: ShapeStyle>(_ style: S) -> some View {
        if #available(iOS 17.0, *) {
            // iOS 17+ 背景由 containerBackground 处理，无需内部绘制
            self
        } else {
            ZStack {
                ContainerRelativeShape()
                    .fill(style)
                self
            }
        }
    }

    /// 用于带有自定义背景（如封面图片）的 Widget
    @ViewBuilder
    func widgetCustomBackgroundCompat<Background: View>(@ViewBuilder _ background: () -> Background) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) {
                background()
            }
        } else {
            ZStack {
                background()
                    .clipShape(ContainerRelativeShape())
                self
            }
        }
    }
}

// MARK: - Common Widget Views

/// 空状态视图
struct EmptyStateView: View {
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(WidgetTheme.textSecondary)

            Text(message)
                .font(.caption)
                .foregroundColor(WidgetTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 未连接状态视图
struct NotConnectedView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 28))
                .foregroundColor(WidgetTheme.textSecondary)

            Text("未连接 NAS")
                .font(.caption)
                .foregroundColor(WidgetTheme.textSecondary)

            Text("点击打开应用连接")
                .font(.caption2)
                .foregroundColor(WidgetTheme.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 标题栏视图
struct WidgetHeader: View {
    let icon: String
    let title: String
    let subtitle: String?

    init(icon: String, title: String, subtitle: String? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(WidgetTheme.primaryColor)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(WidgetTheme.textPrimary)

            if let subtitle = subtitle {
                Text("·")
                    .foregroundColor(WidgetTheme.textSecondary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(WidgetTheme.textSecondary)
            }

            Spacer()
        }
    }
}
