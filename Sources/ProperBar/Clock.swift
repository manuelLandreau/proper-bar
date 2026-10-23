import SwiftUI

struct ClockView: View {
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        let horizontal = prefs.position.isHorizontal
        TimelineView(.everyMinute) { context in
            VStack(alignment: .center, spacing: 0) {
                Text(context.date.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                if !prefs.isCompact || !horizontal {
                    Text(context.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: horizontal ? nil : .infinity, maxHeight: horizontal ? .infinity : nil)
        .barPopup("calendar") { CalendarView() }
    }
}

struct CalendarView: View {
    @State private var selection = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(alignment: .center, spacing: 16) {
                    AnalogClock(date: context.date).frame(width: 84, height: 84)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.date.formatted(.dateTime.hour().minute().second()))
                            .font(.system(size: 28, weight: .light))
                            .monospacedDigit()
                        Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()).capitalized)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            DatePicker("", selection: $selection, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .scaleEffect(1.5, anchor: .top)
                .frame(width: 252, height: 225, alignment: .top)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(width: 320)
    }
}

struct AnalogClock: View {
    let date: Date

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                         with: .color(.primary.opacity(0.06)))
            for hour in 0..<12 {
                let angle = Double(hour) / 12 * 2 * .pi
                let outer = point(center, radius * 0.9, angle)
                let inner = point(center, radius * (hour % 3 == 0 ? 0.74 : 0.8), angle)
                var tick = Path()
                tick.move(to: inner)
                tick.addLine(to: outer)
                context.stroke(tick, with: .color(.primary.opacity(hour % 3 == 0 ? 0.6 : 0.3)), lineWidth: hour % 3 == 0 ? 2 : 1)
            }
            let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
            let seconds = Double(parts.second ?? 0)
            let minutes = Double(parts.minute ?? 0) + seconds / 60
            let hours = Double((parts.hour ?? 0) % 12) + minutes / 60
            hand(context, center, length: radius * 0.5, angle: hours / 12 * 2 * .pi, width: 3, color: .primary)
            hand(context, center, length: radius * 0.72, angle: minutes / 60 * 2 * .pi, width: 2, color: .primary)
            hand(context, center, length: radius * 0.8, angle: seconds / 60 * 2 * .pi, width: 1, color: .accentColor)
            context.fill(Path(ellipseIn: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)), with: .color(.accentColor))
        }
    }

    private func point(_ center: CGPoint, _ length: CGFloat, _ angle: Double) -> CGPoint {
        CGPoint(x: center.x + length * sin(angle), y: center.y - length * cos(angle))
    }

    private func hand(_ context: GraphicsContext, _ center: CGPoint, length: CGFloat, angle: Double, width: CGFloat, color: Color) {
        var path = Path()
        path.move(to: center)
        path.addLine(to: point(center, length, angle))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}
