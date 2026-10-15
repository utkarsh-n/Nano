import SwiftUI
import Charts
import Foundation

struct GrowthPanel: View {
    let worlds: [TorusWorld]
    let store: LabStore
    @Binding var metric: MetricKind
    @State private var chartRevision = Int(ProcessInfo.processInfo.systemUptime * 2)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Growth").font(.title3.bold())
                Spacer()
                Picker("Growth measure", selection: $metric) {
                    ForEach(MetricKind.allCases) { kind in Text(kind.label).tag(kind) }
                }
                .pickerStyle(.menu).tint(.primary)
                .accessibilityIdentifier("growthMetric")
            }
            BoundedGrowthChart(
                worlds: worlds,
                worldIDs: worlds.map(\.id),
                colors: worlds.map { store.color(for: $0.id) },
                metric: metric,
                revision: chartRevision
            )
            .equatable()
            HStack(spacing: 14) {
                ForEach(worlds) { world in
                    HStack(spacing: 4) {
                        Circle().fill(store.color(for: world.id)).frame(width: 7, height: 7)
                        Text(world.name).lineLimit(1)
                        Text(metric.value(in: world.metrics), format: .number.precision(.fractionLength(metric == .radius || metric == .growth ? 2 : 0))).monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
                Text("sim. min").foregroundStyle(.tertiary)
            }
            .font(.caption)
            if metric == .coherence {
                Text("Share of mobile particles moving coherently.").font(.caption2).foregroundStyle(.secondary)
            } else if metric == .growth {
                Text("Radius change per simulated minute, over the latest 30 seconds.").font(.caption2).foregroundStyle(.secondary)
            }
            if worlds.contains(where: { $0.history.count > BoundedGrowthChart.sampleLimit }) {
                Text("Chart samples recent recorded history; brief peaks may be omitted.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { break }
                chartRevision = Int(ProcessInfo.processInfo.systemUptime * 2)
            }
        }
    }
}

/// This view intentionally observes no store or bindings. Simulation ticks can refresh the
/// surrounding numeric readout without asking Swift Charts to rebuild its graph every frame.
private struct BoundedGrowthChart: View, Equatable {
    static let sampleLimit = 80
    let worlds: [TorusWorld]
    let worldIDs: [String]
    let colors: [Color]
    let metric: MetricKind
    let revision: Int

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.revision == rhs.revision && lhs.metric == rhs.metric && lhs.worldIDs == rhs.worldIDs
    }

    private struct PlotSample: Identifiable {
        var id: String
        var worldID: String
        var elapsed: Double
        var value: Double
        var isLatest: Bool
    }

    private var plotSamples: [PlotSample] {
        worlds.flatMap { world in
            let count = world.history.count
            guard count > 0 else { return [PlotSample]() }
            let indices: [Int]
            if count <= Self.sampleLimit {
                indices = Array(world.history.indices)
            } else {
                // Integer indexing guarantees distinct measured points, including both endpoints.
                indices = (0..<Self.sampleLimit).map { $0 * (count - 1) / (Self.sampleLimit - 1) }
            }
            return indices.map { index in
                let sample = world.history[index]
                return PlotSample(id: "\(world.id)-\(sample.time)", worldID: world.id,
                    elapsed: (sample.time - world.comparisonBaseline.time) / 60,
                    value: metric.value(in: sample.metrics), isLatest: index == count - 1)
            }
        }
    }

    private var domain: ClosedRange<Double> {
        // Use all measured values for the domain, even when the drawn series is sampled.
        let values = worlds.flatMap { $0.history.map { metric.value(in: $0.metrics) } }
        if metric == .coherence { return 0...100 }
        if metric == .radius { return 1...max(1.08, (values.max() ?? 1) + 0.03) }
        return 0...max(1, (values.max() ?? 1) * 1.15)
    }

    var body: some View {
        let points = plotSamples
        let elapsedMinutes = max(0.5, (worlds.map { $0.time - $0.comparisonBaseline.time }.max() ?? 0) / 60)
        Chart(points) { point in
            LineMark(x: .value("Minutes", point.elapsed), y: .value("Value", point.value), series: .value("World", point.worldID))
                .foregroundStyle(by: .value("World", point.worldID))
                .interpolationMethod(.linear)
            if point.isLatest {
                PointMark(x: .value("Minutes", point.elapsed), y: .value("Value", point.value))
                    .foregroundStyle(by: .value("World", point.worldID)).symbolSize(20)
            }
        }
        .chartForegroundStyleScale(domain: worldIDs, range: colors)
        .chartLegend(.hidden)
        .chartYScale(domain: domain)
        .chartXScale(domain: 0...elapsedMinutes)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1)))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(metric == .radius || metric == .growth ? 2 : 0)))
            }
        }
        .frame(height: 115)
        .accessibilityLabel("\(metric.label) over simulated minutes")
    }
}
