import SwiftUI

enum VenusVisuals {
    static let charging = Color(red: 240 / 255, green: 120 / 255, blue: 68 / 255)
    static let supplying = Color(red: 0.25, green: 0.84, blue: 0.53)
    static func accent(_ state: VenusFlowState, fresh: Bool = true) -> Color {
        guard fresh else { return .white.opacity(0.35) }
        switch state {
        case .charging: return charging
        case .supplyingHome: return supplying
        case .mains: return .white.opacity(0.65)
        case .standby: return .white.opacity(0.8)
        case .unknown: return .white.opacity(0.4)
        }
    }
    static func number(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...digits)).locale(Locale(identifier: "uk_UA")))
    }
    static func power(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return abs(value) >= 1000 ? "\(number(value / 1000, digits: 2)) кВт" : "\(number(value)) Вт"
    }
    static func energy(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return value >= 1000 ? "\(number(value / 1000, digits: 2)) кВт·год" : "\(number(value)) Вт·год"
    }
    static func soc(_ value: Double?) -> String {
        guard let value, value.isFinite, (0...100).contains(value) else { return "—" }
        return "\(number(value))%"
    }
}

struct VenusTemperatureIcon: View {
    let temperature: Double?
    let fresh: Bool
    var size: CGFloat = 28
    var adaptive = false

    private var reading: VenusTemperature.Result { VenusTemperature.evaluate(value: temperature, fresh: fresh) }
    private var tint: Color {
        switch reading.level {
        case .unknown: return adaptive ? .primary.opacity(0.35) : .white.opacity(0.3)
        case .normal: return adaptive ? .primary.opacity(0.7) : .white.opacity(0.75)
        case .warm: return Color(red: 0.96, green: 0.77, blue: 0.27)
        case .hot: return VenusVisuals.charging
        case .high: return Color(red: 1, green: 0.32, blue: 0.37)
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke((adaptive ? Color.primary : .white).opacity(0.1), lineWidth: 1.6)
            if let progress = reading.progress {
                Circle().trim(from: 0, to: progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: "thermometer.medium")
                .font(.system(size: size * 0.48, weight: .medium)).foregroundStyle(tint)
        }.frame(width: size, height: size)
            .help(reading.title + ". " + reading.explanation)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(reading.value.map { "\(reading.title), \(VenusVisuals.number($0)) градусів Цельсія" } ?? reading.title)
    }
}

enum VenusWave {
    static func position(fraction: Double, state: VenusFlowState, phase: Double) -> Double? {
        guard fraction.isFinite, phase.isFinite, (0...1).contains(fraction), (0...1).contains(phase) else { return nil }
        switch state {
        case .charging: return fraction + (1 - fraction) * phase
        case .supplyingHome: return fraction * (1 - phase)
        case .mains, .standby, .unknown: return nil
        }
    }
    static func selfCheck() throws {
        guard position(fraction: 0.63, state: .charging, phase: 0) == 0.63,
              position(fraction: 0.63, state: .charging, phase: 1) == 1,
              position(fraction: 0.63, state: .supplyingHome, phase: 0) == 0.63,
              position(fraction: 0.63, state: .supplyingHome, phase: 1) == 0,
              position(fraction: 0.63, state: .unknown, phase: 0.5) == nil,
              position(fraction: 1, state: .standby, phase: 0.5) == nil,
              position(fraction: .nan, state: .charging, phase: 0.5) == nil else {
            throw VenusStoreError.message("SOC wave direction regression")
        }
    }
}

struct VenusSOCOrb: View {
    let value: Double?
    let fresh: Bool
    let flow: VenusFlowState
    let status: String
    var diameter: CGFloat = 180
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    private var fraction: Double? {
        guard let value, value.isFinite, (0...100).contains(value) else { return nil }
        return value / 100
    }
    private var moving: Bool { visible && !reduceMotion && fresh && fraction != nil && (flow == .charging || flow == .supplyingHome) }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !moving)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3
            let wave = moving ? fraction.flatMap { VenusWave.position(fraction: $0, state: flow, phase: phase) } : nil
            let accent = VenusVisuals.accent(flow, fresh: fresh)
            ZStack {
                Circle().fill(LinearGradient(colors: [.white.opacity(0.09), .black.opacity(0.12), .white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing)).padding(5)
                Circle().stroke(LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0.035), .white.opacity(0.17)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8).padding(5)
                Circle().stroke(.white.opacity(0.09), lineWidth: 1).padding(13)
                Circle().stroke(.white.opacity(0.055), lineWidth: 0.7).padding(24)
                if let fraction {
                    Circle().trim(from: 0, to: fraction)
                        .stroke(fresh && flow != .unknown ? accent.opacity(0.2) : .clear, lineWidth: 10)
                        .rotationEffect(.degrees(-90)).padding(13).blur(radius: 4)
                    Circle().trim(from: 0, to: fraction)
                        .stroke(fresh && flow != .unknown ? accent : .white.opacity(0.25), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(13)
                }
                if let wave {
                    Circle().trim(from: max(0, wave - 0.02), to: min(1, wave + 0.02))
                        .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(13)
                        .shadow(color: .white.opacity(0.35), radius: 3)
                }
                VStack(spacing: 8) {
                    if fraction != nil {
                        Text(VenusVisuals.soc(value)).font(.system(size: 39, weight: .medium, design: .rounded))
                            .monospacedDigit().foregroundStyle(.white.opacity(fresh ? 1 : 0.5))
                    } else {
                        VenusSoftPlaceholder(width: 48, height: 6).frame(height: 47)
                    }
                    Text(status).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(fresh ? accent : .white.opacity(0.45))
                        .multilineTextAlignment(.center).lineLimit(2).frame(width: diameter - 45)
                }.padding(.top, 3)
            }
        }.frame(width: diameter, height: diameter)
            .background(VenusViewActivity(isActive: $visible)).onDisappear { visible = false }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Заряд батареї \(VenusVisuals.soc(value)). \(status)")
    }
}

struct VenusStationFascia: View {
    let soc: Double?
    let fresh: Bool
    let flow: VenusFlowState
    var model: VenusModel = .venusE
    var ctConnected: Bool? = nil
    var bluetoothConnected: Bool? = nil
    var wifiIP: String? = nil
    var gridPowerW: Double? = nil
    var offgridPowerW: Double? = nil
    var pvPowerW: Double? = nil
    var apiOnline = false
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    private var fraction: Double? {
        guard let soc, soc.isFinite, (0...100).contains(soc) else { return nil }
        return soc / 100
    }
    private var moving: Bool { visible && !reduceMotion && fresh && fraction != nil && (flow == .charging || flow == .supplyingHome) }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !moving)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3
            let wave = moving ? fraction.flatMap { VenusWave.position(fraction: $0, state: flow, phase: phase) } : nil
            ZStack {
                Canvas { drawing, size in
                    let top: CGFloat = compact ? 17 : 27
                    let front = Path(roundedRect: CGRect(x: 7, y: top, width: size.width - 14, height: compact ? 30 : 36), cornerRadius: 9)
                    drawing.fill(front, with: .color(.black.opacity(0.1)))
                    drawing.stroke(front, with: .color(.white.opacity(0.16)), lineWidth: 0.7)
                    var upper = Path()
                    upper.move(to: CGPoint(x: 9, y: top + 1)); upper.addLine(to: CGPoint(x: 28, y: compact ? 6 : 11))
                    upper.addQuadCurve(to: CGPoint(x: size.width - 28, y: compact ? 6 : 11), control: CGPoint(x: size.width / 2, y: compact ? 1 : 4))
                    upper.addLine(to: CGPoint(x: size.width - 9, y: top + 1))
                    drawing.stroke(upper, with: .color(.white.opacity(0.13)), lineWidth: 0.8)
                    var inner = Path()
                    inner.move(to: CGPoint(x: 25, y: top - 3)); inner.addLine(to: CGPoint(x: 39, y: compact ? 9 : 15))
                    inner.addLine(to: CGPoint(x: size.width - 39, y: compact ? 9 : 15)); inner.addLine(to: CGPoint(x: size.width - 25, y: top - 3))
                    drawing.stroke(inner, with: .color(.white.opacity(0.055)), lineWidth: 0.6)
                }
                HStack(alignment: .top, spacing: 10) {
                    if model != .venusA { led("WARN", lit: nil, help: "WARN — попередження станції. Стан індикатора недоступний; пунктир не означає, що попереджень немає.") }
                    led("GRID", evidence: .grid(soc: fresh ? soc : nil, gridPowerW: gridPowerW,
                                                offgridPowerW: offgridPowerW, flow: flow, apiOnline: apiOnline))
                    led("BACKUP", evidence: .backup(soc: fresh ? soc : nil, offgridPowerW: offgridPowerW,
                                                    model: model, apiOnline: apiOnline))
                    VStack(spacing: 7) {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.7)
                                if let fraction { Capsule().fill(.white.opacity(fresh ? 0.9 : 0.25)).frame(width: geometry.size.width * fraction) }
                                if let wave {
                                    Capsule().fill(LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: 18).offset(x: max(0, min(geometry.size.width - 18, geometry.size.width * wave - 9)))
                                        .shadow(color: .white.opacity(0.55), radius: 3)
                                }
                            }
                        }.frame(height: 4)
                        Text("BATTERY").font(.system(size: 7, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                    }.frame(maxWidth: .infinity)
                        .help("BATTERY — заряд акумулятора: \(VenusVisuals.soc(soc)). Світла смуга показує частку заряду; рух — напрямок заряду або розряду.")
                    if model == .venusA {
                        led("PV", evidence: .pv(powerW: pvPowerW, apiOnline: apiOnline))
                    } else {
                        led("CT", lit: ctConnected, help: "З’єднання CT за API: \(connectionText(ctConnected)). Фізичний LED не зчитується.")
                    }
                    led("WIFI", lit: wifiIP.map { $0 != "0.0.0.0" }, help: wifiIP.map { "Wi-Fi — станція отримала адресу \($0). З’єднання підтверджене її останньою відповіддю." } ?? "Wi-Fi — очікуємо актуальне підтвердження з’єднання. Пунктир означає відсутність даних.")
                    if model != .venusA {
                        led("BT", lit: bluetoothConnected, help: "Bluetooth за API: \(connectionText(bluetoothConnected)). Фізичний LED не зчитується.")
                    }
                }.padding(.horizontal, 25).padding(.top, compact ? 19 : 29)
            }
        }.frame(height: compact ? 52 : 72)
            .background(VenusViewActivity(isActive: $visible)).onDisappear { visible = false }
    }
    private func led(_ title: String, lit: Bool?, help: String) -> some View {
        VStack(spacing: 7) {
            Capsule().fill(.white.opacity(lit == true ? 0.95 : lit == false ? 0.08 : 0))
                .overlay(Capsule().strokeBorder(.white.opacity(lit == true ? 0.7 : 0.3),
                    style: StrokeStyle(lineWidth: 0.6, dash: lit == nil ? [1, 1] : [])))
                .frame(width: 12, height: 3)
                .shadow(color: .white.opacity(lit == true ? 0.35 : 0), radius: 3)
            Text(title).font(.system(size: 7, weight: .medium)).foregroundStyle(.white.opacity(0.55))
        }.frame(width: title == "BACKUP" ? 37 : 28).help(help)
            .accessibilityElement(children: .ignore).accessibilityLabel(help)
    }
    private func led(_ title: String, evidence: VenusIndicatorEvidence) -> some View {
        let confirmed = evidence.level == .confirmedOn
        let estimated = evidence.level == .estimatedOn
        let unavailable = evidence.level == .unavailable
        return VStack(spacing: 7) {
            Capsule().fill(.white.opacity(confirmed ? 0.95 : estimated ? 0.5 : 0))
                .overlay(Capsule().strokeBorder(.white.opacity(confirmed ? 0.7 : estimated ? 0.4 : unavailable ? 0.3 : 0.18),
                    style: StrokeStyle(lineWidth: 0.6, dash: confirmed || estimated ? [] : unavailable ? [1, 1] : [2, 1])))
                .frame(width: 12, height: 3)
                .shadow(color: .white.opacity(confirmed ? 0.35 : estimated ? 0.16 : 0), radius: confirmed ? 3 : 2)
            Text(title).font(.system(size: 7, weight: .medium)).foregroundStyle(.white.opacity(0.55))
        }.frame(width: title == "BACKUP" ? 37 : 28).help(evidence.explanation)
            .accessibilityElement(children: .ignore).accessibilityLabel(evidence.explanation)
    }
    private func connectionText(_ value: Bool?) -> String { value.map { $0 ? "підключено" : "не підключено" } ?? "невідоме" }
}
