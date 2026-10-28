import SwiftUI

@MainActor
struct VenusOnboarding: View {
    @ObservedObject private var localization = VenusLocalization.shared
    @ObservedObject var store: VenusStore
    var onConnected: () -> Void = {}
    @State private var selectedLanguage = VenusLanguage.uk
    @State private var step = 0
    @State private var address = ""
    @State private var port = "30000"
    @State private var formMessage: String?
    @State private var imageExpanded = false
    @State private var manualExpanded = false
    @State private var helpShown = false
    @State private var didSearch = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var addressFocused: Bool
    private var stepNames: [String] { [VL("Станція", "Station"), "Local API", VL("Пошук", "Discovery")] }

    var body: some View {
        Group {
            if !localization.hasChosen { languageChoice }
            else if helpShown { VenusHelp(height: 430) { helpShown = false } }
            else if imageExpanded { expandedImage }
            else {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    steps
                    ScrollViewReader { scroll in
                        VenusVerticalScroll {
                            Group {
                                if step == 2 { connection }
                                else { instructions }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                                .id(step)
                                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
                        }.frame(maxHeight: 220)
                            .onChange(of: manualExpanded) { expanded in
                                guard expanded else { return }
                                DispatchQueue.main.async {
                                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                        scroll.scrollTo("manualConnection", anchor: .top)
                                    }
                                }
                            }
                    }
                    Spacer(minLength: 0)
                    footer
                }.padding(24)
            }
        }
        .frame(width: 520, height: 430)
        .foregroundStyle(.white).tint(.white)
        .preferredColorScheme(.dark).background(.clear)
        .environment(\.locale, localization.language.locale)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: step)
        .onChange(of: store.isDiscovering) { searching in
            if !searching && didSearch && store.discoveredDevices.isEmpty && store.error != nil {
                manualExpanded = true
            }
        }
        .onAppear {
            if let configuration = store.configuration {
                address = configuration.ip
                port = String(configuration.port)
            }
        }
    }

    private var languageChoice: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "globe").font(.system(size: 34, weight: .light))
            Text("Оберіть мову\nChoose your language").font(.system(size: 24, weight: .semibold))
            Text("Мову можна змінити в налаштуваннях.\nYou can change it later in Settings.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
            Picker("Мова / Language", selection: $selectedLanguage) {
                Text("Українська").tag(VenusLanguage.uk)
                Text("English").tag(VenusLanguage.en)
                Text("Суржик").tag(VenusLanguage.surzhyk)
            }.pickerStyle(.segmented)
            Spacer(minLength: 0)
            Button { localization.choose(selectedLanguage) } label: {
                Text("Продовжити / Continue").frame(maxWidth: .infinity)
            }.buttonStyle(VenusButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
        }.padding(28)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(VL("Підключімо Marstek", "Connect your Marstek")).font(.system(size: 22, weight: .semibold))
                Text(VL("Mac і станція мають бути в одній мережі.", "Your Mac and station must be on the same network."))
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
                .accessibilityLabel(VL("Крок \(index + 1): \(stepNames[index])", "Step \(index + 1): \(stepNames[index])"))
                .accessibilityAddTraits(index == step ? .isSelected : [])
            }
        }
    }

    private var instructions: some View {
        HStack(alignment: .center, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text(step == 0 ? VL("Відкрий станцію", "Open your station") : VL("Увімкни Local API", "Enable Local API"))
                    .font(.system(size: 18, weight: .semibold))
                Text(step == 0
                     ? VL("У застосунку Marstek відкрий свою станцію, потім натисни налаштування у верхньому куті.", "Open your station in the Marstek app, then tap Settings in the top corner.")
                     : VL("Увімкни Local API й подивись число в полі Ports. У VenusBar потрібно ввести саме цей порт.", "Enable Local API and check the number in Ports. Enter that same port in VenusBar."))
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
                if step == 0 {
                    Label(VL("Налаштування", "Settings"), systemImage: "gearshape")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                } else {
                    Text(VL("Розташування пунктів може відрізнятися залежно від версії застосунку.", "The menu layout may vary between app versions."))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            illustration(width: 218, height: 180)
        }.frame(minHeight: 196).padding(.top, 2)
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !manualExpanded {
                VStack(alignment: .leading, spacing: 5) {
                    Text(VL("Знайдемо станцію самі", "Let’s find your station")).font(.system(size: 18, weight: .semibold))
                    Text(VL("Увімкни Local API та вкажи порт із MARSTEK → Local API → Ports.", "Enable Local API and use the port from MARSTEK → Local API → Ports."))
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                }
                HStack(alignment: .bottom, spacing: 12) {
                    Button(action: scan) {
                        HStack(spacing: 9) {
                            Image(systemName: "magnifyingglass")
                            Text(scanTitle)
                            if store.isDiscovering { ProgressView().controlSize(.small).tint(.black).accessibilityLabel(VL("Пошук станції", "Finding station")) }
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(VenusButtonStyle(primary: true)).disabled(busy)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(VL("Порт", "Port")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                        TextField("30000", text: $port).textFieldStyle(VenusTextFieldStyle()).onSubmit(scan)
                            .accessibilityLabel(VL("Порт Local API", "Local API port"))
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
            }
            Button { manualExpanded.toggle() } label: {
                HStack {
                    Label(manualExpanded ? VL("Повернутися до пошуку", "Back to discovery") : VL("Ввести IP-адресу", "Enter IP address"), systemImage: manualExpanded ? "arrow.left" : "network")
                    Spacer(minLength: 8)
                    if !manualExpanded { Image(systemName: "chevron.down") }
                }.frame(maxWidth: .infinity).contentShape(Rectangle())
            }.buttonStyle(VenusButtonStyle(compact: true))
                .accessibilityValue(manualExpanded ? VL("Розгорнуто", "Expanded") : VL("Згорнуто", "Collapsed"))
                .id("manualConnection")
            if manualExpanded {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .bottom, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(VL("IP-адреса", "IP address")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                            TextField("192.168.1.100", text: $address)
                                .textFieldStyle(VenusTextFieldStyle()).onSubmit(connectManually)
                                .focused($addressFocused)
                                .accessibilityLabel(VL("IP-адреса станції", "Station IP address"))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(VL("Порт", "Port")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                            TextField("30000", text: $port).textFieldStyle(VenusTextFieldStyle()).onSubmit(connectManually)
                                .accessibilityLabel(VL("Порт Local API", "Local API port"))
                        }.frame(width: 84)
                        Button(VL("Підключити", "Connect"), action: connectManually)
                            .buttonStyle(VenusButtonStyle(primary: true))
                            .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                    }
                    VenusConnectionHints()
                }.transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                    .onAppear { addressFocused = true }
            }
            if let message = formMessage ?? store.error {
                VStack(alignment: .leading, spacing: 6) {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(VL("Перевір IP-адресу й порт, тоді натисни «Підключити». Або повтори автоматичний пошук.", "Check the IP address and port, then click Connect. Or try automatic discovery again."))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if #available(macOS 15, *) {
                    Text(VL("Доступ на Mac: Системні параметри → Приватність і безпека → Локальна мережа → VenusBar. Після дозволу повтори пошук.", "Mac permission: System Settings → Privacy & Security → Local Network → VenusBar. After allowing access, search again."))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VenusLocalAPIHelpLink(model: store.model)
        }.padding(.top, 2)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: manualExpanded)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step == 0 {
                Button { step = 2 } label: { Text(VL("Уже ввімкнено", "Already enabled")).frame(minWidth: 128) }
                    .buttonStyle(VenusButtonStyle())
            } else {
                Button { step -= 1; formMessage = nil } label: { Text(VL("Назад", "Back")).frame(minWidth: 128) }
                    .buttonStyle(VenusButtonStyle())
            }
            Spacer(minLength: 0)
            if step < 2 {
                Button { step += 1; formMessage = nil } label: { Text(VL("Далі", "Next")).frame(minWidth: 128) }
                    .buttonStyle(VenusButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
            } else {
                Button { helpShown = true } label: { Text(VL("Як користуватися", "How to use")).frame(minWidth: 128) }
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
            .help(VL("Збільшити схему налаштування", "Enlarge setup diagram"))
            .accessibilityLabel(VL("Збільшити ілюстрацію кроку \(step + 1)", "Enlarge step \(step + 1) illustration"))
    }

    private var expandedImage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(step == 0 ? VL("Де відкрити налаштування", "Where to find Settings") : VL("Увімкнення Local API", "Enabling Local API")).font(.system(size: 18, weight: .semibold))
                Spacer()
                Button { imageExpanded = false } label: { Text(VL("Назад", "Back")).frame(minWidth: 128) }
                    .buttonStyle(VenusButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            VenusSetupIllustration(step: step).frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(VL("Схематичний приклад. Розташування пунктів може відрізнятися залежно від версії застосунку Marstek.", "Schematic example. The menu layout may vary between versions of the Marstek app."))
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
        }.padding(24)
    }

    private var busy: Bool { store.isDiscovering || store.isReading || store.commandBusy }
    private var scanTitle: String {
        if store.isDiscovering { return VL("Шукаємо станцію…", "Finding your station…") }
        if didSearch && store.discoveredDevices.isEmpty && store.error != nil { return VL("Спробувати ще раз", "Try again") }
        return VL("Шукати автоматично", "Find automatically")
    }

    private func scan() {
        guard !busy else { return }
        guard let value = Self.validPort(port) else { formMessage = VL("UDP-порт має бути числом від 1024 до 65535.", "UDP port must be a number from 1024 to 65535."); return }
        formMessage = nil; didSearch = true
        store.discover(port: value)
    }
    private func connectManually() {
        guard !busy else { return }
        guard let value = Self.validPort(port) else { formMessage = VL("UDP-порт має бути числом від 1024 до 65535.", "UDP port must be a number from 1024 to 65535."); return }
        connect(ip: address, port: value, model: .unknown)
    }
    private func connect(ip: String, port: Int, model: VenusModel) {
        do { try store.configure(ip: ip, port: port, model: model); formMessage = nil; onConnected() }
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
    @ObservedObject private var localization = VenusLocalization.shared
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
            Text(step == 0 ? VL("Станція", "Station") : VL("Налаштування", "Settings"))
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
            Text(VL("Натисни шестерню вгорі", "Tap the gear at the top"))
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
                Text(VL("Порт", "Port")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                Spacer()
                Text("30000").font(.system(size: 12, weight: .medium, design: .monospaced))
            }.frame(height: 28)
        }.padding(.horizontal, 13).padding(.vertical, 6)
            .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 13))
    }
}
