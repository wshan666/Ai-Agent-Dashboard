import SwiftUI

enum V2Theme {
    static let cyan = Color(red: 0.02, green: 0.72, blue: 0.92)
    static let mint = Color(red: 0.06, green: 0.78, blue: 0.55)
    static let amber = Color(red: 0.96, green: 0.62, blue: 0.18)
    static let red = Color(red: 0.95, green: 0.24, blue: 0.31)
    static let violet = Color(red: 0.48, green: 0.42, blue: 0.94)
    static let ink = Color(red: 0.05, green: 0.08, blue: 0.13)

    static func statusColor(_ agent: AgentSummary) -> Color {
        if agent.isOnline { return mint }
        if agent.isChecking { return amber }
        return red
    }

    static func statusColor(_ status: String) -> Color {
        switch status {
        case "completed", "available", "running": return mint
        case "queued", "checking": return amber
        case "failed", "cancelled", "disabled": return red
        default: return cyan
        }
    }
}

struct V2ScreenBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.03, green: 0.05, blue: 0.09), Color(red: 0.04, green: 0.12, blue: 0.16), Color(red: 0.06, green: 0.08, blue: 0.12)]
                    : [Color(red: 0.94, green: 0.98, blue: 1.0), Color(red: 0.91, green: 0.96, blue: 0.97), Color(red: 0.98, green: 0.98, blue: 0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            V2GridOverlay()
                .opacity(colorScheme == .dark ? 0.34 : 0.2)
        }
        .ignoresSafeArea()
    }
}

private struct V2GridOverlay: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let spacing: CGFloat = 28
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += spacing
                }
                var y: CGFloat = 0
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += spacing
                }
                context.stroke(path, with: .color(V2Theme.cyan.opacity(0.22)), lineWidth: 0.6)

                let sweep = CGFloat(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8) / 8) * (size.height + 120) - 60
                var scan = Path()
                scan.move(to: CGPoint(x: 0, y: sweep))
                scan.addLine(to: CGPoint(x: size.width, y: sweep + 34))
                context.stroke(scan, with: .color(V2Theme.mint.opacity(0.28)), lineWidth: 1.4)
            }
        }
        .allowsHitTesting(false)
    }
}

struct V2CardModifier: ViewModifier {
    var tint: Color = V2Theme.cyan

    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [tint.opacity(0.44), Color.white.opacity(0.12), tint.opacity(0.16)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: tint.opacity(0.12), radius: 14, x: 0, y: 8)
    }
}

extension View {
    func v2Card(tint: Color = V2Theme.cyan) -> some View {
        modifier(V2CardModifier(tint: tint))
    }

    func v2PageBackground() -> some View {
        background(V2ScreenBackground())
    }
}

struct V2HeroHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = V2Theme.cyan

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(tint.opacity(0.14))
                .overlay(Circle().stroke(tint.opacity(0.46), lineWidth: 1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow)
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.title.bold())
                    .lineLimit(2)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .v2Card(tint: tint)
    }
}

struct V2MetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Spacer()
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                    .shadow(color: tint.opacity(0.65), radius: 5)
            }
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .v2Card(tint: tint)
    }
}

struct V2StatusBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .shadow(color: tint.opacity(0.65), radius: 4)
            Text(text)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tint.opacity(0.13))
        .foregroundStyle(tint)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct V2SectionLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = V2Theme.cyan

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.primary)
            .labelStyle(.titleAndIcon)
            .symbolRenderingMode(.hierarchical)
    }
}
