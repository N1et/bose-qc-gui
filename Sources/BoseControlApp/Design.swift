import SwiftUI

enum Studio {
    static let canvas = Color(red: 0.985, green: 0.982, blue: 0.972)
    static let ink = Color(red: 0.055, green: 0.055, blue: 0.05)
    static let secondary = Color.black.opacity(0.58)
    static let tertiary = Color.black.opacity(0.38)
    static let hairline = Color.black.opacity(0.10)
    static let softLine = Color.black.opacity(0.055)
    static let inset = Color.black.opacity(0.035)
    static let success = Color(red: 0.12, green: 0.47, blue: 0.30)
    static let error = Color(red: 0.68, green: 0.16, blue: 0.14)
    static let radius: CGFloat = 16
}

struct Panel<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(20)
            .background(Studio.canvas)
            .overlay(RoundedRectangle(cornerRadius: Studio.radius).stroke(Studio.hairline))
            .clipShape(RoundedRectangle(cornerRadius: Studio.radius))
    }
}

struct ModeButton: View {
    let title: String
    let selected: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                ZStack {
                    Circle().stroke(selected ? Studio.canvas : Studio.hairline, lineWidth: 1)
                    Circle().trim(from: 0.12, to: selected ? 0.88 : 0.60)
                        .stroke(selected ? Color.white : Studio.ink,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(90))
                        .padding(7)
                }
                .frame(width: 34, height: 34)
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(selected ? Color.white : Studio.ink)
            .background(selected ? Studio.ink : Studio.inset)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? .clear : Studio.softLine))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }
}

struct LevelSlider: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Text(label).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(value > 0 ? "+\(value)" : "\(value)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Studio.secondary)
            }
            Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                .tint(Studio.ink)
        }
    }
}

struct MonochromeSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack {
                Capsule()
                    .fill(isOn ? Studio.ink : Studio.inset)
                    .overlay(Capsule().stroke(isOn ? Color.clear : Studio.hairline, lineWidth: 1))
                Circle()
                    .fill(isOn ? Color.white : Studio.ink)
                    .frame(width: 18, height: 18)
                    .offset(x: isOn ? 10 : -10)
            }
            .frame(width: 46, height: 26)
            .animation(.easeOut(duration: 0.16), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Noise control")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

struct NoiseLevelSlider: View {
    @Binding var value: Int
    let enabled: Bool

    var body: some View {
        GeometryReader { geometry in
            let thumb: CGFloat = 18
            let usable = max(geometry.size.width - thumb, 0)
            let progress = CGFloat(min(max(value, 0), 10)) / 10

            ZStack(alignment: .leading) {
                Capsule().fill(Studio.hairline).frame(height: 4)
                    .padding(.horizontal, thumb / 2)
                Capsule().fill(Studio.ink).frame(width: max(progress * usable, 2), height: 4)
                    .offset(x: thumb / 2)
                Circle()
                    .fill(Studio.canvas)
                    .overlay(Circle().stroke(Studio.ink, lineWidth: 2))
                    .frame(width: thumb, height: thumb)
                    .offset(x: progress * usable)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                guard enabled else { return }
                let position = min(max(gesture.location.x - thumb / 2, 0), usable)
                value = Int((position / max(usable, 1) * 10).rounded())
            })
        }
        .frame(height: 24)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel("Noise control level")
        .accessibilityValue("\(value) of 10")
    }
}

struct ImmersiveSelector: View {
    @Binding var selection: ImmersiveMode
    let enabled: Bool
    var width: CGFloat = 320

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ImmersiveMode.allCases) { mode in
                Button { selection = mode } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selection == mode ? Color.white : Studio.ink)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(selection == mode ? Studio.ink : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Studio.inset)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Studio.hairline))
        .frame(width: width)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel("Immersive audio")
    }
}
