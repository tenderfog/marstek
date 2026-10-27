import SwiftUI

@MainActor
struct VenusOnboarding: View {
    @ObservedObject var store: VenusStore
    @State private var step = 0
    @State private var address = ""
    @State private var port = "30000"
    @State private var formMessage: String?
    @State private var imageExpanded = false
    @State private var manualExpanded = false
    @State private var helpShown = false
    @State private var didSearch = false
    private let stepNames = ["Станція", "Local API", "Пошук"]

    var body: some View {
        Group {
            if helpShown { VenusHelp { helpShown = false } }
            else if imageExpanded { expandedImage }
            else {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    steps
                    ScrollView {
                        Group {
                            if step == 2 { connection }
                            else { instructions }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.scrollIndicators(.hidden).frame(maxHeight: 220)
                    Spacer(minLength: 0)
                    footer
                }.padding(24)
            }
        }
        .frame(width: 520, height: 430)
        .foregroundStyle(.white).tint(.white)
        .preferredColorScheme(.dark).background(.clear)
        .onAppear {
            if let configuration = store.configuration {
                address = configuration.ip
                port = String(configuration.port)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Підключімо Marstek").font(.system(size: 22, weight: .semibold))
                Text("Mac і станція мають бути в одній мережі.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 0)
            Image(systemName: "wifi").font(.system(size: 23, weight: .light))
                .foregroundStyle(.white.opacity(0.8)).padding(.top, 5).accessibilityHidden(true)
        }
    }

    private var steps: some View {
        HStack(spacing: 7) {
            ForEach(0..<3) { index in
                Button {
                    step = index
                    formMessage = nil
                } label: {
                    HStack(spacing: 7) {
                        Text("\(index + 1)").fontWeight(.semibold).monospacedDigit()
                            .foregroundStyle(index == step ? Color.black : .white.opacity(0.5))
                        Text(stepNames[index]).lineLimit(1)
                    }.frame(maxWidth: .infinity)
                        .foregroundStyle(index == step ? Color.black : .white.opacity(0.6))
                }
                .buttonStyle(VenusButtonStyle(primary: index == step, compact: true))
                .accessibilityLabel("Крок \(index + 1): \(stepNames[index])")
                .accessibilityAddTraits(index == step ? .isSelected : [])
            }
        }
    }

    private var instructions: some View {
        HStack(alignment: .center, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text(step == 0 ? "Відкрий станцію" : "Увімкни Local API")
                    .font(.system(size: 18, weight: .semibold))
                Text(step == 0
                     ? "У застосунку Marstek відкрий свою станцію, потім натисни налаштування у верхньому куті."
                     : "Знайди Local API й увімкни перемикач. У полі Ports залиш 30000 або вкажи свій порт.")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
                if step == 0 {
                    Label("Налаштування", systemImage: "gearshape")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                } else {
                    Text("Розташування пунктів може відрізнятися залежно від версії застосунку.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            illustration(width: 218, height: 180)
        }.frame(minHeight: 196).padding(.top, 2)
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Знайдемо станцію самі").font(.system(size: 18, weight: .semibold))
                Text("Увімкни Local API. Модель визначиться автоматично.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                VenusLocalAPIHelpLink(model: store.model)
            }
            HStack(alignment: .bottom, spacing: 12) {
                Button(action: scan) {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass")
                        Text(scanTitle)
                        if store.isDiscovering { ProgressView().controlSize(.small).tint(.black).accessibilityLabel("Пошук станції") }
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(VenusButtonStyle(primary: true)).disabled(busy)
                VStack(alignment: .leading, spacing: 4) {
                    Text("UDP-порт").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    TextField("30000", text: $port).textFieldStyle(VenusTextFieldStyle()).onSubmit(scan)
                        .accessibilityLabel("UDP-порт Local API")
                }.frame(width: 92)
            }
            if !store.discoveredDevices.isEmpty {
                ForEach(store.discoveredDevices) { device in
                    Button {
                        connect(ip: device.ip, port: device.port, model: VenusModel.identify(device.name))
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "bolt.horizontal.circle")
                            Text(device.name).fontWeight(.medium)
                            Spacer(minLength: 8)
                            Text(device.ip).font(.system(size: 12)).monospacedDigit().foregroundStyle(.white.opacity(0.65))
                            Image(systemName: "arrow.right")
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(VenusButtonStyle()).disabled(busy)
                }
            }
            DisclosureGroup(isExpanded: $manualExpanded) {
                HStack(spacing: 10) {
                    TextField("IP-адреса станції", text: $address)
                        .textFieldStyle(VenusTextFieldStyle()).onSubmit(connectManually)
                    Button("Підключити", action: connectManually)
                        .buttonStyle(VenusButtonStyle(primary: true))
                        .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                }.padding(.top, 8)
            } label: {
                Text("Ввести IP вручну").font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7)).frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .contentShape(Rectangle())
            }
            if let message = formMessage ?? store.error {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.top, 2)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step == 0 {
                Button { step = 2 } label: { Text("Уже ввімкнено").frame(minWidth: 128) }
                    .buttonStyle(VenusButtonStyle())
            } else {
                Button { step -= 1; formMessage = nil } label: { Text("Назад").frame(minWidth: 128) }
                    .buttonStyle(VenusButtonStyle())
            }
            Spacer(minLength: 0)
            if step < 2 {
                Button { step += 1; formMessage = nil } label: { Text("Далі").frame(minWidth: 128) }
                    .buttonStyle(VenusButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
            } else {
                Button { helpShown = true } label: { Text("Як користуватися").frame(minWidth: 128) }
                    .buttonStyle(VenusButtonStyle())
            }
        }.frame(height: 44)
    }

    private func illustration(width: CGFloat, height: CGFloat) -> some View {
        Button { imageExpanded = true } label: {
            VenusSetupIllustration(step: step)
                .frame(width: width, height: height)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .medium)).frame(width: 36, height: 36)
                }
        }.buttonStyle(.plain)
            .help("Збільшити схему налаштування")
            .accessibilityLabel("Збільшити ілюстрацію кроку \(step + 1)")
    }

    private var expandedImage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(step == 0 ? "Де відкрити налаштування" : "Увімкнення Local API").font(.system(size: 18, weight: .semibold))
                Spacer()
                Button { imageExpanded = false } label: { Text("Назад").frame(minWidth: 128) }
                    .buttonStyle(VenusButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            VenusSetupIllustration(step: step).frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("Схематичний приклад. Розташування пунктів може відрізнятися залежно від версії застосунку Marstek.")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
        }.padding(24)
    }

    private var busy: Bool { store.isDiscovering || store.isReading || store.commandBusy }
    private var scanTitle: String {
        if store.isDiscovering { return "Шукаємо станцію…" }
        if didSearch && store.discoveredDevices.isEmpty && store.error != nil { return "Спробувати ще раз" }
        return "Шукати автоматично"
    }

    private func scan() {
        guard !busy else { return }
        guard let value = Self.validPort(port) else { formMessage = "UDP-порт має бути числом від 1024 до 65535."; return }
        formMessage = nil; didSearch = true
        store.discover(port: value)
    }
    private func connectManually() {
        guard !busy else { return }
        guard let value = Self.validPort(port) else { formMessage = "UDP-порт має бути числом від 1024 до 65535."; return }
        connect(ip: address, port: value, model: .unknown)
    }
    private func connect(ip: String, port: Int, model: VenusModel) {
        do { try store.configure(ip: ip, port: port, model: model); formMessage = nil }
        catch { formMessage = error.localizedDescription }
    }
    private static func validPort(_ text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let port = Int(value), (1024...65535).contains(port) else { return nil }
        return port
    }
    static func selfCheck() throws {
        guard validPort("30000") == 30000, validPort(" 65535 ") == 65535,
              ["1023", "65536", "-30000", "30.0", "", "+30000"].allSatisfy({ validPort($0) == nil }) else {
            throw VenusStoreError.message("Onboarding port validation regression")
        }
    }
}

/// An original, deliberately schematic guide; no manufacturer screenshots or assets.
private struct VenusSetupIllustration: View {
    let step: Int

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 218, geometry.size.height / 180)
            VStack(spacing: 14) {
                header
                if step == 0 { station } else { localAPI }
                Spacer(minLength: 0)
            }
            .padding(16).frame(width: 218, height: 180)
            .background(RoundedRectangle(cornerRadius: 22).fill(.white.opacity(0.035)))
            .scaleEffect(scale)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }.accessibilityHidden(true)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if step != 0 {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            }
            Text(step == 0 ? "Станція" : "Налаштування")
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 0)
            if step == 0 {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium)).foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(.white, in: RoundedRectangle(cornerRadius: 11))
                    .shadow(color: .white.opacity(0.12), radius: 10)
            }
        }.frame(height: 34)
    }

    private var station: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black.opacity(0.3))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.17), lineWidth: 1))
                Capsule().fill(.white.opacity(0.8)).frame(width: 63, height: 2).padding(.top, 15)
                HStack(spacing: 8) {
                    ForEach(["powerplug", "battery.75percent", "wifi"], id: \.self) { symbol in
                        Image(systemName: symbol).font(.system(size: 9, weight: .light))
                    }
                }.foregroundStyle(.white.opacity(0.45)).padding(.top, 30)
            }.frame(width: 126, height: 65)
            Text("Натисни шестерню вгорі")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
        }.frame(maxWidth: .infinity)
    }

    private var localAPI: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Local API").font(.system(size: 12, weight: .medium))
                Spacer()
                Capsule().fill(.white).frame(width: 34, height: 20)
                    .overlay(alignment: .trailing) {
                        Circle().fill(.black.opacity(0.8)).frame(width: 16, height: 16).padding(2)
                    }
            }.frame(height: 32)
            Rectangle().fill(.white.opacity(0.09)).frame(height: 0.5).padding(.vertical, 5)
            HStack {
                Text("Порт").font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                Spacer()
                Text("30000").font(.system(size: 12, weight: .medium, design: .monospaced))
            }.frame(height: 28)
        }.padding(.horizontal, 13).padding(.vertical, 6)
            .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 13))
    }
}
