import SwiftUI
import WidgetKit
import AppKit

// MARK: - Widget Theme

struct WidgetTheme {
    static let primaryColor = Color.blue
    static let secondaryColor = Color.gray
    static let backgroundColor = Color(nsColor: .windowBackgroundColor)
    static let surfaceColor = Color(nsColor: .controlBackgroundColor)

    static let musicColor = Color.pink
    static let videoColor = Color.purple
    static let booksColor = Color.orange

    static let successColor = Color.green
    static let warningColor = Color.orange
    static let errorColor = Color.red
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
        case .books: return WidgetTheme.booksColor
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
