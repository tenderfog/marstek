import SwiftUI

@MainActor
struct VenusMiniOutageTimeline: View {
    @ObservedObject private var localization = VenusLocalization.shared
    @ObservedObject var store: VenusOutagesStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Group {
                if store.selection == nil { setup }
                else { configured(at: context.date) }
            }
            .frame(width: 300, height: store.selection == nil ? 30 : 58)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText(at: context.date))
        }
    }

    private var setup: some View {
        HStack(spacing: 7) {
            Image(systemName: "bolt.slash").font(.system(size: 11, weight: .medium))
            Text(VL("Графік відключень", "Outage schedule")).font(.system(size: 11, weight: .medium))
            Spacer(minLength: 4)
            Text(VL("Додати адресу", "Add address")).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
        }.foregroundStyle(.white.opacity(0.7))
    }

    private func configured(at now: Date) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                Text(planSummary(at: now))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VenusOutageStyle.color(store.currentPlanState))
                    .lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Text(VL("Зараз \(clock(now))", "Now \(clock(now))")).font(.system(size: 9, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
            }.frame(height: 16)
            VStack(spacing: 2) {
                track(at: now).frame(height: 18)
                HStack(spacing: 0) {
                    Text("00"); Spacer(); Text("06"); Spacer(); Text("12"); Spacer(); Text("18"); Spacer(); Text("24")
                }.font(.system(size: 8)).monospacedDigit().foregroundStyle(.white.opacity(0.35)).frame(height: 10)
            }.frame(height: 30)
        }
    }

    private func track(at now: Date) -> some View {
        Canvas { context, size in
            let bar = CGRect(x: 0, y: 5.5, width: size.width, height: 7)
            let outline = Path(roundedRect: bar, cornerRadius: 3.5)
            var strip = context
            strip.clip(to: outline)
            strip.fill(outline, with: .color(.white.opacity(0.055)))
            for interval in store.todaySlots {
                let x = size.width * Double(interval.start) / 1440
                let width = size.width * Double(interval.end - interval.start) / 1440
                let color: Color
                switch interval.state {
                case .noOutagePlanned: color = VenusOutageStyle.color(.noOutagePlanned).opacity(0.8)
                case .outagePlanned: color = VenusOutageStyle.color(.outagePlanned).opacity(0.85)
                case .emergency: color = VenusOutageStyle.color(.emergency).opacity(0.55)
                case .unknown: color = .white.opacity(0.07)
                case .stale: color = .white.opacity(0.18)
                }
                strip.fill(Path(CGRect(x: x, y: bar.minY, width: width, height: bar.height)), with: .color(color))
            }
            let minute = Double(VenusOutagesReport.minute(at: now))
            let x = size.width * minute / 1440
            var marker = Path()
            marker.move(to: CGPoint(x: x, y: 1.5)); marker.addLine(to: CGPoint(x: x, y: 17))
            context.stroke(marker, with: .color(.white.opacity(0.95)), lineWidth: 1)
            context.fill(Path(ellipseIn: CGRect(x: x - 1.8, y: 0, width: 3.6, height: 3.6)), with: .color(.white))
        }
    }

    private func planSummary(at now: Date) -> String {
        let minute = VenusOutagesReport.minute(at: now)
        let end = store.todaySlots.first { $0.start <= minute && minute < $0.end }.map { VenusOutageInterval.time($0.end) }
        switch store.currentPlanState {
        case .noOutagePlanned: return end.map { VL("Світло до \($0)", "Power until \($0)") } ?? VL("Світло за графіком", "Power scheduled")
        case .outagePlanned: return end.map { VL("Без світла до \($0)", "Outage until \($0)") } ?? VL("Планове відключення", "Scheduled outage")
        case .emergency: return VL("аварійні відключення", "emergency outages")
        case .stale: return VL("потрібне оновлення", "update needed")
        case .unknown: return store.isLoading ? VL("оновлюємо дані", "updating") : VL("ще немає даних", "no data yet")
        }
    }

    private func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = VenusOutagesReport.kyivCalendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func accessibilityText(at now: Date) -> String {
        guard store.selection != nil else { return VL("Графік відключень не налаштований. Додай адресу в головній панелі.", "No outage schedule configured. Add an address in the main panel.") }
        return VL("Графік на сьогодні, київський час. Зараз \(clock(now)). \(store.statusLabel). \(store.isCached ? "Збережений графік. " : "")Біла позначка показує поточний час. Це план оператора, не фактична наявність електрики.", "Today’s schedule, Kyiv time. Now \(clock(now)). \(store.statusLabel). \(store.isCached ? "Saved schedule. " : "")The white marker shows the current time. This is the operator’s plan, not actual power availability.")
    }
}

@MainActor
struct VenusTodayOutageCard: View {
    @ObservedObject private var localization = VenusLocalization.shared
    @ObservedObject var store: VenusOutagesStore
    let onOpen: () -> Void
    @State private var hovered = false

    var body: some View {
        if store.selection != nil {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Button(action: onOpen) {
                    content(at: context.date)
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 124, maxHeight: 124, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(LinearGradient(colors: [cardAccent.opacity(0.13), cardAccent.opacity(0.025), .clear],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                        .modifier(SwiftfulUICardSurface(backgroundColor: .black.opacity(hovered ? 0.12 : 0.18),
                                                       borderColor: .clear, borderWidth: 0, cornerRadius: 18))
                }
                    .buttonStyle(VenusOutageCardButtonStyle())
                    .frame(maxWidth: .infinity, minHeight: 124, maxHeight: 124, alignment: .leading)
                    .contentShape(RoundedRectangle(cornerRadius: 18))
                    .onHover { hovered = $0 }
                    .help(VL("План оператора за київським часом. Натисни, щоб відкрити повний графік.", "The operator’s plan in Kyiv time. Click to open the full schedule."))
            }
        }
    }

    private func content(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(headline(at: now)).font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.95)).lineLimit(1).minimumScaleFactor(0.85)
                    Spacer(minLength: 2)
                    HStack(spacing: 5) {
                        Text(VL("За графіком", "Scheduled"))
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                    }.font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Text(store.selection?.addressLabel ?? "").font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5)).lineLimit(1).truncationMode(.tail)
            }
            intervals(at: now)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func intervals(at now: Date) -> some View {
        if store.currentPlanState == .emergency {
            Text(VL("Екстрені відключення: погодинний план може не діяти.", "Emergency outages: the hourly plan may not apply."))
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
        } else if !store.nextIntervals(limit: 3).isEmpty {
            HStack(spacing: 10) {
                ForEach(store.nextIntervals(limit: 3)) { interval in
                    let state = displayState(interval.state)
                    let minute = VenusOutagesReport.minute(at: now)
                    let current = interval.start <= minute && minute < interval.end
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Image(systemName: state == .noOutagePlanned ? "bolt.fill" : VenusOutageStyle.symbol(state))
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(VenusOutageStyle.color(state))
                            Text(interval.timeRange).font(.system(size: 12, weight: .medium)).monospacedDigit()
                                .foregroundStyle(.white.opacity(current ? 0.95 : 0.7))
                                .lineLimit(1).minimumScaleFactor(0.85)
                        }
                        HStack(spacing: 5) {
                            if current { Circle().fill(cardAccent).frame(width: 3, height: 3) }
                            Text(current ? VL("Зараз", "Now") : intervalLabel(state))
                                .font(.system(size: 10)).foregroundStyle(.white.opacity(current ? 0.65 : 0.5))
                        }
                    }.padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .modifier(SwiftfulUICardSurface(backgroundColor: .white.opacity(current ? 0.065 : 0.025),
                                                       borderColor: .clear, borderWidth: 0, cornerRadius: 11))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(current ? VL("Зараз. ", "Now. ") : "")\(interval.timeRange). \(state.label)")
                }
            }
        } else {
            Text(store.error ?? (store.isLoading ? VL("Оновлюємо графік…", "Updating schedule…") : VL("Точні інтервали ще недоступні", "Exact intervals are not available yet")))
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
        }
    }

    private var cardAccent: Color { VenusOutageStyle.color(store.currentPlanState) }

    private func intervalLabel(_ state: VenusOutagePlanState) -> String {
        switch state {
        case .noOutagePlanned: return VL("Світло є", "Power on")
        case .outagePlanned: return VL("Без світла", "Power off")
        case .unknown, .stale, .emergency: return state.label
        }
    }

    private func headline(at now: Date) -> String {
        let minute = VenusOutagesReport.minute(at: now)
        let end = store.todaySlots.first(where: { $0.start <= minute && minute < $0.end }).map { VenusOutageInterval.time($0.end) }
        switch store.currentPlanState {
        case .noOutagePlanned: return end.map { VL("Світло до \($0)", "Power until \($0)") } ?? VL("Світло є", "Power scheduled")
        case .outagePlanned: return end.map { VL("Немає світла до \($0)", "No power until \($0)") } ?? VL("Немає світла", "Scheduled outage")
        case .unknown, .stale, .emergency: return store.statusLabel
        }
    }

    private func displayState(_ state: VenusOutagePlanState) -> VenusOutagePlanState {
        switch store.currentPlanState {
        case .stale, .emergency, .unknown: return store.currentPlanState
        case .noOutagePlanned, .outagePlanned: return state
        }
    }
}

private struct VenusOutageCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(SwiftfulUIPressFeedback(isPressed: configuration.isPressed, scale: 0.995, opacity: 0.88))
    }
}

@MainActor
struct VenusOutagesSettings: View {
    @ObservedObject private var localization = VenusLocalization.shared
    @ObservedObject var store: VenusOutagesStore
    let onBack: () -> Void
    @State private var cityQuery = ""
    @State private var streetQuery = ""
    @State private var houseQuery = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Button(action: onBack) { Label(VL("Назад", "Back"), systemImage: "chevron.left") }
                    .buttonStyle(VenusButtonStyle())
                Text(VL("Графіки відключень", "Outage schedules")).font(.system(size: 17, weight: .semibold))
                Spacer(minLength: 0)
            }.frame(height: 44)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if store.selection != nil { savedSchedule }
                    addressForm
                    if let error = store.error {
                        Text(error).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if store.isLoading || store.isSearching {
                        Text(store.isSearching ? VL("Шукаємо в офіційному переліку…", "Searching the official directory…") : VL("Оновлюємо графік…", "Updating schedule…"))
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    }
                    HStack(spacing: 7) {
                        Link(VL("Джерело ↗", "Source ↗"), destination: store.sourceURL)
                        Text(VL("План оператора, не фактичне живлення.", "The operator’s plan, not actual power availability."))
                            .foregroundStyle(.white.opacity(0.45))
                    }.font(.system(size: 10))
                }.padding(.vertical, 2).padding(.trailing, 3)
            }.scrollIndicators(.automatic)
        }
        .padding(24).frame(width: 520, height: 610, alignment: .topLeading)
        .foregroundStyle(.white).background(.clear).preferredColorScheme(.dark)
        .onAppear {
            store.loadRegions()
            if cityQuery.isEmpty { cityQuery = store.selectedCity?.name ?? "" }
            if streetQuery.isEmpty { streetQuery = store.selectedStreet?.name ?? "" }
            if houseQuery.isEmpty { houseQuery = store.selectedHouse?.name ?? "" }
        }
    }

    private var addressForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.selection != nil {
                Button(VL("Змінити адресу", "Change address")) {
                    store.clearSelection(); cityQuery = ""; streetQuery = ""; houseQuery = ""
                }.buttonStyle(VenusButtonStyle())
            } else {
                Text(VL("Адреса для графіка", "Schedule address")).font(.system(size: 15, weight: .semibold))
                Text(VL("Обери місто й оператора, потім введи вулицю та будинок.", "Choose a region and operator, then enter the street and building."))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                regionMenu
                if store.regions.isEmpty && !store.isSearching {
                    Button(VL("Спробувати ще раз", "Try again"), action: store.loadRegions).buttonStyle(VenusButtonStyle())
                }
                if store.selectedRegion != nil { dsoMenu }
                if store.selectedDSO != nil {
                    if store.selectedRegion?.hasCities == true { citySearch }
                    if store.selectedRegion?.hasCities != true || store.selectedCity != nil { addressSearch }
                    if store.selectedHouse != nil { groupSelection }
                }
            }
        }
    }

    private var regionMenu: some View {
        Menu {
            ForEach(store.regions) { region in
                Button(region.name) {
                    store.selectRegion(region); cityQuery = ""; streetQuery = ""; houseQuery = ""
                }
            }
        } label: { selectionLabel(store.selectedRegion?.name ?? VL("Обрати область", "Choose region")) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).disabled(store.regions.isEmpty)
    }

    private var dsoMenu: some View {
        Menu {
            ForEach(store.dsos) { dso in
                Button(dso.name) {
                    store.selectDSO(dso); cityQuery = ""; streetQuery = ""; houseQuery = ""
                }
            }
        } label: { selectionLabel(store.selectedDSO?.name ?? VL("Обрати оператора", "Choose operator")) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).disabled(store.dsos.isEmpty)
    }

    private var citySearch: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(VL("Місто", "City"), text: $cityQuery).textFieldStyle(VenusTextFieldStyle())
                .onChange(of: cityQuery) { query in
                    if query != store.selectedCity?.name { store.searchCities(query) }
                }
            if let selected = store.selectedCity { selectionSummary(selected.name) }
            else {
                ForEach(store.cities) { item in
                    addressResult(item, selected: false) {
                        store.selectCity(item); cityQuery = item.name; streetQuery = ""; houseQuery = ""
                    }
                }
            }
        }
    }

    private var addressSearch: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                Text(VL("Вулиця", "Street")).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                HStack(spacing: 5) {
                    TextField(VL("Назва вулиці", "Street name"), text: $streetQuery)
                        .textFieldStyle(VenusTextFieldStyle())
                        .onChange(of: streetQuery) { query in
                            if query != store.selectedStreet?.name {
                                store.searchStreets(query)
                                houseQuery = ""
                            }
                        }
                    if !streetQuery.isEmpty {
                        Button { streetQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15)).foregroundStyle(.white.opacity(0.5))
                                .frame(width: 28, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel(VL("Очистити вулицю", "Clear street"))
                    }
                }
                if store.selectedStreet == nil && !store.streets.isEmpty {
                    addressSuggestions(store.streets) { item in
                        store.selectStreet(item); streetQuery = item.name; houseQuery = store.houseHint ?? ""
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 7) {
                Text(VL("Будинок", "Building")).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                TextField(VL("№", "No."), text: $houseQuery)
                    .textFieldStyle(VenusTextFieldStyle())
                    .disabled(store.selectedStreet == nil)
                    .opacity(store.selectedStreet == nil ? 0.45 : 1)
                    .onChange(of: houseQuery) { query in
                        if store.selectedStreet != nil && query != store.selectedHouse?.name {
                            store.searchHouses(query)
                        }
                    }
                if store.selectedStreet != nil && store.selectedHouse == nil && !store.houses.isEmpty {
                    addressSuggestions(store.houses) { item in
                        store.selectHouse(item); houseQuery = item.name
                    }
                }
            }.frame(width: 104, alignment: .topLeading)
        }
    }

    private func addressSuggestions(_ items: [VenusOutageAddressItem], select: @escaping (VenusOutageAddressItem) -> Void) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    Button { select(item) } label: {
                        Text(item.name).font(.system(size: 13)).foregroundStyle(.white.opacity(0.9))
                            .lineLimit(2).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 12).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(store.isSearching)
                    if item.id != items.last?.id { Divider().overlay(.white.opacity(0.06)).padding(.horizontal, 12) }
                }
            }
        }.frame(height: min(CGFloat(items.count) * 45, 180))
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var groupSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(VL("Підтвердь групу", "Confirm group")).font(.system(size: 14, weight: .semibold))
            ForEach(store.groups, id: \.self) { group in
                Button { store.selectGroup(group) } label: {
                    HStack { Text(VL("Зберегти групу \(group)", "Save group \(group)")); Spacer(); Image(systemName: "checkmark") }
                        .frame(maxWidth: .infinity)
                }.buttonStyle(VenusButtonStyle(primary: true)).disabled(store.isLoading)
            }
        }
    }

    private var savedSchedule: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selection = store.selection {
                Text(selection.addressLabel).font(.system(size: 14, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(VL("Група \(selection.group)", "Group \(selection.group)")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
            HStack {
                Text(store.statusLabel).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VenusOutageStyle.color(store.currentPlanState))
                Spacer()
                Button(VL("Оновити", "Refresh"), action: store.refresh).buttonStyle(VenusButtonStyle()).disabled(store.isLoading)
            }
            if let fetched = store.fetchedAt {
                Text("\(store.isCached ? VL("Останній графік", "Last schedule") : VL("Отримано", "Received")) · \(fetched.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(localization.language.locale)))")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            }
            if store.currentPlanState == .emergency {
                Text(VL("Під час екстрених відключень наведений погодинний графік може не діяти.", "During emergency outages, the hourly schedule may not apply."))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
            }
            if store.report != nil && !store.todaySlots.isEmpty {
                Text(VL("Сьогодні · за київським часом", "Today · Kyiv time")).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                ForEach(store.todaySlots) { interval in
                    HStack(spacing: 10) {
                        Text(interval.timeRange).monospacedDigit().frame(width: 110, alignment: .leading)
                        Image(systemName: VenusOutageStyle.symbol(intervalState(interval.state))).frame(width: 17)
                        Text(interval.state.label)
                        Spacer(minLength: 0)
                    }.font(.system(size: 12)).foregroundStyle(VenusOutageStyle.color(intervalState(interval.state)))
                        .padding(.vertical, 4)
                }
            }
        }
    }

    private func intervalState(_ state: VenusOutagePlanState) -> VenusOutagePlanState {
        switch store.currentPlanState {
        case .stale, .emergency, .unknown: return store.currentPlanState
        case .noOutagePlanned, .outagePlanned: return state
        }
    }

    private func selectionLabel(_ title: String) -> some View {
        HStack { Text(title).font(.system(size: 13)).lineLimit(1); Spacer(); Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)) }
            .foregroundStyle(.white.opacity(0.85)).padding(.horizontal, 13).frame(minHeight: 44)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
    }

    private func selectionSummary(_ title: String) -> some View {
        Label(VL("Обрано: \(title)", "Selected: \(title)"), systemImage: "checkmark")
            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func addressResult(_ item: VenusOutageAddressItem, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(item.name); Spacer(); Image(systemName: selected ? "checkmark" : "chevron.right") }
                .font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(VenusButtonStyle()).disabled(store.isSearching)
    }
}

private enum VenusOutageStyle {
    static func color(_ state: VenusOutagePlanState) -> Color {
        switch state {
        case .noOutagePlanned: return Color(red: 0.4, green: 0.84, blue: 0.58)
        case .outagePlanned: return Color(red: 0.96, green: 0.49, blue: 0.4)
        case .emergency: return Color(red: 1, green: 0.65, blue: 0.37)
        case .unknown, .stale: return .white.opacity(0.5)
        }
    }

    static func symbol(_ state: VenusOutagePlanState) -> String {
        switch state {
        case .noOutagePlanned: return "checkmark"
        case .outagePlanned: return "bolt.slash"
        case .emergency: return "exclamationmark.triangle"
        case .unknown: return "questionmark"
        case .stale: return "clock"
        }
    }
}
