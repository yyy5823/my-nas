//
//  WidgetStyles.swift
//  MyNasWidgets
//
//  Shared styles and theme for all widgets
//

import SwiftUI
import WidgetKit

/// 小组件主题颜色
struct WidgetTheme {
    // 主色调
    static let primaryColor = Color(hex: "00d4aa") // 青绿色
    static let secondaryColor = Color(hex: "6c5ce7") // 紫色

    // 背景色
    static let backgroundGradientStart = Color(hex: "1a1a2e")
    static let backgroundGradientEnd = Color(hex: "16213e")

    // 文字颜色
    static let textPrimary = Color.white
    static let textSecondary = Color.gray

    // 状态颜色
    static let successColor = Color.green
    static let warningColor = Color.orange
    static let errorColor = Color.red

    // 背景渐变
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundGradientStart, backgroundGradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // 卡片背景
    static var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.1))
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
