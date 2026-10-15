import SwiftUI

enum WorldTool: String, CaseIterable, Identifiable {
    case warmth, flow, bonds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warmth: return "Warmth"
        case .flow: return "Flow"
        case .bonds: return "Bonds"
        }
    }

    var subtitle: String {
        switch self {
        case .warmth: return "Give particles energy to move."
        case .flow: return "Change how steady the current feels."
        case .bonds: return "Help nearby opposites move together."
        }
    }

    var symbol: String {
        switch self {
        case .warmth: return "sun.max.fill"
        case .flow: return "wind"
        case .bonds: return "link"
        }
    }

    var tint: Color {
        switch self {
        case .warmth: return .orange
        case .flow: return .cyan
        case .bonds: return .purple
        }
    }

    var keyPath: WritableKeyPath<TorusParameters, Double> {
        switch self {
        case .warmth: return \.energyInput
        case .flow: return \.turbulence
        case .bonds: return \.linkStrength
        }
    }

    func settingName(for value: Double) -> String {
        switch (self, level(for: value)) {
        case (.warmth, 0): return "Gentle"
        case (.warmth, 1): return "Balanced"
        case (.warmth, _): return "Intense"
        case (.flow, 0): return "Calm"
        case (.flow, 1): return "Lively"
        case (.flow, _): return "Restless"
        case (.bonds, 0): return "Loose"
        case (.bonds, 1): return "Connected"
        case (.bonds, _): return "Strong"
        }
    }

    func effectDescription(for value: Double) -> String {
        switch (self, level(for: value)) {
        case (.warmth, 0):
            return "Less energy reaches each particle. Watch motion soften; with less energy available, growth can slow."
        case (.warmth, 1):
            return "A steady supply supports motion. Watch for coherent particles settling into the outer rim."
        case (.warmth, _):
            return "More energy drives faster motion. Too much can disturb alignment and delay settling at the rim."
        case (.flow, 0):
            return "Fewer disturbances help particles keep a steady course. Bonds and shared motion have more time to develop."
        case (.flow, 1):
            return "Changing currents send particles along different paths. Watch which ones regain a shared direction."
        case (.flow, _):
            return "Strong disturbances make motion restless. Coherence and stable connections become harder to sustain."
        case (.bonds, 0):
            return "Connections pull less firmly. Particles can change course more easily, but get less support from their partners."
        case (.bonds, 1):
            return "Connections help nearby opposites move together while leaving some freedom to change course."
        case (.bonds, _):
            return "Links hold more firmly and pull partners together. Strong connections also slow their outward movement."
        }
    }

    private func level(for value: Double) -> Int {
        value < 0.34 ? 0 : value < 0.67 ? 1 : 2
    }
}

struct WorldTuningSheet: View {
    @Bindable var store: LabStore
    let worldID: String
    let tool: WorldTool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var detent: PresentationDetent = .medium

    private var world: TorusWorld? { store.world(worldID) }
    private var value: Double {
        min(1, max(0, world?.parameters[keyPath: tool.keyPath] ?? 0.5))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let world {
                    tuningContent(for: world)
                } else {
                    ContentUnavailableView("World unavailable", systemImage: "circle.dotted",
                                           description: Text("Return to your worlds and choose another experiment."))
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(tool.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.save()
                        dismiss()
                    }
                    .accessibilityIdentifier("doneTuning")
                }
            }
        }
        .tint(.blue)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .onAppear {
            if dynamicTypeSize.isAccessibilitySize { detent = .large }
        }
        .onChange(of: dynamicTypeSize) { _, size in
            if size.isAccessibilitySize { detent = .large }
        }
    }

    private func tuningContent(for world: TorusWorld) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: tool.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tool.tint)
                    .frame(width: 44, height: 44)
                    .background(tool.tint.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tool.subtitle).font(.headline)
                    Text(world.name).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if dynamicTypeSize.isAccessibilitySize {
                dial(size: 220)
                explanation
            } else {
                HStack(alignment: .center, spacing: 16) {
                    dial(size: 174)
                    explanation
                }
            }

            HStack(spacing: 16) {
                Button {
                    setValue(value - 0.05)
                } label: {
                    Image(systemName: "minus")
                        .font(.title3.weight(.semibold))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .disabled(value <= 0)
                .accessibilityLabel("Decrease \(tool.title.lowercased())")
                .accessibilityIdentifier("decreaseTuning")

                Text("Drag up or down")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                Button {
                    setValue(value + 0.05)
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .disabled(value >= 1)
                .accessibilityLabel("Increase \(tool.title.lowercased())")
                .accessibilityIdentifier("increaseTuning")
            }
            .padding(.horizontal, 12)


        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    private func dial(size: CGFloat) -> some View {
        TactileDial(value: value, valueWord: tool.settingName(for: value),
                    label: tool.title, symbol: tool.symbol, tint: tool.tint,
                    onChange: setValue)
            .frame(width: size, height: size)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What to watch").font(.caption.weight(.semibold))
            Text(tool.effectDescription(for: value))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !store.lab.isRunning {
                Label("Press play when you're ready.", systemImage: "pause.circle")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setValue(_ proposed: Double) {
        guard world != nil, proposed.isFinite else { return }
        // One-percent steps make touch input predictable and avoid duplicate commands.
        let next = (min(1, max(0, proposed)) * 100).rounded() / 100
        guard abs(next - value) > 0.000_1 else { return }
        store.tune(tool.keyPath, to: next, in: worldID)
    }
}

private struct TactileDial: View {
    let value: Double
    let valueWord: String
    let label: String
    let symbol: String
    let tint: Color
    let onChange: (Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var dragStartValue: Double? = nil

    private var clampedValue: Double { min(1, max(0, value)) }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let trackSize = size - 38
            ZStack {
                Circle()
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .frame(width: trackSize - 24, height: trackSize - 24)
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 3)

                ForEach(0...40, id: \.self) { index in
                    Capsule()
                        .fill(Double(index) / 40 <= clampedValue ? tint.opacity(0.8) : Color.secondary.opacity(0.25))
                        .frame(width: index.isMultiple(of: 5) ? 2 : 1,
                               height: index.isMultiple(of: 5) ? 11 : 6)
                        .offset(y: -(size / 2 - 7))
                        .rotationEffect(.degrees(-150 + Double(index) * 7.5))
                }

                Circle().trim(from: 0, to: 5.0 / 6.0)
                    .stroke(tint.opacity(0.12), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(120))
                    .frame(width: trackSize, height: trackSize)
                Circle().trim(from: 0, to: clampedValue * 5.0 / 6.0)
                    .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(120))
                    .frame(width: trackSize, height: trackSize)

                Circle()
                    .fill(.white)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(tint, lineWidth: 3))
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
                    .offset(y: -trackSize / 2)
                    .rotationEffect(.degrees(-150 + clampedValue * 300))

                VStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(tint)
                    Text(valueWord)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(clampedValue, format: .percent.precision(.fractionLength(0)))
                        .font(.system(.title2, design: .rounded).weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(width: trackSize - 52)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Circle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 3)
                    .updating($dragStartValue) { _, start, _ in
                        if start == nil { start = clampedValue }
                    }
                    .onChanged { gesture in
                        // Anchor the drag to its initial value, not the changing model value.
                        let origin = dragStartValue ?? clampedValue
                        let travel = max(200, size)
                        onChange(min(1, max(0, origin - Double(gesture.translation.height / travel))))
                    }
            )
            .animation(reduceMotion || dragStartValue != nil ? nil : .easeOut(duration: 0.16), value: clampedValue)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(valueWord), \(Int((clampedValue * 100).rounded())) percent")
        .accessibilityHint("Swipe up or down to adjust by five percent.")
        .accessibilityIdentifier("tuningDial")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(1, clampedValue + 0.05))
            case .decrement: onChange(max(0, clampedValue - 0.05))
            @unknown default: break
            }
        }
    }
}
